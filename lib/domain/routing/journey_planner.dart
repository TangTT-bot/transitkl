import 'routing_graph.dart';

final class JourneyPlanner {
  /// Ranking penalty for changing services in the default Recommended profile.
  /// It affects route choice, never the displayed arrival time.
  static const int recommendedTransferPenaltySeconds = 10 * 60;

  JourneyPlanner(
    this.graph, {
    this.transferPenaltySeconds = recommendedTransferPenaltySeconds,
    this.maximumJourneySeconds = 6 * Duration.secondsPerHour,
  }) {
    if (transferPenaltySeconds < 0) {
      throw ArgumentError.value(
        transferPenaltySeconds,
        'transferPenaltySeconds',
        'Must not be negative',
      );
    }
    if (maximumJourneySeconds <= 0) {
      throw ArgumentError.value(
        maximumJourneySeconds,
        'maximumJourneySeconds',
        'Must be positive',
      );
    }
    for (final edge in graph.rideEdges) {
      (_ridesFrom[edge.fromStopId] ??= []).add(edge);
    }
    for (final edge in graph.transferEdges) {
      (_transfersFrom[edge.fromStopId] ??= []).add(edge);
    }
    for (final trip in graph.scheduledTrips) {
      for (var index = 0; index < trip.stopTimes.length - 1; index++) {
        final segment = _ScheduledSegment(trip, index);
        (_scheduledFrom[segment.from.stopId] ??= []).add(segment);
      }
    }
  }

  final RoutingGraph graph;
  final int transferPenaltySeconds;
  final int maximumJourneySeconds;
  final Map<String, List<RideEdge>> _ridesFrom = {};
  final Map<String, List<TransferEdge>> _transfersFrom = {};
  final Map<String, List<_ScheduledSegment>> _scheduledFrom = {};

  Journey? plan({
    required String originStopId,
    required String destinationStopId,
    required DateTime departure,
  }) {
    if (!graph.stops.containsKey(originStopId)) {
      throw ArgumentError.value(originStopId, 'originStopId', 'Unknown stop');
    }
    if (!graph.stops.containsKey(destinationStopId)) {
      throw ArgumentError.value(
        destinationStopId,
        'destinationStopId',
        'Unknown stop',
      );
    }

    final origin = _State(originStopId, null, null);
    final labels = <_State, _Label>{};
    final previous = <_State, _Previous>{};
    final queue = _MinHeap();
    final originLabel = const _Label(
      generalizedCostSeconds: 0,
      elapsedSeconds: 0,
      transferCount: 0,
    );
    labels[origin] = originLabel;
    queue.add(_QueueEntry(origin, originLabel));

    while (queue.isNotEmpty) {
      final entry = queue.removeFirst();
      if (!identical(labels[entry.state], entry.label)) continue;
      if (entry.state.stopId == destinationStopId) {
        return _buildJourney(
          origin: origin,
          destination: entry.state,
          destinationLabel: entry.label,
          previous: previous,
          departure: departure,
        );
      }

      _relaxTransfers(entry, labels, previous, queue);
      _relaxFrequencyRides(entry, departure, labels, previous, queue);
      _relaxScheduledRides(entry, departure, labels, previous, queue);
    }
    return null;
  }

  void _relaxTransfers(
    _QueueEntry entry,
    Map<_State, _Label> labels,
    Map<_State, _Previous> previous,
    _MinHeap queue,
  ) {
    for (final edge
        in _transfersFrom[entry.state.stopId] ?? const <TransferEdge>[]) {
      final destination = _State(
        edge.toStopId,
        entry.state.lastServiceId,
        null,
      );
      _relax(
        destination: destination,
        candidate: _Label(
          generalizedCostSeconds:
              entry.label.generalizedCostSeconds + edge.walkSeconds,
          elapsedSeconds: entry.label.elapsedSeconds + edge.walkSeconds,
          transferCount: entry.label.transferCount,
        ),
        priorState: entry.state,
        segment: _WalkSegment(edge),
        labels: labels,
        previous: previous,
        queue: queue,
      );
    }
  }

  void _relaxFrequencyRides(
    _QueueEntry entry,
    DateTime departure,
    Map<_State, _Label> labels,
    Map<_State, _Previous> previous,
    _MinHeap queue,
  ) {
    for (final edge in _ridesFrom[entry.state.stopId] ?? const <RideEdge>[]) {
      final journeyId = 'frequency:${edge.serviceId}';
      final continuesService = entry.state.activeRunId == journeyId;
      var waitSeconds = 0;
      if (!continuesService) {
        final currentTime = departure.add(
          Duration(seconds: entry.label.elapsedSeconds),
        );
        final wait = graph.services[edge.serviceId]!.averageWaitSecondsAt(
          currentTime,
          graph.serviceCalendars,
        );
        if (wait == null) continue;
        waitSeconds = wait;
      }
      _relaxRide(
        entry: entry,
        fromStopId: edge.fromStopId,
        toStopId: edge.toStopId,
        serviceId: edge.serviceId,
        activeRunId: journeyId,
        vehicleJourneyId: journeyId,
        scheduledTripId: null,
        waitSeconds: waitSeconds,
        rideSeconds: edge.travelSeconds,
        labels: labels,
        previous: previous,
        queue: queue,
      );
    }
  }

