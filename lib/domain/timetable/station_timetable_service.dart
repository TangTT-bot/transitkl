import 'dart:math' as math;

import '../routing/routing_graph.dart';

/// Route and direction shown to a passenger. A loop uses the next stop rather
/// than advertising the boarding stop as the destination.
typedef TimetableDirection = ({String routeId, String line, String direction});

typedef TimetableDeparture = ({
  TimetableDirection service,
  int seconds,
  String? endsAt,
});

typedef TimetableFrequency = ({
  TimetableDirection service,
  int startSeconds,
  int endSeconds,
  int headwaySeconds,
  bool lineLevel,
});

typedef StationTimetable = ({
  List<TimetableDeparture> departures,
  List<TimetableFrequency> frequencies,
});

/// Read-only projection of the same graph used by the journey planner.
/// Input dates are local calendar dates. Times in the result are seconds
/// since midnight in Malaysia, with 86400 allowed as the end of a window.
final class StationTimetableService {
  StationTimetableService(this.graph);

  static const _daySeconds = Duration.secondsPerDay;
  final RoutingGraph graph;
  late final _index = _indexBoardings();

  StationTimetable forStops(Iterable<String> stopIds, DateTime date) {
    assert(stopIds.every(graph.stops.containsKey), 'Unknown timetable stop');
    // UTC here is a date-arithmetic anchor only. GTFS clock times are not
    // converted to UTC or to the reader's device timezone.
    final day = DateTime.utc(date.year, date.month, date.day);
    final activeCalendars = <(String, int), bool>{};
    bool runsOn(String calendarId, int daysBack) => activeCalendars.putIfAbsent(
      (calendarId, daysBack),
      () => graph.serviceCalendars[calendarId]!.runsOn(
        day.subtract(Duration(days: daysBack)),
      ),
    );

    final departures = <TimetableDeparture>[];
    final frequencies = <TimetableFrequency>{};
    for (final stopId in stopIds.toSet()) {
      for (final boarding in _index.scheduled[stopId] ?? const []) {
        final daysBack = boarding.seconds ~/ _daySeconds;
        if (runsOn(boarding.calendarId, daysBack)) {
          departures.add((
            service: boarding.direction,
            seconds: boarding.seconds % _daySeconds,
            endsAt: boarding.endsAt,
          ));
        }
      }
      for (final boarding in _index.frequency[stopId] ?? const []) {
        for (final window in boarding.windows) {
          final start = window.startSeconds + boarding.offsetSeconds;
          final end = window.endSeconds + boarding.offsetSeconds;
          for (
            var daysBack = start ~/ _daySeconds;
            daysBack <= (end - 1) ~/ _daySeconds;
            daysBack++
          ) {
            if (!runsOn(window.calendarId, daysBack)) continue;
            final shift = daysBack * _daySeconds;
            frequencies.add((
              service: boarding.direction,
              startSeconds: math.max(0, start - shift),
              endSeconds: math.min(_daySeconds, end - shift),
              headwaySeconds: window.headwaySeconds,
              lineLevel: boarding.lineLevel,
            ));
          }
        }
      }
    }
    return (
      departures: List.unmodifiable(
        departures..sort((a, b) => a.seconds.compareTo(b.seconds)),
      ),
      frequencies: List.unmodifiable(
        frequencies.toList()..sort((a, b) {
          final start = a.startSeconds.compareTo(b.startSeconds);
          if (start != 0) return start;
          final end = a.endSeconds.compareTo(b.endSeconds);
          if (end != 0) return end;
          return a.headwaySeconds.compareTo(b.headwaySeconds);
        }),
      ),
    );
  }

