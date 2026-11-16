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

    return planner.planBetween(
      originStopIds: origin.stopIds,
      destinationStopIds: destination.stopIds,
      departure: departure,
    );
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
    final normalizedQuery = _compact(query);
    return normalizedQuery.isNotEmpty &&
        _compact(name).contains(normalizedQuery);
  }

  int queryRank(String query) {
    final nameKey = _compact(name);
    final queryKey = _compact(query);
    return nameKey == queryKey
        ? 0
        : nameKey.startsWith(queryKey)
        ? 1
        : 2;
  }

  @override
  bool operator ==(Object other) => other is StationGroup && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

String _compact(String value) =>
    value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

/// Exact stations must not disappear behind many bus stop substring matches.
List<StationGroup> searchStations(
  Iterable<StationGroup> stations,
  String query, {
  int limit = 12,
}) {
  final matches = stations
      .where((station) => station.matchesQuery(query))
      .toList();
  matches.sort((a, b) {
    final rank = a.queryRank(query).compareTo(b.queryRank(query));
    return rank != 0 ? rank : a.name.compareTo(b.name);
  });
  return matches.take(limit).toList(growable: false);
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
      final operatorName = _operatorName(component);
      final ambiguous =
          separate &&
          components
                  .where(
                    (candidate) => _operatorName(candidate) == operatorName,
                  )
                  .length >
              1;
      stations.add(
        StationGroup(
          id: separate ? '${entry.key}::${component.first}' : entry.key,
          name:
              '${_displayName(graph.stops[component.first]!.name)}'
              '${separate ? ' ($operatorName${ambiguous ? ' ${component.first.split(':').last}' : ''})' : ''}',
          stopIds: List.unmodifiable(component),
        ),
      );
    }
  }
  stations.sort((first, second) => first.name.compareTo(second.name));
  return List.unmodifiable(stations);
}

String _operatorName(List<String> ids) =>
    ids.every((id) => id.startsWith('ktmb:'))
    ? 'KTM Komuter'
    : ids.every((id) => id.startsWith('prasarana_rapid_bus_kl:'))
    ? 'Rapid Bus KL'
    : 'Rapid Rail';

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
