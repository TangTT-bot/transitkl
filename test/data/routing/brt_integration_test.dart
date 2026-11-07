import 'package:flutter_test/flutter_test.dart';
import 'package:transitkl/data/routing/routing_graph_repository.dart';
import 'package:transitkl/domain/routing/journey_planner.dart';
import 'package:transitkl/domain/search/journey_search_service.dart';

const railPrefix = 'prasarana_rapid_rail:';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TransitDataBundle data;
  late JourneySearchService search;
  final saturday = DateTime(2026, 11, 7, 8);

  setUpAll(() async {
    data = await AssetRoutingGraphRepository().load();
    search = JourneySearchService(data.graph);
  });

  Journey route(String origin, String destination, {DateTime? departure}) =>
      search.search(
        origin: search.stations.singleWhere((station) => station.id == origin),
        destination: search.stations.singleWhere(
          (station) => station.id == destination,
        ),
        departure: departure ?? saturday,
      )!;

  void verifyClockAndScore(Journey journey) {
    expect(
      journey.legs.fold<int>(0, (sum, leg) => sum + leg.durationSeconds),
      journey.totalTravelSeconds,
    );
    expect(
      journey.arrival.difference(journey.departure).inSeconds,
      journey.totalTravelSeconds,
    );
    expect(
      journey.generalizedCostSeconds,
      journey.totalTravelSeconds +
          600 * journey.transferCount +
          journey.totalWalkingSeconds,
    );
  }

  test('BRT has seven stops, both directions and both interchange pairs', () {
    final services = data.graph.services.values
        .where((service) => service.routeId == '${railPrefix}BRT')
        .toList();
    expect(services, hasLength(2));
    expect(services.map((service) => service.directionId).toSet(), {0, 1});
    final edges = data.graph.rideEdges
        .where(
          (edge) => services.any((service) => service.id == edge.serviceId),
        )
        .toList();
    expect(edges, hasLength(12));
    expect(
      {
        for (final edge in edges) ...[edge.fromStopId, edge.toStopId],
      },
      {for (var index = 1; index <= 7; index++) '${railPrefix}BRT$index'},
    );
    for (final (first, second, seconds) in [
      ('${railPrefix}KJ31', '${railPrefix}BRT7', 180),
      ('ktmb:53600', '${railPrefix}BRT1', 360),
    ]) {
      for (final (from, to) in [(first, second), (second, first)]) {
        final link = data.graph.transferEdges.singleWhere(
          (edge) => edge.fromStopId == from && edge.toStopId == to,
        );
        expect(link.walkSeconds, seconds);
        expect(link.source, 'curated_interchange');
      }
    }
    final usj = search.stations.singleWhere((station) => station.id == 'usj 7');
    expect(usj.stopIds.toSet(), {'${railPrefix}KJ31', '${railPrefix}BRT7'});
    expect(usj.matchesQuery('USJ7'), isTrue);
    expect(usj.matchesQuery('USJ 7'), isTrue);
  });

  test('LRT and BRT journeys use USJ 7 in both directions', () {
    for (final (from, to) in [
      ('putra heights', 'sunu monash'),
      ('sunu monash', 'putra heights'),
    ]) {
      final journey = route(from, to);
      final rides = journey.legs.whereType<TransitLeg>().toList();
      expect(rides, hasLength(2));
      expect(
        rides.map((leg) => data.graph.services[leg.serviceId]!.routeId).toSet(),
        {'${railPrefix}KJ', '${railPrefix}BRT'},
      );
      expect(journey.transferCount, 1);
      final walk = journey.legs.whereType<WalkingLeg>().single;
      expect(
        {walk.fromStopId, walk.toStopId},
        {'${railPrefix}KJ31', '${railPrefix}BRT7'},
      );
      expect(walk.walkSeconds, 180);
      verifyClockAndScore(journey);
    }
  });

  test('KTM and BRT journeys use Setia Jaya in both directions', () {
    // Choose times with actual KTM service through Setia Jaya. Some morning
    // trains start at Subang Jaya and cannot be boarded at Setia Jaya.
    for (final (from, to, departure) in [
      ('klang', 'sunway lagoon', DateTime(2026, 11, 7, 10)),
      ('sunway lagoon', 'klang', DateTime(2026, 11, 7, 9)),
    ]) {
      final journey = route(from, to, departure: departure);
      final rides = journey.legs.whereType<TransitLeg>().toList();
      expect(rides, hasLength(2));
      expect(rides.where((leg) => leg.isScheduled), hasLength(1));
      expect(
        rides.any(
          (leg) =>
              data.graph.services[leg.serviceId]!.routeId == '${railPrefix}BRT',
        ),
        isTrue,
      );
      expect(journey.transferCount, 1);
      final walk = journey.legs.whereType<WalkingLeg>().single;
      expect(
        {walk.fromStopId, walk.toStopId},
        {'ktmb:53600', '${railPrefix}BRT1'},
      );
      expect(walk.walkSeconds, 360);
      verifyClockAndScore(journey);
    }
  });

  test('a substantially earlier KTM connection can justify BRT via LRT', () {
    final journey = route('sunway lagoon', 'klang');
    expect(journey.arrival, DateTime(2026, 11, 7, 9, 3));
    expect(journey.transferCount, 2);
    expect(journey.totalWalkingSeconds, 180 + 300);
    expect(
      journey.legs.whereType<TransitLeg>().map(
        (leg) => data.graph.services[leg.serviceId]!.routeId,
      ),
      ['${railPrefix}BRT', '${railPrefix}KJ', 'ktmb:KA15_KD19'],
    );
    verifyClockAndScore(journey);
  });

  test('end-to-end BRT journeys stay on BRT without extra transfers', () {
    for (final (from, to) in [
      ('sunway setia jaya', 'usj 7'),
      ('usj 7', 'sunway setia jaya'),
    ]) {
      final journey = route(from, to);
      expect(journey.transferCount, 0);
      expect(journey.totalWalkingSeconds, 0);
      final ride = journey.legs.single as TransitLeg;
      expect(ride.stopIds, hasLength(7));
      expect(data.graph.services[ride.serviceId]!.routeId, '${railPrefix}BRT');
      verifyClockAndScore(journey);
    }
  });

  test('BRT waits respect weekday/weekend calendars and operating windows', () {
    final planner = JourneyPlanner(data.graph, maximumJourneySeconds: 3600);
    Journey? direct(DateTime departure) => planner.plan(
      originStopId: '${railPrefix}BRT7',
      destinationStopId: '${railPrefix}BRT5',
      departure: departure,
    );
    final weekend = direct(saturday)!;
    final weekday = direct(DateTime(2026, 11, 9, 8))!;
    expect((weekend.legs.single as TransitLeg).waitSeconds, 180);
    expect((weekday.legs.single as TransitLeg).waitSeconds, 120);
    expect(direct(DateTime(2026, 11, 7, 2)), isNull);
  });
}
