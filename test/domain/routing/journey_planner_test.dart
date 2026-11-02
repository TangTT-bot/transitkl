import 'package:flutter_test/flutter_test.dart';
import 'package:transitkl/domain/routing/journey_planner.dart';
import 'package:transitkl/domain/routing/routing_graph.dart';

void main() {
  group('JourneyPlanner frequency routing', () {
    test('adds waits and a transfer penalty, then groups ride segments', () {
      final journey = JourneyPlanner(_transferGraph()).plan(
        originStopId: 'A',
        destinationStopId: 'D',
        departure: DateTime(2026, 7, 27, 8),
      );

      expect(journey, isNotNull);
      expect(journey!.totalTravelSeconds, 1890);
      expect(journey.generalizedCostSeconds, 2190);
      expect(journey.transferCount, 1);
      expect(journey.legs, hasLength(3));

      final firstRide = journey.legs[0] as TransitLeg;
      expect(firstRide.serviceId, 'red:0');
      expect(firstRide.waitSeconds, 300);
      expect(firstRide.rideSeconds, 600);
      expect(firstRide.stopIds, ['A', 'B', 'P1']);
      expect(firstRide.isTransferBoarding, isFalse);
      expect(firstRide.isScheduled, isFalse);

      final walk = journey.legs[1] as WalkingLeg;
      expect(walk.walkSeconds, 120);

      final secondRide = journey.legs[2] as TransitLeg;
      expect(secondRide.serviceId, 'blue:0');
      expect(secondRide.waitSeconds, 450);
      expect(secondRide.rideSeconds, 420);
      expect(secondRide.isTransferBoarding, isTrue);
    });

    test('can prefer a slower direct journey after transfer inconvenience', () {
      final base = _transferGraph();
      final graph = RoutingGraph(
        stops: base.stops.values,
        serviceCalendars: base.serviceCalendars.values,
        services: [
          ...base.services.values,
          _service('green:0', headwaySeconds: 600),
        ],
        scheduledTrips: const [],
        rideEdges: [
          ...base.rideEdges,
          const RideEdge(
            fromStopId: 'A',
            toStopId: 'D',
            serviceId: 'green:0',
            travelSeconds: 1800,
          ),
        ],
        transferEdges: base.transferEdges,
      );

      final journey = JourneyPlanner(graph).plan(
        originStopId: 'A',
        destinationStopId: 'D',
        departure: DateTime(2026, 7, 27, 8),
      );

      expect(journey, isNotNull);
      expect(journey!.totalTravelSeconds, 2100);
      expect(journey.generalizedCostSeconds, 2100);
      expect(journey.transferCount, 0);
      expect((journey.legs.single as TransitLeg).serviceId, 'green:0');
    });

    test('does not board a frequency service outside its operating window', () {
      final journey = JourneyPlanner(_transferGraph()).plan(
        originStopId: 'A',
        destinationStopId: 'P1',
        departure: DateTime(2026, 7, 28, 2),
      );

      expect(journey, isNull);
    });

    test('does not run a frequency service on an inactive calendar date', () {
      final graph = _singleLineGraph(
        calendar: _calendar(
          weekdays: const [true, true, true, true, true, false, false],
        ),
      );

      final journey = JourneyPlanner(graph).plan(
        originStopId: 'A',
        destinationStopId: 'D',
        departure: DateTime(2026, 8, 1, 8),
      );

      expect(journey, isNull);
    });

    test('recognizes a previous service day after midnight', () {
      final service = TransitService(
        id: 'night:0',
        routeId: 'night',
        directionId: 0,
        shortName: 'N',
        longName: 'Night Line',
        headways: const [
          HeadwayWindow(
            calendarId: 'calendar',
            startSeconds: 24 * 3600,
            endSeconds: 26 * 3600,
            headwaySeconds: 1200,
          ),
        ],
      );
      final graph = RoutingGraph(
        stops: const [
          StopNode(id: 'A', name: 'Alpha'),
          StopNode(id: 'D', name: 'Delta'),
        ],
        serviceCalendars: [
          _calendar(
            weekdays: const [true, false, false, false, false, false, false],
          ),
        ],
        services: [service],
        scheduledTrips: const [],
        rideEdges: const [
          RideEdge(
            fromStopId: 'A',
            toStopId: 'D',
            serviceId: 'night:0',
            travelSeconds: 300,
          ),
        ],
        transferEdges: const [],
      );

      final journey = JourneyPlanner(graph).plan(
        originStopId: 'A',
        destinationStopId: 'D',
        departure: DateTime(2026, 7, 28, 0, 30),
      );

      expect(journey, isNotNull);
      expect(journey!.totalTravelSeconds, 900);
    });
  });

  group('JourneyPlanner exact schedule routing', () {
    test('waits for the next trip and stays aboard through dwell time', () {
      final journey = JourneyPlanner(_scheduledGraph()).plan(
        originStopId: 'A',
        destinationStopId: 'D',
        departure: DateTime(2026, 7, 27, 8),
      );

      expect(journey, isNotNull);
      expect(journey!.arrival, DateTime(2026, 7, 27, 8, 35));
      expect(journey.totalTravelSeconds, 35 * 60);
      expect(journey.transferCount, 0);
      expect(journey.legs, hasLength(1));
      final ride = journey.legs.single as TransitLeg;
      expect(ride.scheduledTripId, 'exact-trip');
      expect(ride.waitSeconds, 10 * 60);
      expect(ride.rideSeconds, 25 * 60);
      expect(ride.stopIds, ['A', 'B', 'D']);
    });

    test('applies removed and added calendar exceptions', () {
      final graph = _scheduledGraph(
        exceptions: {DateTime(2026, 7, 27): false, DateTime(2026, 8, 1): true},
      );
      final planner = JourneyPlanner(graph);

      final removed = planner.plan(
        originStopId: 'A',
        destinationStopId: 'D',
        departure: DateTime(2026, 7, 27, 8),
      );
      final added = planner.plan(
        originStopId: 'A',
        destinationStopId: 'D',
        departure: DateTime(2026, 8, 1, 8),
      );

      expect(removed, isNull);
      expect(added, isNotNull);
      expect(added!.arrival, DateTime(2026, 8, 1, 8, 35));
    });

    test('finds a 24-hour trip from the previous service day', () {
      final graph = _scheduledGraph(
        stopTimes: const [
          ScheduledStopTime(
            stopId: 'A',
            arrivalSeconds: 24 * 3600 + 30 * 60,
            departureSeconds: 24 * 3600 + 30 * 60,
          ),
          ScheduledStopTime(
            stopId: 'D',
            arrivalSeconds: 25 * 3600,
            departureSeconds: 25 * 3600,
          ),
        ],
      );

      final journey = JourneyPlanner(graph).plan(
        originStopId: 'A',
        destinationStopId: 'D',
        departure: DateTime(2026, 7, 28, 0, 20),
      );

      expect(journey, isNotNull);
      expect(journey!.arrival, DateTime(2026, 7, 28, 1));
      expect(journey.totalTravelSeconds, 40 * 60);
    });
  });
}

