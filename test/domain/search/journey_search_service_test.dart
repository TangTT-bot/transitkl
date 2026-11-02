import 'package:flutter_test/flutter_test.dart';
import 'package:transitkl/domain/routing/routing_graph.dart';
import 'package:transitkl/domain/search/journey_search_service.dart';

void main() {
  test('groups platform IDs and searches every station platform', () {
    final service = JourneySearchService(_graph());
    final central = service.stations.singleWhere(
      (station) => station.id == 'central interchange',
    );
    final origin = service.stations.singleWhere(
      (station) => station.id == 'alpha',
    );
    final destination = service.stations.singleWhere(
      (station) => station.id == 'delta',
    );

    expect(central.stopIds, containsAll(['P1', 'P2']));

    final journey = service.search(
      origin: origin,
      destination: destination,
      departure: DateTime(2026, 7, 27, 8),
    );

    expect(journey, isNotNull);
    expect(journey!.originStopId, 'A');
    expect(journey.destinationStopId, 'D');
    expect(journey.transferCount, 1);
  });

  test('does not plan a journey to the same station group', () {
    final service = JourneySearchService(_graph());
    final station = service.stations.first;

    final journey = service.search(
      origin: station,
      destination: station,
      departure: DateTime(2026, 7, 27, 8),
    );

    expect(journey, isNull);
  });
}

RoutingGraph _graph() {
  final calendar = ServiceCalendar(
    id: 'daily',
    weekdays: const [true, true, true, true, true, true, true],
    startDate: DateTime(2026),
    endDate: DateTime(2026, 12, 31),
  );
  TransitService service(String id) => TransitService(
    id: id,
    routeId: id,
    directionId: 0,
    shortName: id,
    longName: '$id line',
    headways: const [
      HeadwayWindow(
        calendarId: 'daily',
        startSeconds: 6 * 3600,
        endSeconds: 24 * 3600,
        headwaySeconds: 600,
      ),
    ],
  );

  return RoutingGraph(
    stops: const [
      StopNode(id: 'A', name: 'ALPHA', normalizedName: 'alpha'),
      StopNode(
        id: 'P1',
        name: 'CENTRAL INTERCHANGE',
        normalizedName: 'central interchange',
      ),
      StopNode(
        id: 'P2',
        name: 'CENTRAL INTERCHANGE',
        normalizedName: 'central interchange',
      ),
      StopNode(id: 'D', name: 'DELTA', normalizedName: 'delta'),
    ],
    serviceCalendars: [calendar],
    services: [service('red'), service('blue')],
    scheduledTrips: const [],
    rideEdges: const [
      RideEdge(
        fromStopId: 'A',
        toStopId: 'P1',
        serviceId: 'red',
        travelSeconds: 300,
      ),
      RideEdge(
        fromStopId: 'P2',
        toStopId: 'D',
        serviceId: 'blue',
        travelSeconds: 300,
      ),
    ],
    transferEdges: const [
      TransferEdge(fromStopId: 'P1', toStopId: 'P2', walkSeconds: 120),
      TransferEdge(fromStopId: 'P2', toStopId: 'P1', walkSeconds: 120),
    ],
  );
}