  void _relaxScheduledRides(
    _QueueEntry entry,
    DateTime departure,
    Map<_State, _Label> labels,
    Map<_State, _Previous> previous,
    _MinHeap queue,
  ) {
    final currentTime = departure.add(
      Duration(seconds: entry.label.elapsedSeconds),
    );
    final currentDate = _dateOnly(currentTime);
    for (final segment
        in _scheduledFrom[entry.state.stopId] ?? const <_ScheduledSegment>[]) {
      final calendar = graph.serviceCalendars[segment.trip.calendarId]!;
      for (final dayOffset in const [-1, 0, 1]) {
        final serviceDate = currentDate.add(Duration(days: dayOffset));
        if (!calendar.runsOn(serviceDate)) continue;

        final scheduledDeparture = serviceDate.add(
          Duration(seconds: segment.from.departureSeconds),
        );
        final scheduledArrival = serviceDate.add(
          Duration(seconds: segment.to.arrivalSeconds),
        );
        final runPrefix =
            'scheduled:${segment.trip.id}:${_dateKey(serviceDate)}';
        final fromRunId = '$runPrefix:${segment.index}';
        final toRunId = '$runPrefix:${segment.index + 1}';
        final continuesRun = entry.state.activeRunId == fromRunId;
        if (scheduledDeparture.isBefore(currentTime)) continue;

        final waitSeconds = continuesRun
            ? 0
            : scheduledDeparture.difference(currentTime).inSeconds;
        final rideSeconds = continuesRun
            ? scheduledArrival.difference(currentTime).inSeconds
            : scheduledArrival.difference(scheduledDeparture).inSeconds;
        if (rideSeconds < 0) continue;

        _relaxRide(
          entry: entry,
          fromStopId: segment.from.stopId,
          toStopId: segment.to.stopId,
          serviceId: segment.trip.serviceId,
          activeRunId: toRunId,
          vehicleJourneyId: runPrefix,
          scheduledTripId: segment.trip.id,
          waitSeconds: waitSeconds,
          rideSeconds: rideSeconds,
          labels: labels,
          previous: previous,
          queue: queue,
        );
      }
    }
  }

  void _relaxRide({
    required _QueueEntry entry,
    required String fromStopId,
    required String toStopId,
    required String serviceId,
    required String activeRunId,
    required String vehicleJourneyId,
    required String? scheduledTripId,
    required int waitSeconds,
    required int rideSeconds,
    required Map<_State, _Label> labels,
    required Map<_State, _Previous> previous,
    required _MinHeap queue,
  }) {
    final changesService =
        entry.state.lastServiceId != null &&
        entry.state.lastServiceId != serviceId;
    final penalty = changesService ? transferPenaltySeconds : 0;
    _relax(
      destination: _State(toStopId, serviceId, activeRunId),
      candidate: _Label(
        generalizedCostSeconds:
            entry.label.generalizedCostSeconds +
            waitSeconds +
            rideSeconds +
            penalty,
        elapsedSeconds: entry.label.elapsedSeconds + waitSeconds + rideSeconds,
        transferCount: entry.label.transferCount + (changesService ? 1 : 0),
      ),
      priorState: entry.state,
      segment: _RideSegment(
        fromStopId: fromStopId,
        toStopId: toStopId,
        serviceId: serviceId,
        vehicleJourneyId: vehicleJourneyId,
        scheduledTripId: scheduledTripId,
        waitSeconds: waitSeconds,
        rideSeconds: rideSeconds,
        isTransferBoarding: changesService,
      ),
      labels: labels,
      previous: previous,
      queue: queue,
    );
  }

  void _relax({
    required _State destination,
    required _Label candidate,
    required _State priorState,
    required _PathSegment segment,
    required Map<_State, _Label> labels,
    required Map<_State, _Previous> previous,
    required _MinHeap queue,
  }) {
    if (candidate.elapsedSeconds > maximumJourneySeconds) return;
    final existing = labels[destination];
    if (existing != null && !_isBetter(candidate, existing)) return;
    labels[destination] = candidate;
    previous[destination] = _Previous(priorState, segment);
    queue.add(_QueueEntry(destination, candidate));
  }

