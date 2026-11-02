import 'routing_graph.dart';

final class JourneyPlanner {
  JourneyPlanner(
    this.graph, {
    this.transferPenaltySeconds = 300,
    this.fallbackWaitSeconds = 600,
  }) {
    if (transferPenaltySeconds < 0) {
      throw ArgumentError.value(
        transferPenaltySeconds,
        'transferPenaltySeconds',
        'Must not be negative',
      );
    }
    if (fallbackWaitSeconds < 0) {
      throw ArgumentError.value(
        fallbackWaitSeconds,
        'fallbackWaitSeconds',
        'Must not be negative',
      );
    }
    for (final edge in graph.rideEdges) {
      (_ridesFrom[edge.fromStopId] ??= []).add(edge);
    }
    for (final edge in graph.transferEdges) {
      (_transfersFrom[edge.fromStopId] ??= []).add(edge);
    }
  }

  final RoutingGraph graph;
  final int transferPenaltySeconds;
  final int fallbackWaitSeconds;
  final Map<String, List<RideEdge>> _ridesFrom = {};
  final Map<String, List<TransferEdge>> _transfersFrom = {};

  Journey? plan({
    required String originStopId,
    required String destinationStopId,
    required int departureSeconds,
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
    if (departureSeconds < 0) {
      throw ArgumentError.value(
        departureSeconds,
        'departureSeconds',
        'Must not be negative',
      );
    }

    final origin = _State(originStopId, null);
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
      if (!identical(labels[entry.state], entry.label)) {
        continue;
      }
      if (entry.state.stopId == destinationStopId) {
        return _buildJourney(
          origin: origin,
          destination: entry.state,
          destinationLabel: entry.label,
          previous: previous,
          departureSeconds: departureSeconds,
        );
      }

      for (final edge
          in _transfersFrom[entry.state.stopId] ?? const <TransferEdge>[]) {
        final destination = _State(edge.toStopId, entry.state.serviceId);
        final candidate = _Label(
          generalizedCostSeconds:
              entry.label.generalizedCostSeconds + edge.walkSeconds,
          elapsedSeconds: entry.label.elapsedSeconds + edge.walkSeconds,
          transferCount: entry.label.transferCount,
        );
        _relax(
          destination: destination,
          candidate: candidate,
          priorState: entry.state,
          segment: _WalkSegment(edge),
          labels: labels,
          previous: previous,
          queue: queue,
        );
      }

      for (final edge in _ridesFrom[entry.state.stopId] ?? const <RideEdge>[]) {
        final changesService =
            entry.state.serviceId != null &&
            entry.state.serviceId != edge.serviceId;
        final continuesService = entry.state.serviceId == edge.serviceId;
        var waitSeconds = 0;
        if (!continuesService) {
          final service = graph.services[edge.serviceId]!;
          final currentTime = departureSeconds + entry.label.elapsedSeconds;
          final wait = service.averageWaitSecondsAt(
            currentTime,
            fallbackWaitSeconds: fallbackWaitSeconds,
          );
          if (wait == null) {
            continue;
          }
          waitSeconds = wait;
        }

        final penalty = changesService ? transferPenaltySeconds : 0;
        final destination = _State(edge.toStopId, edge.serviceId);
        final candidate = _Label(
          generalizedCostSeconds:
              entry.label.generalizedCostSeconds +
              waitSeconds +
              edge.travelSeconds +
              penalty,
          elapsedSeconds:
              entry.label.elapsedSeconds + waitSeconds + edge.travelSeconds,
          transferCount: entry.label.transferCount + (changesService ? 1 : 0),
        );
        _relax(
          destination: destination,
          candidate: candidate,
          priorState: entry.state,
          segment: _RideSegment(
            edge: edge,
            waitSeconds: waitSeconds,
            isTransferBoarding: changesService,
          ),
          labels: labels,
          previous: previous,
          queue: queue,
        );
      }
    }
    return null;
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
    final existing = labels[destination];
    if (existing != null && !_isBetter(candidate, existing)) {
      return;
    }
    labels[destination] = candidate;
    previous[destination] = _Previous(priorState, segment);
    queue.add(_QueueEntry(destination, candidate));
  }

