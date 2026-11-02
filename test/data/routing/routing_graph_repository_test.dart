import 'package:flutter_test/flutter_test.dart';
import 'package:transitkl/data/routing/routing_graph_repository.dart';
import 'package:transitkl/domain/routing/journey_planner.dart';
import 'package:transitkl/domain/search/journey_search_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the bundled Rapid Rail routing graph', () async {
    final data = await AssetRoutingGraphRepository().load();

    expect(data.feed.id, 'prasarana_rapid_rail');
    expect(data.feed.serviceDateEnd, DateTime(2026, 12, 31));
    expect(data.graph.stops, hasLength(187));
    expect(data.graph.services, hasLength(16));
    expect(data.graph.rideEdges, hasLength(358));
    expect(data.graph.transferEdges, hasLength(62));
  });

  test('prefers direct KJL from Putra Heights to Pasar Seni', () async {
    final data = await AssetRoutingGraphRepository().load();
    final search = JourneySearchService(data.graph);
    final origin = search.stations.singleWhere(
      (station) => station.id == 'putra heights',
    );
    final destination = search.stations.singleWhere(
      (station) => station.id == 'pasar seni',
    );

    final journey = search.search(
      origin: origin,
      destination: destination,
      departure: DateTime(2026, 11, 2, 8),
    );

    expect(journey, isNotNull);
    expect(journey!.originStopId, 'prasarana_rapid_rail:KJ37');
    expect(journey.destinationStopId, 'prasarana_rapid_rail:KJ14');
    expect(journey.transferCount, 0);
    final transitLeg = journey.legs.whereType<TransitLeg>().single;
    expect(transitLeg.serviceId, 'prasarana_rapid_rail:KJ::direction:0');
  });
}
