import 'package:flutter_test/flutter_test.dart';
import 'package:transitkl/data/routing/routing_graph_repository.dart';
import 'package:transitkl/domain/routing/journey_planner.dart';
import 'package:transitkl/domain/search/journey_search_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'loads the audited Rapid Rail and Klang Valley Komuter network',
    () async {
      final data = await AssetRoutingGraphRepository().load();

      expect(data.feed.id, 'transitkl_rail');
      expect(data.feed.serviceDateEnd, DateTime(2026, 12, 31));
      expect(data.graph.stops, hasLength(244));
      expect(data.graph.services, hasLength(20));
      expect(data.graph.rideEdges, hasLength(505));
      expect(data.graph.transferEdges, hasLength(98));
      expect(data.graph.scheduledTrips, hasLength(164));
      expect(
        data.sources.singleWhere((feed) => feed.id == 'ktmb').serviceDateEnd,
        DateTime(2026, 11, 17),
      );
      expect(
        data.graph.services.values
            .where((s) => s.id.startsWith('ktmb:'))
            .map((s) => s.routeId)
            .toSet(),
        {'ktmb:KA15_KD19', 'ktmb:KC05_KB18'},
      );
    },
  );

  test('KTM direct, cross-operator and expired-feed routing', () async {
    final data = await AssetRoutingGraphRepository().load();
    final search = JourneySearchService(data.graph);
    Journey? route(String from, String to, DateTime departure) => search.search(
      origin: search.stations.singleWhere((s) => s.id == from),
      destination: search.stations.singleWhere((s) => s.id == to),
      departure: departure,
    );
    final departure = DateTime(2026, 11, 3, 8);
    final direct = route('batu caves', 'kl sentral', departure)!;
    expect(direct.arrival, DateTime(2026, 11, 3, 8, 34));
    expect(direct.transferCount, 0);
    expect((direct.legs.single as TransitLeg).isScheduled, isTrue);
    final multimodal = route('batu caves', 'klcc', departure)!;
    expect(multimodal.legs.whereType<WalkingLeg>(), isNotEmpty);
    expect(
      multimodal.legs.whereType<TransitLeg>().any(
        (leg) => leg.serviceId.startsWith('ktmb:'),
      ),
      isTrue,
    );
    expect(
      multimodal.legs.whereType<TransitLeg>().any(
        (leg) => leg.serviceId.startsWith('prasarana_rapid_rail:'),
      ),
      isTrue,
    );
    expect(
      multimodal.legs.fold<int>(0, (sum, leg) => sum + leg.durationSeconds),
      multimodal.totalTravelSeconds,
    );
    expect(route('klcc', 'batu caves', departure), isNotNull);
    final weekend = route(
      'batu caves',
      'kl sentral',
      DateTime(2026, 11, 7, 8),
    )!;
    final weekendTripId = (weekend.legs.single as TransitLeg).scheduledTripId;
    expect(
      data.graph.scheduledTrips
          .singleWhere((trip) => trip.id == weekendTripId)
          .calendarId,
      'ktmb:komuter_weekend',
    );
    expect(route('gombak', 'seremban', departure), isNull);
    expect(route('gombak', 'seremban', DateTime(2026, 11, 3, 16)), isNotNull);
    expect(route('batu caves', 'klcc', DateTime(2026, 11, 18, 8)), isNull);
    expect(route('gombak', 'kajang', DateTime(2026, 11, 18, 8)), isNotNull);
    final sentul = search.stations
        .where((s) => s.id.startsWith('sentul::'))
        .toList();
    expect(sentul, hasLength(2));
    expect(sentul.map((s) => s.name).toSet().length, 2);
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
    )!;
    expect(journey.originStopId, 'prasarana_rapid_rail:KJ37');
    expect(journey.destinationStopId, 'prasarana_rapid_rail:KJ14');
    expect(journey.transferCount, 0);
    expect(journey.totalWalkingSeconds, 0);
    final transitLeg = journey.legs.whereType<TransitLeg>().single;
    expect(transitLeg.serviceId, 'prasarana_rapid_rail:KJ::direction:0');
    expect(journey.totalTravelSeconds, 3625);
  });
}
