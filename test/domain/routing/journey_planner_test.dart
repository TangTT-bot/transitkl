import 'package:flutter_test/flutter_test.dart';
import 'package:transitkl/domain/routing/journey_planner.dart';
import 'package:transitkl/domain/routing/routing_graph.dart';

void main() {
  group('JourneyPlanner', () {
    test('adds waits and a transfer penalty, then groups ride segments', () {
      final journey = JourneyPlanner(_transferGraph()).plan(
        originStopId: 'A',
        destinationStopId: 'D',
        departureSeconds: 8 * 3600,
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
        services: [
          ...base.services.values,
          _service('green:0', headwaySeconds: 600),
        ],
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
        departureSeconds: 8 * 3600,
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
        departureSeconds: 26 * 3600,
      );

      expect(journey, isNull);
    });

    test('recognizes GTFS after-midnight frequency windows', () {
      final service = TransitService(
        id: 'night:0',
        routeId: 'night',
        directionId: 0,
        shortName: 'N',
        longName: 'Night Line',
        headways: const [
          HeadwayWindow(
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
        services: [service],
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
        departureSeconds: 30 * 60,
      );

      expect(journey, isNotNull);
      expect(journey!.totalTravelSeconds, 900);
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
    services: [
      _service('red:0', headwaySeconds: 600),
      _service('blue:0', headwaySeconds: 900),
    ],
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

TransitService _service(String id, {required int headwaySeconds}) {
  return TransitService(
    id: id,
    routeId: id.split(':').first,
    directionId: 0,
    shortName: id.split(':').first,
    longName: '${id.split(':').first} line',
    headways: [
      HeadwayWindow(
        startSeconds: 6 * 3600,
        endSeconds: 25 * 3600,
        headwaySeconds: headwaySeconds,
      ),
    ],
  );
}
