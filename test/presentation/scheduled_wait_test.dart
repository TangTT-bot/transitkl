import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transitkl/data/routing/routing_graph_repository.dart';
import 'package:transitkl/domain/routing/journey_planner.dart';
import 'package:transitkl/domain/search/journey_search_service.dart';
import 'package:transitkl/presentation/journey_planner/journey_planner_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TransitDataBundle data;
  late Journey afternoonJourney;
  late Journey laterJourney;

  setUpAll(() async {
    data = await AssetRoutingGraphRepository().load();
    final search = JourneySearchService(data.graph);
    final sunMed = search.stations.singleWhere((stop) => stop.id == 'sunmed');
    final klang = search.stations.singleWhere((stop) => stop.id == 'klang');
    Journey plan(int hour, int minute) => search.search(
      origin: sunMed,
      destination: klang,
      departure: DateTime(2026, 11, 16, hour, minute),
    )!;

    afternoonJourney = plan(13, 0);
    laterJourney = plan(17, 25);
  });

  test('SunMed to Klang timing separates travel and the KTM service gap', () {
    final legs = afternoonJourney.timedLegs.toList();
    expect(legs, hasLength(3));
    expect(legs[0].leg, isA<TransitLeg>());
    expect(legs[1].leg, isA<WalkingLeg>());
    expect(legs[1].boardsAt, isNull);
    expect(legs[1].endsAt, legs[2].startsAt);
    final train = legs.last;
    expect(train.leg.fromStopId, 'ktmb:53600');
    final trainLeg = train.leg as TransitLeg;
    expect(trainLeg.isScheduled, isTrue);
    expect(train.boardsAt, DateTime(2026, 11, 16, 17, 55));
    expect(train.endsAt, afternoonJourney.arrival);
    expect(trainLeg.rideSeconds, 33 * 60);
    expect(
      trainLeg.waitSeconds,
      train.boardsAt!.difference(train.startsAt).inSeconds,
    );

    final rideAndWalk = afternoonJourney.legs.fold<int>(
      0,
      (sum, leg) =>
          sum +
          switch (leg) {
            TransitLeg(:final rideSeconds) => rideSeconds,
            WalkingLeg(:final walkSeconds) => walkSeconds,
          },
    );
    expect(afternoonJourney.totalMovingSeconds, rideAndWalk);
    expect(
      afternoonJourney.totalWaitingSeconds + rideAndWalk,
      5 * 3600 + 28 * 60,
    );
    expect(laterJourney.timedLegs.last.boardsAt, train.boardsAt);
    expect(laterJourney.arrival, afternoonJourney.arrival);
    expect(laterJourney.totalTravelSeconds, 63 * 60);
    expect(laterJourney.totalMovingSeconds, rideAndWalk);
  });

  Future<void> showJourney(WidgetTester tester, Journey journey) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: JourneyResultView(graph: data.graph, journey: journey),
          ),
        ),
      ),
    );
  }

  testWidgets('long wait shows the exact boarding time and duration split', (
    tester,
  ) async {
    await showJourney(tester, afternoonJourney);
    expect(find.text('Long scheduled wait'), findsOneWidget);
    expect(
      find.textContaining(
        RegExp('scheduled for 17:55 at Setia Jaya', caseSensitive: false),
      ),
      findsOneWidget,
    );
    expect(find.text('Wait at this stop: 4 hr 39 min.'), findsOneWidget);
    expect(find.text('Total from 13:00'), findsOneWidget);
    expect(find.text('5 hr 28 min'), findsOneWidget);
    expect(find.text('Waiting (included): 4 hr 43 min'), findsOneWidget);
    expect(find.text('Riding + walking: 45 min'), findsOneWidget);
    expect(find.text('Scheduled boarding: 17:55'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('normal waits retain the boarding time without a warning', (
    tester,
  ) async {
    await showJourney(tester, laterJourney);
    expect(find.text('Long scheduled wait'), findsNothing);
    expect(find.text('Scheduled boarding: 17:55'), findsOneWidget);
    expect(find.text('1 hr 3 min'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
