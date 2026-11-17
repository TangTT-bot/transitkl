import 'package:flutter_test/flutter_test.dart';
import 'package:transitkl/data/routing/routing_graph_repository.dart';
import 'package:transitkl/domain/routing/routing_graph.dart';
import 'package:transitkl/domain/timetable/station_timetable_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TransitDataBundle data;
  late StationTimetableService service;

  setUpAll(() async {
    data = await AssetRoutingGraphRepository().load();
    service = StationTimetableService(data.graph);
  });

  test('Setia Jaya groups every KTM departure by actual travel direction', () {
    final timetable = service.forStops(['ktmb:53600'], DateTime(2026, 11, 16));
    final toPortKlang = timetable.departures.where(
      (row) => row.service.direction == 'Toward Pelabuhan Klang',
    );
    final toTanjungMalim = timetable.departures.where(
      (row) => row.service.direction == 'Toward Tanjung Malim',
    );
    final klangTimes = toPortKlang.map((row) => row.seconds);
    expect(timetable.frequencies, isEmpty);
    expect(
      timetable.departures.map((row) => row.service).toSet(),
      hasLength(2),
    );
    expect(klangTimes.where((time) => time >= 13 * 3600).first, 64500);
    expect(klangTimes, orderedEquals([...klangTimes]..sort()));
    expect(
      toPortKlang.singleWhere((row) => row.seconds == 64500).endsAt,
      isNull,
    );
    expect(
      toPortKlang.singleWhere((row) => row.seconds == 68100).endsAt,
      'Klang',
    );
    // The published directionId on the 19:25 trip points the other way.
    expect(klangTimes, contains(69900));
    expect(toTanjungMalim.map((row) => row.seconds), isNot(contains(69900)));
    expect(
      toTanjungMalim.singleWhere((row) => row.seconds == 79800).endsAt,
      'KL Sentral',
    );

    final expired = service.forStops(['ktmb:53600'], DateTime(2026, 11, 18));
    expect(expired.departures, isEmpty);
    expect(expired.frequencies, isEmpty);
  });

  test('Rapid Rail and Sunway BRT show line-level frequency only', () {
    final date = DateTime(2026, 11, 16);
    for (final (stop, line) in [
      ('KJ29', 'LRT Kelana Jaya Line'),
      ('BRT4', 'BRT Sunway Line'),
    ]) {
      final rows = service.forStops(['prasarana_rapid_rail:$stop'], date);
      expect(rows.departures, isEmpty);
      expect(rows.frequencies, isNotEmpty);
      expect(rows.frequencies.every((row) => row.lineLevel), isTrue);
      expect(rows.frequencies.map((row) => row.service.line).toSet(), {line});
      expect(
        rows.frequencies.map((row) => row.service.direction).toSet(),
        hasLength(2),
      );
    }
  });

  test('published T200 uses an offset window and a loop direction', () {
    final edge = data.graph.rideEdges.firstWhere(
      (edge) =>
          edge.serviceId.contains(':T2000::') &&
          edge.sequence == 1 &&
          edge.pickupAllowed,
    );
    final result = service.forStops([edge.fromStopId], DateTime(2026, 11, 16));
    final windows = result.frequencies
        .where((row) => row.service.line == 'T200')
        .toList();
    expect(windows, isNotEmpty);
    expect(windows.every((row) => !row.lineLevel), isTrue);
    expect(windows.first.service.direction, startsWith('Loop via '));
    expect(windows.first.startSeconds, 21600 + edge.departureOffsetSeconds);
    expect(windows.first.headwaySeconds, 1800);
  });

  test('a published fixed-time bus loop appears at midnight', () {
    final rows = service.forStops([
      'prasarana_rapid_bus_kl:1002606',
    ], DateTime(2026, 11, 17));
    final bus = rows.departures.singleWhere((row) => row.service.line == '651');
    expect(bus.seconds, 0);
    expect(bus.service.direction, startsWith('Loop via '));
  });

  test(
    'overnight departures use the previous service day and its exceptions',
    () {
      final midnight = StationTimetableService(_overnightGraph());
      final friday = midnight.forStops(['B'], DateTime(2026, 11, 13));
      final saturday = midnight.forStops(['B'], DateTime(2026, 11, 14));
      final cancelledSaturday = midnight.forStops([
        'B',
      ], DateTime(2026, 11, 21));
      expect(friday.departures, isEmpty);
      expect(friday.frequencies.single.startSeconds, 23 * 3600 + 58 * 60);
      expect(friday.frequencies.single.endSeconds, 86400);
      expect(saturday.departures.single.seconds, 600);
      expect(saturday.departures.single.service.direction, 'Toward C');
      expect(saturday.frequencies.single.startSeconds, 0);
      expect(saturday.frequencies.single.endSeconds, 480);
      expect(cancelledSaturday.departures, isEmpty);
      expect(cancelledSaturday.frequencies, isEmpty);
      for (final stop in ['A', 'C']) {
        final result = midnight.forStops([stop], DateTime(2026, 11, 13));
        expect(result.departures, isEmpty);
        expect(result.frequencies, isEmpty);
      }
    },
  );
}

RoutingGraph _overnightGraph() => RoutingGraph(
  stops: const [
    StopNode(id: 'A', name: 'A'),
    StopNode(id: 'B', name: 'B'),
    StopNode(id: 'C', name: 'C'),
  ],
  services: [
    TransitService(
      id: 'night',
      routeId: 'night',
      directionId: 0,
      shortName: 'N1',
      longName: 'Night service',
      headways: const [
        HeadwayWindow(
          calendarId: 'friday',
          startSeconds: 85980,
          endSeconds: 86580,
          headwaySeconds: 300,
        ),
      ],
    ),
  ],
  serviceCalendars: [
    ServiceCalendar(
      id: 'friday',
      weekdays: const [false, false, false, false, true, false, false],
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 30),
      exceptions: {DateTime(2026, 11, 20): false},
    ),
  ],
  scheduledTrips: [
    ScheduledTrip(
      id: 'night-trip',
      serviceId: 'night',
      calendarId: 'friday',
      headsign: '',
      stopTimes: const [
        ScheduledStopTime(
          stopId: 'A',
          arrivalSeconds: 86700,
          departureSeconds: 86700,
          pickupAllowed: false,
        ),
        ScheduledStopTime(
          stopId: 'B',
          arrivalSeconds: 87000,
          departureSeconds: 87000,
        ),
        ScheduledStopTime(
          stopId: 'C',
          arrivalSeconds: 87300,
          departureSeconds: 87300,
        ),
      ],
    ),
  ],
  rideEdges: const [
    RideEdge(
      fromStopId: 'A',
      toStopId: 'B',
      serviceId: 'night',
      travelSeconds: 300,
      sequence: 0,
      pickupAllowed: false,
    ),
    RideEdge(
      fromStopId: 'B',
      toStopId: 'C',
      serviceId: 'night',
      travelSeconds: 300,
      sequence: 1,
      departureOffsetSeconds: 300,
    ),
  ],
  transferEdges: const [],
);
