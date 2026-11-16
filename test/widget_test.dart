import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transitkl/data/routing/routing_graph_repository.dart';
import 'package:transitkl/data/routing/journey_search_executor.dart';
import 'package:transitkl/domain/routing/journey_planner.dart';
import 'package:transitkl/domain/search/journey_search_service.dart';
import 'package:transitkl/presentation/journey_planner/journey_planner_screen.dart';

void main() {
  testWidgets('loads the offline graph and plans a real Rapid Rail journey', (
    tester,
  ) async {
    final data = await tester.runAsync(AssetRoutingGraphRepository().load);
    await tester.pumpWidget(
      MaterialApp(
        home: JourneyPlannerScreen(
          data: data!,
          searchRunner: _testSearch,
          initialDeparture: DateTime(2026, 11, 2, 8),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Plan your journey'), findsOneWidget);
    expect(find.textContaining('187'), findsNothing);
    expect(find.textContaining('valid until 31 Dec 2026'), findsOneWidget);
    expect(find.textContaining('KTM Komuter'), findsWidgets);
    expect(find.textContaining('Sunway BRT'), findsWidgets);
    expect(find.textContaining('17 Nov 2026'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('origin-station-field')),
      'Gombak',
    );
    await tester.pump();
    await tester.tap(find.text('Gombak (LRT)'));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('destination-station-field')),
      'Kajang',
    );
    await tester.pump();
    await tester.tap(find.text('Kajang (MRT + KTM Komuter)'));
    await tester.pump();

    final button = find.byKey(const Key('find-journey-button'));
    await tester.scrollUntilVisible(
      button,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(find.byKey(const Key('journey-result')), findsOneWidget);
    expect(find.text('Recommended journey'), findsOneWidget);
    expect(find.textContaining('transfer'), findsWidgets);
    expect(find.textContaining('Kelana Jaya'), findsOneWidget);

    expect(find.byKey(const Key('route-preference-field')), findsNothing);
    expect(find.text('Travel preference'), findsNothing);
    expect(find.text('Fastest'), findsNothing);
    expect(find.text('Fewer transfers'), findsNothing);
    expect(find.text('Least walking'), findsNothing);
    expect(find.textContaining('Walking'), findsOneWidget);
  });

  testWidgets('shows a straightforward LRT to BRT journey through USJ 7', (
    tester,
  ) async {
    final data = await tester.runAsync(AssetRoutingGraphRepository().load);
    await tester.pumpWidget(
      MaterialApp(
        home: JourneyPlannerScreen(
          data: data!,
          searchRunner: _testSearch,
          initialDeparture: DateTime(2026, 11, 7, 8),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('origin-station-field')),
      'USJ7',
    );
    await tester.pump();
    expect(find.text('USJ 7 (LRT + Sunway BRT)'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('origin-station-field')),
      'Putra Heights',
    );
    await tester.pump();
    await tester.tap(find.text('PUTRA Heights (LRT)'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('destination-station-field')),
      'Monash',
    );
    await tester.pump();
    await tester.tap(find.text('Sunu-monash (Sunway BRT)'));
    await tester.pump();
    final button = find.byKey(const Key('find-journey-button'));
    await tester.scrollUntilVisible(
      button,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(find.text('Recommended journey'), findsOneWidget);
    expect(find.text('LRT Kelana Jaya Line'), findsOneWidget);
    expect(find.text('BRT Sunway Line'), findsOneWidget);
    expect(find.text('Transfer at USJ 7'), findsOneWidget);
    expect(find.text('1 transfer'), findsOneWidget);
    expect(find.byKey(const Key('route-preference-field')), findsNothing);
  });

  testWidgets(
    'published bus stop search shows T200 and the partial coverage notice',
    (tester) async {
      final data = await tester.runAsync(AssetRoutingGraphRepository().load);
      await tester.pumpWidget(
        MaterialApp(
          home: JourneyPlannerScreen(
            data: data!,
            initialDeparture: DateTime(2026, 11, 8, 8),
            searchRunner: _testSearch,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('bus-coverage-notice')), findsOneWidget);
      expect(find.textContaining('138 published routes'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('origin-station-field')),
        'SL311',
      );
      await tester.pump();
      await tester.tap(find.text('SL311 LRT Gombak (Rapid Bus)'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('destination-station-field')),
        'SL162',
      );
      await tester.pump();
      await tester.tap(find.text('SL162 HUB UIA (Rapid Bus)'));
      await tester.pump();
      final button = find.byKey(const Key('find-journey-button'));
      await tester.scrollUntilVisible(
        button,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Recommended journey'), findsOneWidget);
      expect(find.text('T200'), findsOneWidget);
      expect(find.text('0 transfers'), findsOneWidget);
    },
  );

  testWidgets(
    'labels the Klang train station and BD28 bus stop in both fields',
    (tester) async {
      final data = await tester.runAsync(AssetRoutingGraphRepository().load);
      await tester.pumpWidget(
        MaterialApp(
          home: JourneyPlannerScreen(
            data: data!,
            initialDeparture: DateTime(2026, 11, 16, 13),
            searchRunner: _testSearch,
          ),
        ),
      );
      final from = find.byKey(const Key('origin-station-field'));
      final to = find.byKey(const Key('destination-station-field'));
      const trainLabel = 'KLANG (KTM Komuter)';
      const busLabel = 'BD28 KTM KLANG (Rapid Bus)';

      await tester.enterText(from, 'Klang');
      await tester.pump();
      expect(find.text(trainLabel), findsOneWidget);
      await tester.tap(find.text(trainLabel));
      await tester.pump();
      expect(tester.widget<TextField>(from).controller!.text, trainLabel);

      await tester.enterText(to, 'BD28 KTM Klang');
      await tester.pump();
      expect(find.text(busLabel), findsOneWidget);
      await tester.tap(find.text(busLabel));
      await tester.pump();
      expect(tester.widget<TextField>(to).controller!.text, busLabel);
    },
  );
}

// Keep real domain routing but avoid the worker isolate inside the fake widget clock.
Future<Journey?> _testSearch(JourneySearchRequest request) async =>
    JourneySearchService(request.graph).search(
      origin: request.origin,
      destination: request.destination,
      departure: request.departure,
    );