  Journey _buildJourney({
    required _State origin,
    required _State destination,
    required _Label destinationLabel,
    required Map<_State, _Previous> previous,
    required DateTime departure,
  }) {
    final reversedSegments = <_PathSegment>[];
    var cursor = destination;
    while (cursor != origin) {
      final step = previous[cursor];
      if (step == null) {
        throw StateError('Routing predecessor chain is incomplete.');
      }
      reversedSegments.add(step.segment);
      cursor = step.state;
    }
    final legs = <JourneyLeg>[];
    _TransitLegBuilder? transitBuilder;

    void flushTransit() {
      final builder = transitBuilder;
      if (builder != null) {
        legs.add(builder.build());
        transitBuilder = null;
      }
    }

    for (final segment in reversedSegments.reversed) {
      switch (segment) {
        case _RideSegment():
          if (transitBuilder?.vehicleJourneyId == segment.vehicleJourneyId &&
              segment.waitSeconds == 0) {
            transitBuilder!.add(segment);
          } else {
            flushTransit();
            transitBuilder = _TransitLegBuilder(segment);
          }
        case _WalkSegment():
          flushTransit();
          legs.add(
            WalkingLeg(
              fromStopId: segment.edge.fromStopId,
              toStopId: segment.edge.toStopId,
              walkSeconds: segment.edge.walkSeconds,
              distanceMetres: segment.edge.distanceMetres,
            ),
          );
      }
    }
    flushTransit();

    return Journey(
      originStopId: origin.stopId,
      destinationStopId: destination.stopId,
      departure: departure,
      arrival: departure.add(
        Duration(seconds: destinationLabel.elapsedSeconds),
      ),
      totalTravelSeconds: destinationLabel.elapsedSeconds,
      generalizedCostSeconds: destinationLabel.generalizedCostSeconds,
      transferCount: destinationLabel.transferCount,
      legs: legs,
    );
  }
}

final class Journey {
  Journey({
    required this.originStopId,
    required this.destinationStopId,
    required this.departure,
    required this.arrival,
    required this.totalTravelSeconds,
    required this.generalizedCostSeconds,
    required this.transferCount,
    required Iterable<JourneyLeg> legs,
  }) : legs = List.unmodifiable(legs);

  final String originStopId;
  final String destinationStopId;
  final DateTime departure;
  final DateTime arrival;
  final int totalTravelSeconds;
  final int generalizedCostSeconds;
  final int transferCount;
  final List<JourneyLeg> legs;
}

sealed class JourneyLeg {
  const JourneyLeg({required this.fromStopId, required this.toStopId});

  final String fromStopId;
  final String toStopId;
  int get durationSeconds;
}

final class TransitLeg extends JourneyLeg {
  TransitLeg({
    required super.fromStopId,
    required super.toStopId,
    required this.serviceId,
    required this.scheduledTripId,
    required this.waitSeconds,
    required this.rideSeconds,
    required this.isTransferBoarding,
    required Iterable<String> stopIds,
  }) : stopIds = List.unmodifiable(stopIds);

  final String serviceId;
  final String? scheduledTripId;
  final int waitSeconds;
  final int rideSeconds;
  final bool isTransferBoarding;
  final List<String> stopIds;

  bool get isScheduled => scheduledTripId != null;

  @override
  int get durationSeconds => waitSeconds + rideSeconds;
}

final class WalkingLeg extends JourneyLeg {
  const WalkingLeg({
    required super.fromStopId,
    required super.toStopId,
    required this.walkSeconds,
    this.distanceMetres,
  });

  final int walkSeconds;
  final int? distanceMetres;

  @override
  int get durationSeconds => walkSeconds;
}

final class _ScheduledSegment {
  const _ScheduledSegment(this.trip, this.index);

  final ScheduledTrip trip;
  final int index;
  ScheduledStopTime get from => trip.stopTimes[index];
  ScheduledStopTime get to => trip.stopTimes[index + 1];
}

final class _State {
  const _State(this.stopId, this.lastServiceId, this.activeRunId);

  final String stopId;
  final String? lastServiceId;
  final String? activeRunId;

  @override
  bool operator ==(Object other) =>
      other is _State &&
      stopId == other.stopId &&
      lastServiceId == other.lastServiceId &&
      activeRunId == other.activeRunId;

  @override
  int get hashCode => Object.hash(stopId, lastServiceId, activeRunId);
}

final class _Label {
  const _Label({
    required this.generalizedCostSeconds,
    required this.elapsedSeconds,
    required this.transferCount,
  });

  final int generalizedCostSeconds;
  final int elapsedSeconds;
  final int transferCount;
}

