import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transitkl/data/routing/journey_search_executor.dart';
import 'package:transitkl/data/routing/routing_graph_repository.dart';
import 'package:transitkl/presentation/journey_planner/journey_planner_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TransitDataBundle data;

  setUpAll(() async {
    data = await AssetRoutingGraphRepository().load();
  });

  Future<void> open(
    WidgetTester tester,
    List<JourneySearchRequest> searches,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: JourneyPlannerScreen(
          data: data,
          initialDeparture: DateTime(2026, 11, 16, 13),
          searchRunner: (request) async {
            searches.add(request);
            return null;
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('timetables-tab')));
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, String query, String label) async {
    await tester.enterText(
      find.byKey(const Key('timetable-station-field')),
      query,
    );
    await tester.pump();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('searching KTM shows two directions, short turns and expiry', (
    tester,
  ) async {
    final searches = <JourneySearchRequest>[];
    await open(tester, searches);
    expect(
      find.text('Choose a station or bus stop from the suggestions.'),
      findsOneWidget,
    );
    await select(tester, 'Setia Jaya', 'SETIA JAYA (KTM Komuter)');
    expect(find.text('Scheduled departures'), findsOneWidget);
    final scrollable = find
        .descendant(
          of: find.byKey(const Key('timetable-list')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('17:55'),
      140,
      scrollable: scrollable,
    );
    expect(find.text('17:55'), findsOneWidget);
    final portKlangCard = find.ancestor(
      of: find.text('Toward Pelabuhan Klang'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: portKlangCard, matching: find.text('17:55')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: portKlangCard,
        matching: find.text('18:55 · Ends at Klang'),
      ),
      findsOneWidget,
    );
    final towardsTanjungMalim = find.text('Toward Tanjung Malim');
    await tester.scrollUntilVisible(
      towardsTanjungMalim,
      140,
      scrollable: scrollable,
    );
    expect(towardsTanjungMalim, findsOneWidget);
    expect(find.text('Toward Klang'), findsNothing);
    expect(find.text('Service frequency'), findsNothing);

    final date = find.byKey(const Key('timetable-date-button'));
    await tester.scrollUntilVisible(
      date.hitTestable(),
      -140,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(date);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3'));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.textContaining('bundled timetable expired'), findsOneWidget);
    expect(
      find.textContaining('No departures or frequency windows'),
      findsOneWidget,
    );
    expect(find.text('Scheduled departures'), findsNothing);
    expect(searches, isEmpty);
  });

  testWidgets(
    'line frequency is distinct and Use as From retains planner date',
    (tester) async {
      final searches = <JourneySearchRequest>[];
      await open(tester, searches);
      await select(tester, 'SS15', 'SS 15 (LRT)');
      expect(find.text('Service frequency'), findsOneWidget);
      expect(find.text('Scheduled departures'), findsNothing);
      expect(find.textContaining('not station-specific'), findsWidgets);
      await tester.tap(find.text('Use as From'));
      await tester.pumpAndSettle();
      final from = find.byKey(const Key('origin-station-field'));
      expect(tester.widget<TextField>(from).controller!.text, 'SS 15 (LRT)');
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(searches, isEmpty);

      await tester.tap(find.byKey(const Key('timetables-tab')));
      await tester.pumpAndSettle();
      final station = find.byKey(const Key('timetable-station-field'));
      expect(tester.widget<TextField>(station).controller!.text, 'SS 15 (LRT)');
      expect(find.textContaining('November 16'), findsOneWidget);
    },
  );
}
