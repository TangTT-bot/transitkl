final class RoutingGraph {
  RoutingGraph({
    required Iterable<StopNode> stops,
    required Iterable<TransitService> services,
    required Iterable<RideEdge> rideEdges,
    required Iterable<TransferEdge> transferEdges,
  }) : stops = Map.unmodifiable({for (final stop in stops) stop.id: stop}),
       services = Map.unmodifiable({
         for (final service in services) service.id: service,
       }),
       rideEdges = List.unmodifiable(rideEdges),
       transferEdges = List.unmodifiable(transferEdges) {
    _validateReferences();
  }

  factory RoutingGraph.fromJson(Map<String, Object?> json) {
    return RoutingGraph(
      stops: _objects(json, 'stops').map(StopNode.fromJson),
      services: _objects(json, 'services').map(TransitService.fromJson),
      rideEdges: _objects(json, 'rideEdges').map(RideEdge.fromJson),
      transferEdges: _objects(json, 'transferEdges').map(TransferEdge.fromJson),
    );
  }

  final Map<String, StopNode> stops;
  final Map<String, TransitService> services;
  final List<RideEdge> rideEdges;
  final List<TransferEdge> transferEdges;

  void _validateReferences() {
    for (final service in services.values) {
      for (final window in service.headways) {
        if (window.startSeconds < 0 ||
            window.endSeconds <= window.startSeconds ||
            window.headwaySeconds <= 0) {
          throw FormatException(
            'Service ${service.id} has an invalid headway window.',
          );
        }
      }
    }
    for (final edge in rideEdges) {
      if (!stops.containsKey(edge.fromStopId) ||
          !stops.containsKey(edge.toStopId)) {
        throw FormatException(
          'Ride edge references an unknown stop: '
          '${edge.fromStopId} -> ${edge.toStopId}',
        );
      }
      if (!services.containsKey(edge.serviceId)) {
        throw FormatException(
          'Ride edge references an unknown service: ${edge.serviceId}',
        );
      }
      if (edge.travelSeconds < 0) {
        throw FormatException('Ride edge travel time must not be negative.');
      }
    }
    for (final edge in transferEdges) {
      if (!stops.containsKey(edge.fromStopId) ||
          !stops.containsKey(edge.toStopId)) {
        throw FormatException(
          'Transfer edge references an unknown stop: '
          '${edge.fromStopId} -> ${edge.toStopId}',
        );
      }
      if (edge.walkSeconds < 0) {
        throw FormatException('Transfer walk time must not be negative.');
      }
    }
  }
}

final class StopNode {
  const StopNode({
    required this.id,
    required this.name,
    this.normalizedName = '',
    this.latitude,
    this.longitude,
  });

  factory StopNode.fromJson(Map<String, Object?> json) {
    return StopNode(
      id: _string(json, 'id'),
      name: _string(json, 'name'),
      normalizedName: json['normalizedName'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }

  final String id;
  final String name;
  final String normalizedName;
  final double? latitude;
  final double? longitude;
}

final class TransitService {
  TransitService({
    required this.id,
    required this.routeId,
    required this.directionId,
    required this.shortName,
    required this.longName,
    required Iterable<HeadwayWindow> headways,
    this.routeType,
    this.color,
    this.textColor,
  }) : headways = List.unmodifiable(headways);

  factory TransitService.fromJson(Map<String, Object?> json) {
    return TransitService(
      id: _string(json, 'id'),
      routeId: _string(json, 'routeId'),
      directionId: _integer(json, 'directionId'),
      shortName: json['shortName'] as String? ?? '',
      longName: json['longName'] as String? ?? '',
      routeType: (json['routeType'] as num?)?.toInt(),
      color: json['color'] as String?,
      textColor: json['textColor'] as String?,
      headways: _objects(json, 'headways').map(HeadwayWindow.fromJson),
    );
  }

  final String id;
  final String routeId;
  final int directionId;
  final String shortName;
  final String longName;
  final int? routeType;
  final String? color;
  final String? textColor;
  final List<HeadwayWindow> headways;

  int? averageWaitSecondsAt(
    int secondsSinceServiceDay, {
    required int fallbackWaitSeconds,
  }) {
    if (headways.isEmpty) {
      return fallbackWaitSeconds;
    }

    final candidateTimes = <int>{secondsSinceServiceDay};
    if (secondsSinceServiceDay >= 0 && secondsSinceServiceDay < 4 * 3600) {
      candidateTimes.add(secondsSinceServiceDay + 24 * 3600);
    }
    final activeHeadways = [
      for (final window in headways)
        for (final time in candidateTimes)
          if (window.contains(time)) window.headwaySeconds,
    ];
    if (activeHeadways.isEmpty) {
      return null;
    }
    final shortestHeadway = activeHeadways.reduce(
      (current, value) => value < current ? value : current,
    );
    return (shortestHeadway + 1) ~/ 2;
  }
}

final class HeadwayWindow {
  const HeadwayWindow({
    required this.startSeconds,
    required this.endSeconds,
    required this.headwaySeconds,
  });

  factory HeadwayWindow.fromJson(Map<String, Object?> json) {
    return HeadwayWindow(
      startSeconds: _integer(json, 'startSeconds'),
      endSeconds: _integer(json, 'endSeconds'),
      headwaySeconds: _integer(json, 'headwaySeconds'),
    );
  }

  final int startSeconds;
  final int endSeconds;
  final int headwaySeconds;

  bool contains(int seconds) => seconds >= startSeconds && seconds < endSeconds;
}

final class RideEdge {
  const RideEdge({
    required this.fromStopId,
    required this.toStopId,
    required this.serviceId,
    required this.travelSeconds,
  });

  factory RideEdge.fromJson(Map<String, Object?> json) {
    return RideEdge(
      fromStopId: _string(json, 'fromStopId'),
      toStopId: _string(json, 'toStopId'),
      serviceId: _string(json, 'serviceId'),
      travelSeconds: _integer(json, 'travelSeconds'),
    );
  }

  final String fromStopId;
  final String toStopId;
  final String serviceId;
  final int travelSeconds;
}

final class TransferEdge {
  const TransferEdge({
    required this.fromStopId,
    required this.toStopId,
    required this.walkSeconds,
    this.distanceMetres,
    this.source = 'unknown',
  });

  factory TransferEdge.fromJson(Map<String, Object?> json) {
    return TransferEdge(
      fromStopId: _string(json, 'fromStopId'),
      toStopId: _string(json, 'toStopId'),
      walkSeconds: _integer(json, 'walkSeconds'),
      distanceMetres: (json['distanceMetres'] as num?)?.toInt(),
      source: json['source'] as String? ?? 'unknown',
    );
  }

  final String fromStopId;
  final String toStopId;
  final int walkSeconds;
  final int? distanceMetres;
  final String source;
}

List<Map<String, Object?>> _objects(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List<Object?>) {
    throw FormatException('$key must be a JSON array.');
  }
  return value
      .map((item) {
        if (item is! Map<String, Object?>) {
          throw FormatException('$key must contain JSON objects.');
        }
        return item;
      })
      .toList(growable: false);
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

int _integer(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! num) {
    throw FormatException('$key must be a number.');
  }
  return value.toInt();
}
