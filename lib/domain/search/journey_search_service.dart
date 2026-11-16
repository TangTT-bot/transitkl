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

enum StationMode {
  lrt('LRT'),
  mrt('MRT'),
  monorail('Monorail'),
  rapidRail('Rapid Rail'),
  sunwayBrt('Sunway BRT'),
  ktmKomuter('KTM Komuter'),
  rapidBus('Rapid Bus');

  const StationMode(this.label);

  final String label;
}

final class StationGroup {
  const StationGroup({
    required this.id,
    required this.name,
    required this.stopIds,
    this.modes = const [],
    this.disambiguatingStopId,
  });

  final String id;
  final String name;
  final List<String> stopIds;
  final List<StationMode> modes;
  final String? disambiguatingStopId;

  String get displayLabel {
    final details = [
      if (modes.isNotEmpty) modes.map((mode) => mode.label).join(' + '),
      ?disambiguatingStopId,
    ];
    return details.isEmpty ? name : '$name (${details.join(' · ')})';
  }

  /// Ignore spacing and punctuation when matching station abbreviations, e.g.
  /// USJ7/USJ 7 or SunU-Monash/SunU Monash.
  bool matchesQuery(String query) => _queryRank(_compact(query)) != null;

  int? _queryRank(String queryKey) {
    if (queryKey.isEmpty) return null;
    final nameKey = _compact(name);
    if (nameKey == queryKey) return 0;
    if (nameKey.startsWith(queryKey)) return 1;
    if (nameKey.contains(queryKey)) return 2;
    // Also accept a pasted name with its mode label, without matching every
    // station that happens to display the same mode.
    if (queryKey.startsWith(nameKey)) {
      final labelKey = _compact(displayLabel);
      if (labelKey == queryKey) return 0;
      if (labelKey.startsWith(queryKey)) return 1;
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is StationGroup && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

final _nonSearchCharacters = RegExp('[^a-z0-9]');

String _compact(String value) =>
    value.toLowerCase().replaceAll(_nonSearchCharacters, '');

/// Exact stations must not disappear behind many bus stop substring matches.
List<StationGroup> searchStations(
  Iterable<StationGroup> stations,
  String query, {
  int limit = 12,
}) {
  final queryKey = _compact(query);
  if (queryKey.isEmpty) return const [];
  final matches = [
    for (final station in stations)
      if (station._queryRank(queryKey) case final rank?) (station, rank),
  ];
  matches.sort((a, b) {
    final rank = a.$2.compareTo(b.$2);
    return rank != 0 ? rank : a.$1.displayLabel.compareTo(b.$1.displayLabel);
  });
  return matches.take(limit).map((match) => match.$1).toList(growable: false);
}

List<StationGroup> _buildStations(RoutingGraph graph) {
  final modeByService = {
    for (final service in graph.services.values)
      service.id: _modeForRoute(service.routeId),
  };
  final modesByStop = <String, Set<StationMode>>{};
  void recordVisit(String stopId, String serviceId) {
    final modes = modesByStop.putIfAbsent(stopId, () => {});
    final mode = modeByService[serviceId];
    if (mode != null) modes.add(mode);
  }

  for (final edge in graph.rideEdges) {
    recordVisit(edge.fromStopId, edge.serviceId);
    recordVisit(edge.toStopId, edge.serviceId);
  }
  for (final trip in graph.scheduledTrips) {
    for (final stopTime in trip.stopTimes) {
      recordVisit(stopTime.stopId, trip.serviceId);
    }
  }

  final grouped = <String, List<StopNode>>{};
  for (final stop in graph.stops.values) {
    if (!modesByStop.containsKey(stop.id)) continue;
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
    final modesByComponent = [
      for (final component in components)
        [
          for (final mode in StationMode.values)
            if (component.any((stopId) => modesByStop[stopId]!.contains(mode)))
              mode,
        ],
    ];
    final modeKeys = modesByComponent
        .map((modes) => modes.map((mode) => mode.name).join(','))
        .toList();
    final modeCounts = <String, int>{};
    for (final key in modeKeys) {
      modeCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
    }
    for (final (index, component) in components.indexed) {
      final separate = components.length > 1;
      final ambiguous = modeCounts[modeKeys[index]]! > 1;
      stations.add(
        StationGroup(
          id: separate ? '${entry.key}::${component.first}' : entry.key,
          name: _displayName(graph.stops[component.first]!.name),
          stopIds: List.unmodifiable(component),
          modes: List.unmodifiable(modesByComponent[index]),
          disambiguatingStopId: ambiguous
              ? component.first.split(':').last
              : null,
        ),
      );
    }
  }
  stations.sort(
    (first, second) => first.displayLabel.compareTo(second.displayLabel),
  );
  return List.unmodifiable(stations);
}

// The rail feed uses the same GTFS route type for LRT, MRT and Monorail.
// Map its published route IDs to the passenger-facing modes.
StationMode? _modeForRoute(String routeId) {
  final parts = routeId.split(':');
  return switch (parts.first) {
    'prasarana_rapid_rail' => switch (parts.last) {
      'AG' || 'KJ' || 'PH' || 'SA' => StationMode.lrt,
      'KGL' || 'PYL' => StationMode.mrt,
      'MR' => StationMode.monorail,
      'BRT' => StationMode.sunwayBrt,
      _ => StationMode.rapidRail,
    },
    'ktmb' => StationMode.ktmKomuter,
    'prasarana_rapid_bus_kl' => StationMode.rapidBus,
    _ => null,
  };
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
