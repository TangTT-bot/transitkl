import 'package:flutter_test/flutter_test.dart';
import 'package:transitkl/data/routing/routing_graph_repository.dart';
import 'package:transitkl/data/routing/journey_search_executor.dart';
import 'package:transitkl/domain/routing/journey_planner.dart';
import 'package:transitkl/domain/search/journey_search_service.dart';

const busPrefix = 'prasarana_rapid_bus_kl:';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TransitDataBundle data;
  late JourneySearchService search;
  setUpAll(() async {
    data = await AssetRoutingGraphRepository().load();
    search = JourneySearchService(data.graph);
  });
  StationGroup stop(String query) =>
      search.stations.singleWhere((s) => s.id == query);
  Journey? route(String from, String to, DateTime departure) => search.search(
    origin: stop(from),
    destination: stop(to),
    departure: departure,
  );

  test('only published bus routes are bundled and BRT is not duplicated', () {
    final source = data.sources.singleWhere(
      (s) => s.id == 'prasarana_rapid_bus_kl',
    );
    expect(source.includedRouteCount, 138);
    expect(source.serviceDateEnd, DateTime(2027, 3, 31));
    expect(source.coverageNote, contains('Partial Klang Valley bus coverage'));
    expect(source.coverageNote, contains('separate MRT feeder'));
    expect(
      data.graph.transferEdges.where(
        (edge) =>
            edge.fromStopId.startsWith(busPrefix) &&
            edge.toStopId.startsWith(busPrefix),
      ),
      isEmpty,
    );
    final busStops = search.stations
        .where((s) => s.stopIds.every((id) => id.startsWith(busPrefix)))
        .toList();
    expect(
      busStops.map((s) => s.displayLabel).toSet(),
      hasLength(busStops.length),
    );
    final services = data.graph.services.values.where(
      (s) => s.id.startsWith(busPrefix),
    );
    expect(services.map((s) => s.routeId).toSet(), hasLength(138));
    expect(services.any((s) => s.routeId == '${busPrefix}B1000'), isFalse);
    expect(
      data.graph.stops.keys.any((s) => s == '${busPrefix}1005834'),
      isFalse,
    );
    expect(
      data.graph.scheduledTrips.any((t) => t.id.contains('weekend_T4069')),
      isFalse,
    );
    expect(
      data.graph.rideEdges.where(
        (e) => e.serviceId.startsWith(busPrefix) && e.sequence != null,
      ),
      isNotEmpty,
    );
  });

  test(
    'T200 direct journeys respect ordered loops in both directions and day types',
    () {
      for (final departure in [
        DateTime(2026, 11, 8, 8),
        DateTime(2026, 11, 9, 8),
      ]) {
        for (final pair in [
          ('sl311 lrt gombak', 'sl162 hub uia'),
          ('sl162 hub uia', 'sl311 lrt gombak'),
        ]) {
          final journey = route(pair.$1, pair.$2, departure)!;
          expect(journey.transferCount, 0);
          expect(journey.legs.whereType<TransitLeg>(), hasLength(1));
          expect(
            data
                .graph
                .services[(journey.legs.single as TransitLeg).serviceId]!
                .shortName,
            'T200',
          );
          expect(
            journey.totalTravelSeconds,
            journey.legs.fold<int>(0, (sum, leg) => sum + leg.durationSeconds),
          );
        }
      }
    },
  );

  test('rail and bus use the explicit Gombak walk in both directions', () {
    for (final pair in [('klcc', 'sl162 hub uia'), ('sl162 hub uia', 'klcc')]) {
      final journey = route(pair.$1, pair.$2, DateTime(2026, 11, 9, 8))!;
      expect(
        journey.legs.whereType<TransitLeg>().any(
          (leg) => leg.serviceId.startsWith(busPrefix),
        ),
        isTrue,
      );
      expect(
        journey.legs.whereType<TransitLeg>().any(
          (leg) => leg.serviceId.startsWith('prasarana_rapid_rail:'),
        ),
        isTrue,
      );
      expect(
        journey.legs.whereType<WalkingLeg>().any(
          (leg) =>
              {leg.fromStopId, leg.toStopId}.contains('${busPrefix}1001801') &&
              leg.walkSeconds == 300,
        ),
        isTrue,
      );
    }
  });

  test('bus expiry and overnight closures do not create imaginary service', () {
    expect(
      route('sl311 lrt gombak', 'sl162 hub uia', DateTime(2027, 4, 1, 8)),
      isNull,
    );
    expect(
      route('sl311 lrt gombak', 'sl162 hub uia', DateTime(2026, 11, 9, 0)),
      isNull,
    );
    expect(
      route('sl311 lrt gombak', 'sl162 hub uia', DateTime(2027, 1, 4, 8)),
      isNotNull,
    );
    final railExpired = route('gombak', 'kajang', DateTime(2027, 1, 4, 8));
    if (railExpired != null) {
      expect(
        railExpired.legs.whereType<TransitLeg>().every(
          (leg) => leg.serviceId.startsWith(busPrefix),
        ),
        isTrue,
      );
    }
  });

  test(
    'mobile worker returns the same Recommended result as synchronous domain search',
    () async {
      final departure = DateTime(2026, 11, 9, 8);
      final origin = stop('sl311 lrt gombak');
      final destination = stop('sl162 hub uia');
      final result = await runJourneySearch(
        JourneySearchRequest(
          graph: data.graph,
          origin: origin,
          destination: destination,
          departure: departure,
        ),
      );
      final direct = search.search(
        origin: origin,
        destination: destination,
        departure: departure,
      )!;
      expect(result!.cost.compareTo(direct.cost), 0);
      expect(result.arrival, direct.arrival);
    },
  );
}
