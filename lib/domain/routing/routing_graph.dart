final class RoutingGraph {
  RoutingGraph({
    required Iterable<StopNode> stops,
    required Iterable<ServiceCalendar> serviceCalendars,
    required Iterable<TransitService> services,
    required Iterable<ScheduledTrip> scheduledTrips,
    required Iterable<RideEdge> rideEdges,
    required Iterable<TransferEdge> transferEdges,
  }) : stops = Map.unmodifiable({for (final stop in stops) stop.id: stop}),
       serviceCalendars = Map.unmodifiable({
         for (final calendar in serviceCalendars) calendar.id: calendar,
       }),
       services = Map.unmodifiable({
         for (final service in services) service.id: service,
       }),
       scheduledTrips = List.unmodifiable(scheduledTrips),
       rideEdges = List.unmodifiable(rideEdges),
       transferEdges = List.unmodifiable(transferEdges) {
    _validateReferences();
  }

  factory RoutingGraph.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 2) {
      throw FormatException(
        'Unsupported routing graph schema: ${json['schemaVersion']}. '
        'Rebuild the graph with the current GTFS pipeline.',
      );
    }
    return RoutingGraph(
      stops: _objects(json, 'stops').map(StopNode.fromJson),
      serviceCalendars: _objects(
        json,
        'serviceCalendars',
      ).map(ServiceCalendar.fromJson),
      services: _objects(json, 'services').map(TransitService.fromJson),
      scheduledTrips: _objects(
        json,
        'scheduledTrips',
      ).map(ScheduledTrip.fromJson),
      rideEdges: _objects(json, 'rideEdges').map(RideEdge.fromJson),
      transferEdges: _objects(json, 'transferEdges').map(TransferEdge.fromJson),
    );
  }

  final Map<String, StopNode> stops;
  final Map<String, ServiceCalendar> serviceCalendars;
  final Map<String, TransitService> services;
  final List<ScheduledTrip> scheduledTrips;
  final List<RideEdge> rideEdges;
  final List<TransferEdge> transferEdges;

  void _validateReferences() {
    for (final service in services.values) {
      for (final window in service.headways) {
        if (!serviceCalendars.containsKey(window.calendarId)) {
          throw FormatException(
            'Service ${service.id} references unknown calendar '
            '${window.calendarId}.',
          );
        }
        if (window.startSeconds < 0 ||
            window.endSeconds <= window.startSeconds ||
            window.headwaySeconds <= 0) {
          throw FormatException(
            'Service ${service.id} has an invalid headway window.',
          );
        }
      }
    }
    for (final trip in scheduledTrips) {
      if (!services.containsKey(trip.serviceId)) {
        throw FormatException(
          'Trip ${trip.id} references unknown service ${trip.serviceId}.',
        );
      }
      if (!serviceCalendars.containsKey(trip.calendarId)) {
        throw FormatException(
          'Trip ${trip.id} references unknown calendar ${trip.calendarId}.',
        );
      }
      if (trip.stopTimes.length < 2) {
        throw FormatException('Trip ${trip.id} must contain at least 2 stops.');
      }
      for (var index = 0; index < trip.stopTimes.length; index++) {
        final stopTime = trip.stopTimes[index];
        if (!stops.containsKey(stopTime.stopId)) {
          throw FormatException(
            'Trip ${trip.id} references unknown stop ${stopTime.stopId}.',
          );
        }
        if (stopTime.arrivalSeconds < 0 ||
            stopTime.departureSeconds < stopTime.arrivalSeconds) {
          throw FormatException('Trip ${trip.id} contains invalid stop times.');
        }
        if (index > 0 &&
            stopTime.arrivalSeconds <
                trip.stopTimes[index - 1].departureSeconds) {
          throw FormatException(
            'Trip ${trip.id} stop times are not chronological.',
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

final class ServiceCalendar {
  ServiceCalendar({
    required this.id,
    required Iterable<bool> weekdays,
    required this.startDate,
    required this.endDate,
    Map<DateTime, bool> exceptions = const {},
  }) : weekdays = List.unmodifiable(weekdays),
       exceptions = Map.unmodifiable({
         for (final entry in exceptions.entries)
           _dateKey(entry.key): entry.value,
       }) {
    if (this.weekdays.length != DateTime.daysPerWeek) {
      throw ArgumentError.value(
        this.weekdays,
        'weekdays',
        'Must contain Monday through Sunday',
      );
    }
  }

  factory ServiceCalendar.fromJson(Map<String, Object?> json) {
    final weekdaysValue = json['weekdays'];
    if (weekdaysValue is! List<Object?> ||
        weekdaysValue.any((value) => value is! bool)) {
      throw const FormatException('weekdays must be a JSON boolean array.');
    }
    final exceptions = <DateTime, bool>{};
    for (final exception in _objects(json, 'exceptions')) {
      final running = exception['isRunning'];
      if (running is! bool) {
        throw const FormatException('isRunning must be a boolean.');
      }
      exceptions[_date(exception, 'date')!] = running;
    }
    return ServiceCalendar(
      id: _string(json, 'id'),
      weekdays: weekdaysValue.cast<bool>(),
      startDate: _date(json, 'startDate'),
      endDate: _date(json, 'endDate'),
      exceptions: exceptions,
    );
  }

  final String id;
  final List<bool> weekdays;
  final DateTime? startDate;
  final DateTime? endDate;
  final Map<int, bool> exceptions;

  bool runsOn(DateTime date) {
    final normalized = _dateOnly(date);
    final exception = exceptions[_dateKey(normalized)];
    if (exception != null) return exception;
    if (startDate == null || endDate == null) return false;
    if (normalized.isBefore(startDate!) || normalized.isAfter(endDate!)) {
      return false;
    }
    return weekdays[normalized.weekday - DateTime.monday];
  }
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
    DateTime departure,
    Map<String, ServiceCalendar> calendars,
  ) {
    final seconds = _secondsSinceMidnight(departure);
    final date = _dateOnly(departure);
    final candidates = [
      (date: date, seconds: seconds),
      (
        date: date.subtract(const Duration(days: 1)),
        seconds: seconds + Duration.secondsPerDay,
      ),
    ];
    final activeHeadways = [
      for (final window in headways)
        for (final candidate in candidates)
          if (window.contains(candidate.seconds) &&
              calendars[window.calendarId]!.runsOn(candidate.date))
            window.headwaySeconds,
    ];
    if (activeHeadways.isEmpty) return null;
    final shortestHeadway = activeHeadways.reduce(
      (current, value) => value < current ? value : current,
    );
    return (shortestHeadway + 1) ~/ 2;
  }
}

final class HeadwayWindow {
  const HeadwayWindow({
    required this.calendarId,
    required this.startSeconds,
    required this.endSeconds,
    required this.headwaySeconds,
  });

  factory HeadwayWindow.fromJson(Map<String, Object?> json) {
    return HeadwayWindow(
      calendarId: _string(json, 'calendarId'),
      startSeconds: _integer(json, 'startSeconds'),
      endSeconds: _integer(json, 'endSeconds'),
      headwaySeconds: _integer(json, 'headwaySeconds'),
    );
  }

  final String calendarId;
  final int startSeconds;
  final int endSeconds;
  final int headwaySeconds;

  bool contains(int seconds) => seconds >= startSeconds && seconds < endSeconds;
}

final class ScheduledTrip {
  ScheduledTrip({
    required this.id,
    required this.serviceId,
    required this.calendarId,
    required this.headsign,
    required Iterable<ScheduledStopTime> stopTimes,
  }) : stopTimes = List.unmodifiable(stopTimes);

  factory ScheduledTrip.fromJson(Map<String, Object?> json) {
    return ScheduledTrip(
      id: _string(json, 'id'),
      serviceId: _string(json, 'serviceId'),
      calendarId: _string(json, 'calendarId'),
      headsign: json['headsign'] as String? ?? '',
      stopTimes: _objects(json, 'stopTimes').map(ScheduledStopTime.fromJson),
    );
  }

  final String id;
  final String serviceId;
  final String calendarId;
  final String headsign;
  final List<ScheduledStopTime> stopTimes;
}

final class ScheduledStopTime {
  const ScheduledStopTime({
    required this.stopId,
    required this.arrivalSeconds,
    required this.departureSeconds,
  });

  factory ScheduledStopTime.fromJson(Map<String, Object?> json) {
    return ScheduledStopTime(
      stopId: _string(json, 'stopId'),
      arrivalSeconds: _integer(json, 'arrivalSeconds'),
      departureSeconds: _integer(json, 'departureSeconds'),
    );
  }

  final String stopId;
  final int arrivalSeconds;
  final int departureSeconds;
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

DateTime? _date(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('$key must be an ISO date string.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('Invalid date for $key: $value');
  return _dateOnly(parsed);
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

int _dateKey(DateTime value) =>
    value.year * 10000 + value.month * 100 + value.day;

int _secondsSinceMidnight(DateTime value) =>
    value.hour * Duration.secondsPerHour +
    value.minute * Duration.secondsPerMinute +
    value.second;
