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
        if (candidate != null &&
            (best == null || candidate.cost.compareTo(best.cost) < 0)) {
          best = candidate;
        }
      }
    }
    return best;
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

  /// Ignore spacing and punctuation when matching station abbreviations, e.g.
  /// USJ7/USJ 7 or SunU-Monash/SunU Monash.
  bool matchesQuery(String query) {
    String compact(String value) =>
        value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    final normalizedQuery = compact(query);
    return normalizedQuery.isNotEmpty &&
        compact(name).contains(normalizedQuery);
  }

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

  final connections = <String, Set<String>>{};
  for (final edge in graph.transferEdges) {
    (connections[edge.fromStopId] ??= {}).add(edge.toStopId);
    (connections[edge.toStopId] ??= {}).add(edge.fromStopId);
  }
  final stations = <StationGroup>[];
  for (final entry in grouped.entries) {
    final remaining = {for (final stop in entry.value) stop.id};
    final components = <List<String>>[];
    while (remaining.isNotEmpty) {
      final component = <String>[];
      final pending = [remaining.first];
      remaining.remove(pending.first);
      while (pending.isNotEmpty) {
        final stopId = pending.removeLast();
        component.add(stopId);
        for (final neighbor in connections[stopId] ?? const <String>{}) {
          if (remaining.remove(neighbor)) pending.add(neighbor);
        }
      }
      component.sort();
      components.add(component);
    }
    for (final component in components) {
      final separate = components.length > 1;
      final operatorName = component.every((id) => id.startsWith('ktmb:'))
          ? 'KTM Komuter'
          : 'Rapid Rail';
      stations.add(
        StationGroup(
          id: separate ? '${entry.key}::${component.first}' : entry.key,
          name:
              '${_displayName(graph.stops[component.first]!.name)}'
              '${separate ? ' ($operatorName)' : ''}',
          stopIds: List.unmodifiable(component),
        ),
      );
    }
  }
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