RoutingGraph _transferGraph() {
  return RoutingGraph(
    stops: const [
      StopNode(id: 'A', name: 'Alpha'),
      StopNode(id: 'B', name: 'Beta'),
      StopNode(id: 'P1', name: 'Central Interchange'),
      StopNode(id: 'P2', name: 'Central Interchange'),
      StopNode(id: 'D', name: 'Delta'),
    ],
    serviceCalendars: [_calendar()],
    services: [
      _service('red:0', headwaySeconds: 600),
      _service('blue:0', headwaySeconds: 900),
    ],
    scheduledTrips: const [],
    rideEdges: const [
      RideEdge(
        fromStopId: 'A',
        toStopId: 'B',
        serviceId: 'red:0',
        travelSeconds: 300,
      ),
      RideEdge(
        fromStopId: 'B',
        toStopId: 'P1',
        serviceId: 'red:0',
        travelSeconds: 300,
      ),
      RideEdge(
        fromStopId: 'P2',
        toStopId: 'D',
        serviceId: 'blue:0',
        travelSeconds: 420,
      ),
    ],
    transferEdges: const [
      TransferEdge(fromStopId: 'P1', toStopId: 'P2', walkSeconds: 120),
      TransferEdge(fromStopId: 'P2', toStopId: 'P1', walkSeconds: 120),
    ],
  );
}