  Journey _buildJourney({
    required _State origin,
    required _State destination,
    required _Label destinationLabel,
    required Map<_State, _Previous> previous,
    required int departureSeconds,
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
    final segments = reversedSegments.reversed.toList(growable: false);
    final legs = <JourneyLeg>[];
    _TransitLegBuilder? transitBuilder;

    void flushTransit() {
      final builder = transitBuilder;
      if (builder != null) {
        legs.add(builder.build());
        transitBuilder = null;
      }
    }

    for (final segment in segments) {
      switch (segment) {
        case _RideSegment():
          if (transitBuilder != null &&
              transitBuilder!.serviceId == segment.edge.serviceId &&
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
      departureSeconds: departureSeconds,
      arrivalSeconds: departureSeconds + destinationLabel.elapsedSeconds,
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
    required this.departureSeconds,
    required this.arrivalSeconds,
    required this.totalTravelSeconds,
    required this.generalizedCostSeconds,
    required this.transferCount,
    required Iterable<JourneyLeg> legs,
  }) : legs = List.unmodifiable(legs);

  final String originStopId;
  final String destinationStopId;
  final int departureSeconds;
  final int arrivalSeconds;
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
    required this.waitSeconds,
    required this.rideSeconds,
    required this.isTransferBoarding,
    required Iterable<String> stopIds,
  }) : stopIds = List.unmodifiable(stopIds);

  final String serviceId;
  final int waitSeconds;
  final int rideSeconds;
  final bool isTransferBoarding;
  final List<String> stopIds;

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

final class _State {
  const _State(this.stopId, this.serviceId);

  final String stopId;
  final String? serviceId;

  @override
  bool operator ==(Object other) =>
      other is _State && stopId == other.stopId && serviceId == other.serviceId;

  @override
  int get hashCode => Object.hash(stopId, serviceId);
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
    required this.edge,
    required this.waitSeconds,
    required this.isTransferBoarding,
  });

  final RideEdge edge;
  final int waitSeconds;
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
    : serviceId = first.edge.serviceId,
      fromStopId = first.edge.fromStopId,
      toStopId = first.edge.toStopId,
      waitSeconds = first.waitSeconds,
      rideSeconds = first.edge.travelSeconds,
      isTransferBoarding = first.isTransferBoarding,
      stopIds = [first.edge.fromStopId, first.edge.toStopId];

  final String serviceId;
  final String fromStopId;
  String toStopId;
  final int waitSeconds;
  int rideSeconds;
  final bool isTransferBoarding;
  final List<String> stopIds;

  void add(_RideSegment segment) {
    toStopId = segment.edge.toStopId;
    rideSeconds += segment.edge.travelSeconds;
    stopIds.add(segment.edge.toStopId);
  }

  TransitLeg build() => TransitLeg(
    fromStopId: fromStopId,
    toStopId: toStopId,
    serviceId: serviceId,
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
      if (_compare(_entries[parent], entry) <= 0) {
        break;
      }
      _entries[index] = _entries[parent];
      index = parent;
    }
    _entries[index] = entry;
  }

  _QueueEntry removeFirst() {
    final result = _entries.first;
    final last = _entries.removeLast();
    if (_entries.isEmpty) {
      return result;
    }
    var index = 0;
    while (true) {
      final left = index * 2 + 1;
      if (left >= _entries.length) {
        break;
      }
      final right = left + 1;
      var child = left;
      if (right < _entries.length &&
          _compare(_entries[right], _entries[left]) < 0) {
        child = right;
      }
      if (_compare(last, _entries[child]) <= 0) {
        break;
      }
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
    return (first.state.serviceId ?? '').compareTo(
      second.state.serviceId ?? '',
    );
  }
}
