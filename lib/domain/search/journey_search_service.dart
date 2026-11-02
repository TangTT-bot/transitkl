import '../routing/journey_planner.dart';
import '../routing/routing_graph.dart';

final class JourneySearchService {
  JourneySearchService(this.graph)
    : planner = JourneyPlanner(graph),
      stations = _buildStations(graph);

  final RoutingGraph graph;
  final JourneyPlanner planner;
  final List<StationGroup> stations;

  Journey? search({
    required StationGroup origin,
    required StationGroup destination,
    required DateTime departure,
  }) {
    if (origin.id == destination.id) return null;

    Journey? best;
    for (final originStopId in origin.stopIds) {
      for (final destinationStopId in destination.stopIds) {
        final candidate = planner.plan(
          originStopId: originStopId,
          destinationStopId: destinationStopId,
          departure: departure,
        );
        if (candidate != null && _isBetter(candidate, best)) {
          best = candidate;
        }
      }
    }
    return best;
  }

  static bool _isBetter(Journey candidate, Journey? current) {
    if (current == null) return true;
    if (candidate.generalizedCostSeconds != current.generalizedCostSeconds) {
      return candidate.generalizedCostSeconds < current.generalizedCostSeconds;
    }
    if (candidate.totalTravelSeconds != current.totalTravelSeconds) {
      return candidate.totalTravelSeconds < current.totalTravelSeconds;
    }
    return candidate.transferCount < current.transferCount;
  }
}

final class StationGroup {
  const StationGroup({
    required this.id,
    required this.name,
    required this.stopIds,
  });

  final String id;
  final String name;
  final List<String> stopIds;

  @override
  bool operator ==(Object other) => other is StationGroup && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

List<StationGroup> _buildStations(RoutingGraph graph) {
  final boardableStopIds = <String>{
    for (final edge in graph.rideEdges) ...[edge.fromStopId, edge.toStopId],
    for (final trip in graph.scheduledTrips)
      for (final stopTime in trip.stopTimes) stopTime.stopId,
  };
  final grouped = <String, List<StopNode>>{};
  for (final stop in graph.stops.values) {
    if (!boardableStopIds.contains(stop.id)) continue;
    final key = stop.normalizedName.isEmpty
        ? stop.name.trim().toLowerCase()
        : stop.normalizedName;
    (grouped[key] ??= []).add(stop);
  }

  final stations = [
    for (final entry in grouped.entries)
      StationGroup(
        id: entry.key,
        name: _displayName(entry.value.first.name),
        stopIds: List.unmodifiable(entry.value.map((stop) => stop.id)),
      ),
  ];
  stations.sort((first, second) => first.name.compareTo(second.name));
  return List.unmodifiable(stations);
}

String _displayName(String value) {
  return value
      .trim()
      .split(RegExp(r'\s+'))
      .map((word) {
        if (word.isEmpty) return word;
        if (word.length <= 5 &&
            word == word.toUpperCase() &&
            RegExp(r'[A-Z]').hasMatch(word)) {
          return word;
        }
        final lower = word.toLowerCase();
        return '${lower[0].toUpperCase()}${lower.substring(1)}';
      })
      .join(' ');
}