RoutingGraph _singleLineGraph({required ServiceCalendar calendar}) {
  return RoutingGraph(
    stops: const [
      StopNode(id: 'A', name: 'Alpha'),
      StopNode(id: 'D', name: 'Delta'),
    ],
    serviceCalendars: [calendar],
    services: [_service('red:0', headwaySeconds: 600)],
    scheduledTrips: const [],
    rideEdges: const [
      RideEdge(
        fromStopId: 'A',
        toStopId: 'D',
        serviceId: 'red:0',
        travelSeconds: 300,
      ),
    ],
    transferEdges: const [],
  );
}

RoutingGraph _scheduledGraph({
  Map<DateTime, bool> exceptions = const {},
  List<ScheduledStopTime> stopTimes = const [
    ScheduledStopTime(
      stopId: 'A',
      arrivalSeconds: 8 * 3600 + 10 * 60,
      departureSeconds: 8 * 3600 + 10 * 60,
    ),
    ScheduledStopTime(
      stopId: 'B',
      arrivalSeconds: 8 * 3600 + 20 * 60,
      departureSeconds: 8 * 3600 + 22 * 60,
    ),
    ScheduledStopTime(
      stopId: 'D',
      arrivalSeconds: 8 * 3600 + 35 * 60,
      departureSeconds: 8 * 3600 + 35 * 60,
    ),
  ],
}) {
  return RoutingGraph(
    stops: const [
      StopNode(id: 'A', name: 'Alpha'),
      StopNode(id: 'B', name: 'Beta'),
      StopNode(id: 'D', name: 'Delta'),
    ],
    serviceCalendars: [
      _calendar(
        weekdays: const [true, true, true, true, true, false, false],
        exceptions: exceptions,
      ),
    ],
    services: [
      TransitService(
        id: 'exact:0',
        routeId: 'exact',
        directionId: 0,
        shortName: 'EX',
        longName: 'Exact Line',
        headways: const [],
      ),
    ],
    scheduledTrips: [
      ScheduledTrip(
        id: 'exact-trip',
        serviceId: 'exact:0',
        calendarId: 'calendar',
        headsign: 'Delta',
        stopTimes: stopTimes,
      ),
    ],
    rideEdges: const [
      RideEdge(
        fromStopId: 'A',
        toStopId: 'B',
        serviceId: 'exact:0',
        travelSeconds: 600,
      ),
      RideEdge(
        fromStopId: 'B',
        toStopId: 'D',
        serviceId: 'exact:0',
        travelSeconds: 780,
      ),
    ],
    transferEdges: const [],
  );
}

TransitService _service(String id, {required int headwaySeconds}) {
  return TransitService(
    id: id,
    routeId: id.split(':').first,
    directionId: 0,
    shortName: id.split(':').first,
    longName: '${id.split(':').first} line',
    headways: [
      HeadwayWindow(
        calendarId: 'calendar',
        startSeconds: 6 * 3600,
        endSeconds: 25 * 3600,
        headwaySeconds: headwaySeconds,
      ),
    ],
  );
}

ServiceCalendar _calendar({
  List<bool> weekdays = const [true, true, true, true, true, true, true],
  Map<DateTime, bool> exceptions = const {},
}) {
  return ServiceCalendar(
    id: 'calendar',
    weekdays: weekdays,
    startDate: DateTime(2026),
    endDate: DateTime(2026, 12, 31),
    exceptions: exceptions,
  );
}
