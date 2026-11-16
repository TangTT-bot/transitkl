import 'routing_cost.dart';
import 'routing_graph.dart';

final class JourneyPlanner {
  static const int recommendedTransferPenaltySeconds = 10 * 60;

  JourneyPlanner(
    this.graph, {
    this.transferPenaltySeconds = recommendedTransferPenaltySeconds,
    this.additionalWalkingPenalty = 1,
    this.maximumJourneySeconds = 6 * Duration.secondsPerHour,
  }) {
    if (transferPenaltySeconds < 0 || additionalWalkingPenalty < 0) {
      throw ArgumentError('Routing penalties must not be negative.');
    }
    if (maximumJourneySeconds <= 0) {
      throw ArgumentError.value(maximumJourneySeconds, 'maximumJourneySeconds');
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
    // Input record order must not change an otherwise tied recommendation.
    for (final edges in _ridesFrom.values) {
      edges.sort(
        (
          a,
          b,
        ) => '${a.serviceId}:${a.sequence}:${a.toStopId}:${a.travelSeconds}'
            .compareTo(
              '${b.serviceId}:${b.sequence}:${b.toStopId}:${b.travelSeconds}',
            ),
      );
    }
    for (final edges in _transfersFrom.values) {
      edges.sort((a, b) => a.toStopId.compareTo(b.toStopId));
    }
    for (final segments in _scheduledFrom.values) {
      segments.sort(
        (a, b) =>
            '${a.trip.id}:${a.index}'.compareTo('${b.trip.id}:${b.index}'),
      );
    }
  }

  final RoutingGraph graph;
  final int transferPenaltySeconds;

  /// 1 means walking counts twice: once in elapsed time, once as inconvenience.
  final int additionalWalkingPenalty;
  final int maximumJourneySeconds;
  final Map<String, List<RideEdge>> _ridesFrom = {};
  final Map<String, List<TransferEdge>> _transfersFrom = {};
  final Map<String, List<_ScheduledSegment>> _scheduledFrom = {};

  Journey? plan({
    required String originStopId,
    required String destinationStopId,
    required DateTime departure,
  }) => planBetween(
    originStopIds: [originStopId],
    destinationStopIds: [destinationStopId],
    departure: departure,
  );

  /// One multi-source search replaces the Cartesian product of station platforms.
  Journey? planBetween({
    required Iterable<String> originStopIds,
    required Iterable<String> destinationStopIds,
    required DateTime departure,
  }) {
    final origins = originStopIds.toSet().toList()..sort();
    final destinations = destinationStopIds.toSet();
    if (origins.isEmpty ||
        destinations.isEmpty ||
        origins.any((id) => !graph.stops.containsKey(id)) ||
        destinations.any((id) => !graph.stops.containsKey(id))) {
      throw ArgumentError('Origin and destination must be known stops.');
    }

    final frontiers = <_State, List<_Label>>{};
    final frequencyWindows = <String, List<FrequencyBoardingWindow>>{};
    final latest = departure.add(Duration(seconds: maximumJourneySeconds));
    final queryDate = _dateOnly(departure);
    final queryEpoch = departure.millisecondsSinceEpoch ~/ 1000;
    final latestEpoch = latest.millisecondsSinceEpoch ~/ 1000;
    final scheduledInstances = <String, List<_ScheduledInstance>>{};
    final queue = _MinHeap();
    var nextId = 0;

    void relax({
      required _State state,
      required int elapsedSeconds,
      required int transfers,
      required int walkingSeconds,
      required _Label? parent,
      required _PathSegment? segment,
    }) {
      if (elapsedSeconds > maximumJourneySeconds) return;
      final cost = RoutingCost(
        elapsedSeconds: elapsedSeconds,
        transfers: transfers,
        walkingSeconds: walkingSeconds,
        generalizedSeconds:
            elapsedSeconds +
            transfers * transferPenaltySeconds +
            walkingSeconds * additionalWalkingPenalty,
      );
      final frontier = frontiers.putIfAbsent(state, () => []);
      if (frontier.any((label) => label.cost.dominatesOrEquals(cost))) return;
      frontier.removeWhere((label) {
        if (!cost.dominatesOrEquals(label.cost)) return false;
        label.active = false;
        return true;
      });
      final label = _Label(
        id: nextId++,
        state: state,
        cost: cost,
        parent: parent,
        segment: segment,
      );
      frontier.add(label);
      queue.add(label);
    }

    for (final origin in origins) {
      relax(
        state: _State(origin, false, null),
        elapsedSeconds: 0,
        transfers: 0,
        walkingSeconds: 0,
        parent: null,
        segment: null,
      );
    }

    while (queue.isNotEmpty) {
      final label = queue.removeFirst();
      if (!label.active) continue;
      if (destinations.contains(label.state.stopId) && label.state.canAlight) {
        return _buildJourney(label, departure);
      }

      final onBoard = label.state.activeRunId != null;
      if (onBoard && label.state.canAlight) {
        // Share a Pareto frontier after alighting, but keep useful through rides.
        relax(
          state: _State(label.state.stopId, true, null),
          elapsedSeconds: label.cost.elapsedSeconds,
          transfers: label.cost.transfers,
          walkingSeconds: label.cost.walkingSeconds,
          parent: label,
          segment: null,
        );
      }

      for (final edge
          in _transfersFrom[label.state.stopId] ?? const <TransferEdge>[]) {
        if (onBoard || !label.state.canAlight) continue;
        relax(
          state: _State(edge.toStopId, label.state.hasBoarded, null),
          elapsedSeconds: label.cost.elapsedSeconds + edge.walkSeconds,
          transfers: label.cost.transfers,
          walkingSeconds: label.cost.walkingSeconds + edge.walkSeconds,
          parent: label,
          segment: _WalkSegment(edge),
        );
      }

      void relaxRide({
        required String toStopId,
        required String serviceId,
        required String runId,
        required String vehicleJourneyId,
        required String? scheduledTripId,
        required int waitSeconds,
        required int rideSeconds,
        required bool continuesRun,
        bool canAlight = true,
      }) {
        // A change of vehicle counts even if both trains use the same line.
        final isTransfer = label.state.hasBoarded && !continuesRun;
        relax(
          state: _State(toStopId, true, runId, canAlight: canAlight),
          elapsedSeconds: label.cost.elapsedSeconds + waitSeconds + rideSeconds,
          transfers: label.cost.transfers + (isTransfer ? 1 : 0),
          walkingSeconds: label.cost.walkingSeconds,
          parent: label,
          segment: _RideSegment(
            fromStopId: label.state.stopId,
            toStopId: toStopId,
            serviceId: serviceId,
            vehicleJourneyId: vehicleJourneyId,
            scheduledTripId: scheduledTripId,
            waitSeconds: waitSeconds,
            rideSeconds: rideSeconds,
            isTransferBoarding: isTransfer,
          ),
        );
      }

      final currentTime = departure.add(
        Duration(seconds: label.cost.elapsedSeconds),
      );
      for (final edge in _ridesFrom[label.state.stopId] ?? const <RideEdge>[]) {
        final journeyId = 'frequency:${edge.serviceId}';
        final fromRunId = edge.sequence == null
            ? journeyId
            : '$journeyId:position:${edge.sequence}';
        final toRunId = edge.sequence == null
            ? journeyId
            : '$journeyId:position:${edge.sequence! + 1}';
        final continuesRun = label.state.activeRunId == fromRunId;
        if (!continuesRun && (onBoard || !edge.pickupAllowed)) {
          continue;
        }
        int? wait = continuesRun ? 0 : null;
        if (!continuesRun) {
          final windows = frequencyWindows.putIfAbsent(
            '${edge.serviceId}:${edge.departureOffsetSeconds}',
            () => graph.services[edge.serviceId]!.boardingWindowsBetween(
              departure,
              latest,
              graph.serviceCalendars,
              departureOffsetSeconds: edge.departureOffsetSeconds,
            ),
          );
          final nowSeconds = currentTime.millisecondsSinceEpoch ~/ 1000;
          for (final window in windows) {
            final candidate = window.waitAt(nowSeconds);
            if (candidate != null && (wait == null || candidate < wait)) {
              wait = candidate;
            }
          }
        }
        if (wait == null) continue;
        relaxRide(
          toStopId: edge.toStopId,
          serviceId: edge.serviceId,
          runId: toRunId,
          vehicleJourneyId: journeyId,
          scheduledTripId: null,
          waitSeconds: wait,
          rideSeconds:
              edge.travelSeconds + (continuesRun ? edge.dwellSeconds : 0),
          continuesRun: continuesRun,
          canAlight: edge.dropOffAllowed,
        );
      }

      final instances = scheduledInstances.putIfAbsent(label.state.stopId, () {
        final result = <_ScheduledInstance>[];
        for (final segment
            in _scheduledFrom[label.state.stopId] ??
                const <_ScheduledSegment>[]) {
          final calendar = graph.serviceCalendars[segment.trip.calendarId]!;
          final lastDay = _dateOnly(latest).difference(queryDate).inDays;
          for (var dayOffset = -1; dayOffset <= lastDay; dayOffset++) {
            final serviceDate = queryDate.add(Duration(days: dayOffset));
            if (!calendar.runsOn(serviceDate)) continue;
            final midnight = serviceDate.millisecondsSinceEpoch ~/ 1000;
            final scheduledDeparture = midnight + segment.from.departureSeconds;
            final scheduledArrival = midnight + segment.to.arrivalSeconds;
            if (scheduledDeparture < queryEpoch ||
                scheduledArrival > latestEpoch) {
              continue;
            }
            result.add(
              _ScheduledInstance(
                segment,
                scheduledDeparture,
                scheduledArrival,
                'scheduled:${segment.trip.id}:${_dateKey(serviceDate)}',
              ),
            );
          }
        }
        return result;
      });
      final nowEpoch = queryEpoch + label.cost.elapsedSeconds;
      for (final instance in instances) {
        if (instance.departure < nowEpoch) continue;
        final segment = instance.segment;
        final continuesRun = label.state.activeRunId == instance.fromRunId;
        if (!continuesRun && (onBoard || !segment.from.pickupAllowed)) {
          continue;
        }
        final wait = continuesRun ? 0 : instance.departure - nowEpoch;
        final ride =
            instance.arrival - (continuesRun ? nowEpoch : instance.departure);
        if (ride < 0) continue;
        relaxRide(
          toStopId: segment.to.stopId,
          serviceId: segment.trip.serviceId,
          runId: instance.toRunId,
          vehicleJourneyId: instance.prefix,
          scheduledTripId: segment.trip.id,
          waitSeconds: wait,
          rideSeconds: ride,
          continuesRun: continuesRun,
          canAlight: segment.to.dropOffAllowed,
        );
      }
    }
    return null;
  }

  Journey _buildJourney(_Label destination, DateTime departure) {
    final segments = <_PathSegment>[];
    var cursor = destination;
    while (cursor.parent != null) {
      if (cursor.segment != null) segments.add(cursor.segment!);
      cursor = cursor.parent!;
    }
    final legs = <JourneyLeg>[];
    _TransitLegBuilder? transitBuilder;
    void flushTransit() {
      if (transitBuilder != null) {
        legs.add(transitBuilder!.build());
        transitBuilder = null;
      }
    }

    for (final segment in segments.reversed) {
      switch (segment) {
        case _RideSegment():
          if (transitBuilder?.vehicleJourneyId == segment.vehicleJourneyId &&
              segment.waitSeconds == 0 &&
              !segment.isTransferBoarding) {
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
      originStopId: cursor.state.stopId,
      destinationStopId: destination.state.stopId,
      departure: departure,
      arrival: departure.add(
        Duration(seconds: destination.cost.elapsedSeconds),
      ),
      cost: destination.cost,
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
    required this.cost,
    required Iterable<JourneyLeg> legs,
  }) : legs = List.unmodifiable(legs);

  final String originStopId;
  final String destinationStopId;
  final DateTime departure;
  final DateTime arrival;
  final RoutingCost cost;
  final List<JourneyLeg> legs;

  int get totalTravelSeconds => cost.elapsedSeconds;
  int get generalizedCostSeconds => cost.generalizedSeconds;
  int get transferCount => cost.transfers;
  int get totalWalkingSeconds => cost.walkingSeconds;

  int get totalWaitingSeconds => legs.whereType<TransitLeg>().fold(
    0,
    (total, leg) => total + leg.waitSeconds,
  );

  /// Time riding and walking, excluding all boarding waits.
  int get totalMovingSeconds => totalTravelSeconds - totalWaitingSeconds;

  /// The time at each boarding stop is derived from the planned journey, not
  /// from the original search time alone. Include earlier rides and walks.
  Iterable<JourneyLegTiming> get timedLegs sync* {
    var start = departure;
    for (final leg in legs) {
      final timing = JourneyLegTiming(leg: leg, startsAt: start);
      yield timing;
      start = timing.endsAt;
    }
  }

  int? get totalWalkingMetres {
    var metres = 0;
    for (final leg in legs.whereType<WalkingLeg>()) {
      if (leg.distanceMetres == null) return null;
      metres += leg.distanceMetres!;
    }
    return metres;
  }
}

final class JourneyLegTiming {
  const JourneyLegTiming({required this.leg, required this.startsAt});

  final JourneyLeg leg;
  final DateTime startsAt;

  DateTime? get boardsAt => switch (leg) {
    TransitLeg(:final waitSeconds) => startsAt.add(
      Duration(seconds: waitSeconds),
    ),
    WalkingLeg() => null,
  };

  DateTime get endsAt => startsAt.add(Duration(seconds: leg.durationSeconds));
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

final class _ScheduledInstance {
  _ScheduledInstance(this.segment, this.departure, this.arrival, this.prefix)
    : fromRunId = '$prefix:${segment.index}',
      toRunId = '$prefix:${segment.index + 1}';
  final _ScheduledSegment segment;
  final int departure;
  final int arrival;
  final String prefix;
  final String fromRunId;
  final String toRunId;
}

final class _State {
  const _State(
    this.stopId,
    this.hasBoarded,
    this.activeRunId, {
    this.canAlight = true,
  });
  final String stopId;
  final bool hasBoarded;
  final String? activeRunId;
  final bool canAlight;
  @override
  bool operator ==(Object other) =>
      other is _State &&
      stopId == other.stopId &&
      hasBoarded == other.hasBoarded &&
      activeRunId == other.activeRunId &&
      canAlight == other.canAlight;
  @override
  int get hashCode => Object.hash(stopId, hasBoarded, activeRunId, canAlight);
}

final class _Label {
  _Label({
    required this.id,
    required this.state,
    required this.cost,
    required this.parent,
    required this.segment,
  });
  final int id;
  final _State state;
  final RoutingCost cost;
  // Immutable parent-label references preserve each path after Pareto pruning.
  final _Label? parent;
  final _PathSegment? segment;
  bool active = true;
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

final class _MinHeap {
  final List<_Label> _entries = [];
  bool get isNotEmpty => _entries.isNotEmpty;
  void add(_Label entry) {
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

  _Label removeFirst() {
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

  int _compare(_Label first, _Label second) {
    var result = first.cost.compareTo(second.cost);
    if (result != 0) return result;
    result = first.state.stopId.compareTo(second.state.stopId);
    if (result != 0) return result;
    result = (first.state.activeRunId ?? '').compareTo(
      second.state.activeRunId ?? '',
    );
    if (result != 0) return result;
    return first.id.compareTo(second.id);
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
int _dateKey(DateTime value) =>
    value.year * 10000 + value.month * 100 + value.day;