bool _isBetter(_Label candidate, _Label existing) {
  if (candidate.generalizedCostSeconds != existing.generalizedCostSeconds) {
    return candidate.generalizedCostSeconds < existing.generalizedCostSeconds;
  }
  if (candidate.elapsedSeconds != existing.elapsedSeconds) {
    return candidate.elapsedSeconds < existing.elapsedSeconds;
  }
  return candidate.transferCount < existing.transferCount;
}

sealed class _PathSegment {
  const _PathSegment();
}

final class _RideSegment extends _PathSegment {
  const _RideSegment({
    required this.fromStopId,
    required this.toStopId,
    required this.serviceId,
    required this.vehicleJourneyId,
    required this.scheduledTripId,
    required this.waitSeconds,
    required this.rideSeconds,
    required this.isTransferBoarding,
  });

  final String fromStopId;
  final String toStopId;
  final String serviceId;
  final String vehicleJourneyId;
  final String? scheduledTripId;
  final int waitSeconds;
  final int rideSeconds;
  final bool isTransferBoarding;
}

final class _WalkSegment extends _PathSegment {
  const _WalkSegment(this.edge);

  final TransferEdge edge;
}

final class _Previous {
  const _Previous(this.state, this.segment);

  final _State state;
  final _PathSegment segment;
}

final class _TransitLegBuilder {
  _TransitLegBuilder(_RideSegment first)
    : vehicleJourneyId = first.vehicleJourneyId,
      serviceId = first.serviceId,
      scheduledTripId = first.scheduledTripId,
      fromStopId = first.fromStopId,
      toStopId = first.toStopId,
      waitSeconds = first.waitSeconds,
      rideSeconds = first.rideSeconds,
      isTransferBoarding = first.isTransferBoarding,
      stopIds = [first.fromStopId, first.toStopId];

  final String vehicleJourneyId;
  final String serviceId;
  final String? scheduledTripId;
  final String fromStopId;
  String toStopId;
  final int waitSeconds;
  int rideSeconds;
  final bool isTransferBoarding;
  final List<String> stopIds;

  void add(_RideSegment segment) {
    toStopId = segment.toStopId;
    rideSeconds += segment.rideSeconds;
    stopIds.add(segment.toStopId);
  }

  TransitLeg build() => TransitLeg(
    fromStopId: fromStopId,
    toStopId: toStopId,
    serviceId: serviceId,
    scheduledTripId: scheduledTripId,
    waitSeconds: waitSeconds,
    rideSeconds: rideSeconds,
    isTransferBoarding: isTransferBoarding,
    stopIds: stopIds,
  );
}

final class _QueueEntry {
  const _QueueEntry(this.state, this.label);

  final _State state;
  final _Label label;
}

final class _MinHeap {
  final List<_QueueEntry> _entries = [];

  bool get isNotEmpty => _entries.isNotEmpty;

  void add(_QueueEntry entry) {
    _entries.add(entry);
    var index = _entries.length - 1;
    while (index > 0) {
      final parent = (index - 1) ~/ 2;
      if (_compare(_entries[parent], entry) <= 0) break;
      _entries[index] = _entries[parent];
      index = parent;
    }
    _entries[index] = entry;
  }

  _QueueEntry removeFirst() {
    final result = _entries.first;
    final last = _entries.removeLast();
    if (_entries.isEmpty) return result;
    var index = 0;
    while (true) {
      final left = index * 2 + 1;
      if (left >= _entries.length) break;
      final right = left + 1;
      var child = left;
      if (right < _entries.length &&
          _compare(_entries[right], _entries[left]) < 0) {
        child = right;
      }
      if (_compare(last, _entries[child]) <= 0) break;
      _entries[index] = _entries[child];
      index = child;
    }
    _entries[index] = last;
    return result;
  }

  static int _compare(_QueueEntry first, _QueueEntry second) {
    var result = first.label.generalizedCostSeconds.compareTo(
      second.label.generalizedCostSeconds,
    );
    if (result != 0) return result;
    result = first.label.elapsedSeconds.compareTo(second.label.elapsedSeconds);
    if (result != 0) return result;
    result = first.label.transferCount.compareTo(second.label.transferCount);
    if (result != 0) return result;
    result = first.state.stopId.compareTo(second.state.stopId);
    if (result != 0) return result;
    result = (first.state.lastServiceId ?? '').compareTo(
      second.state.lastServiceId ?? '',
    );
    if (result != 0) return result;
    return (first.state.activeRunId ?? '').compareTo(
      second.state.activeRunId ?? '',
    );
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

int _dateKey(DateTime value) =>
    value.year * 10000 + value.month * 100 + value.day;