  _BoardingIndex _indexBoardings() {
    final scheduled = <String, List<_ScheduledBoarding>>{};
    final frequency = <String, List<_FrequencyBoarding>>{};
    void addFrequency(
      TransitService service,
      RideEdge edge,
      String heading, {
      required bool lineLevel,
    }) {
      (frequency[edge.fromStopId] ??= []).add((
        direction: _direction(service, heading),
        windows: service.headways,
        offsetSeconds: edge.departureOffsetSeconds,
        lineLevel: lineLevel,
      ));
    }

    final ktmOrders = _ktmLineOrders();
    for (final trip in graph.scheduledTrips) {
      final service = graph.services[trip.serviceId]!;
      final terminal = trip.stopTimes.last.stopId;
      final lineEnd = ktmOrders[service.routeId]?.lineEndFor(trip);
      final destination = _destinationName(lineEnd ?? terminal);
      final endsAt = lineEnd != null && lineEnd != terminal
          ? _destinationName(terminal)
          : null;
      final loop = trip.stopTimes.first.stopId == terminal;
      var downstreamDropOff = trip.stopTimes.last.dropOffAllowed;
      for (var index = trip.stopTimes.length - 2; index >= 0; index--) {
        final stop = trip.stopTimes[index];
        if (downstreamDropOff && stop.pickupAllowed) {
          final next = trip.stopTimes[index + 1].stopId;
          (scheduled[stop.stopId] ??= []).add((
            direction: _direction(
              service,
              loop
                  ? 'Loop via ${graph.stops[next]!.name}'
                  : 'Toward $destination',
            ),
            calendarId: trip.calendarId,
            seconds: stop.departureSeconds,
            endsAt: endsAt,
          ));
        }
        downstreamDropOff |= stop.dropOffAllowed;
      }
    }

    final byService = <String, List<RideEdge>>{};
    for (final edge in graph.rideEdges) {
      if (graph.services[edge.serviceId]!.headways.isNotEmpty) {
        (byService[edge.serviceId] ??= []).add(edge);
      }
    }
    for (final entry in byService.entries) {
      final service = graph.services[entry.key]!;
      final edges = entry.value;
      if (edges.first.sequence != null) {
        edges.sort((a, b) => a.sequence!.compareTo(b.sequence!));
        final last = edges.last.toStopId;
        final loop = last == edges.first.fromStopId;
        var downstreamDropOff = false;
        for (final edge in edges.reversed) {
          downstreamDropOff |= edge.dropOffAllowed;
          if (!edge.pickupAllowed || !downstreamDropOff) continue;
          final next = graph.stops[edge.toStopId]!.name;
          final destination = graph.stops[last]!.name;
          addFrequency(
            service,
            edge,
            loop ? 'Loop via $next' : 'Toward $destination',
            lineLevel: false,
          );
        }
      } else {
        final terminals = edges.map((edge) => edge.toStopId).toSet()
          ..removeAll(edges.map((edge) => edge.fromStopId));
        final heading = terminals.length == 1
            ? 'Toward ${graph.stops[terminals.single]!.name}'
            : 'Direction ${service.directionId + 1}';
        for (final edge in edges.where((edge) => edge.pickupAllowed)) {
          addFrequency(service, edge, heading, lineLevel: true);
        }
      }
    }
    return (scheduled: scheduled, frequency: frequency);
  }

  Map<String, _KtmLineOrder> _ktmLineOrders() {
    final longest = <String, ScheduledTrip>{};
    for (final trip in graph.scheduledTrips) {
      final route = graph.services[trip.serviceId]!.routeId;
      if (!route.startsWith('ktmb:')) continue;
      final current = longest[route];
      if (current == null || trip.stopTimes.length > current.stopTimes.length) {
        final ids = trip.stopTimes.map((time) => time.stopId).toSet();
        if (ids.length == trip.stopTimes.length) longest[route] = trip;
      }
    }
    return {
      for (final entry in longest.entries)
        entry.key: _KtmLineOrder(entry.value),
    };
  }

  String _destinationName(String id) {
    final name = graph.stops[id]!.name;
    if (!id.startsWith('ktmb:')) return name;
    // Passenger-facing names for terminals with abbreviations or alternate spellings.
    if (id == 'ktmb:55200') return 'Pelabuhan Klang';
    if (id == 'ktmb:15200') return 'Tanjung Malim';
    if (id == 'ktmb:25100') return 'Pulau Sebang / Tampin';
    return name
        .toLowerCase()
        .split(' ')
        .map((word) {
          if (word == 'kl') return 'KL';
          if (word.isEmpty) return word;
          return '${word[0].toUpperCase()}${word.substring(1)}';
        })
        .join(' ');
  }

  TimetableDirection _direction(TransitService service, String heading) {
    final useShortName =
        service.routeId.startsWith('prasarana_rapid_bus_kl:') ||
        service.routeId.startsWith('ktmb:');
    final preferredName = useShortName ? service.shortName : service.longName;
    return (
      routeId: service.routeId,
      line: preferredName.isNotEmpty
          ? preferredName
          : service.shortName.isNotEmpty
          ? service.shortName
          : service.routeId.split(':').last,
      direction: heading,
    );
  }
}

/// KTM short turns use a subsequence of the full line, and some published
/// direction IDs disagree with actual travel. Infer the grouping from the
/// ordered stops, using the longest non-loop trip across all service days.
/// A branch or reversal stays under its own actual terminus, not a guess.
final class _KtmLineOrder {
  _KtmLineOrder(ScheduledTrip reference)
    : _first = reference.stopTimes.first.stopId,
      _last = reference.stopTimes.last.stopId,
      _positions = {
        for (final (index, stop) in reference.stopTimes.indexed)
          stop.stopId: index,
      };

  final String _first;
  final String _last;
  final Map<String, int> _positions;

  String? lineEndFor(ScheduledTrip trip) {
    final start = _positions[trip.stopTimes.first.stopId];
    if (start == null) return null;
    var previous = start;
    int? sign;
    for (final stop in trip.stopTimes.skip(1)) {
      final position = _positions[stop.stopId];
      if (position == null || position == previous) return null;
      final step = position > previous ? 1 : -1;
      if (sign != null && step != sign) return null;
      sign = step;
      previous = position;
    }
    return sign == 1 ? _last : _first;
  }
}

typedef _BoardingIndex = ({
  Map<String, List<_ScheduledBoarding>> scheduled,
  Map<String, List<_FrequencyBoarding>> frequency,
});

typedef _ScheduledBoarding = ({
  TimetableDirection direction,
  String calendarId,
  int seconds,
  String? endsAt,
});

typedef _FrequencyBoarding = ({
  TimetableDirection direction,
  List<HeadwayWindow> windows,
  int offsetSeconds,
  bool lineLevel,
});
