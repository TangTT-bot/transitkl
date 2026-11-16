import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transitkl/data/routing/journey_search_executor.dart';
import 'package:transitkl/data/routing/routing_graph_repository.dart';
import 'package:transitkl/domain/favourites/favourites.dart';
import 'package:transitkl/presentation/journey_planner/journey_planner_screen.dart';

void main() {
  Future<void> select(
    WidgetTester tester,
    String field,
    String query,
    String label,
  ) async {
    await tester.enterText(find.byKey(Key('$field-station-field')), query);
    await tester.pump();
    await tester.tap(find.text(label));
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'saves, reopens, searches and removes favourite stations and journeys',
    (tester) async {
      final data = await tester.runAsync(AssetRoutingGraphRepository().load);
      final store = _MemoryRepository();
      final searches = <JourneySearchRequest>[];
      final firstDate = DateTime(2026, 11, 16, 13);
      final nextDate = DateTime(2026, 11, 17, 10);
      Widget app(DateTime departure) => MaterialApp(
        home: JourneyPlannerScreen(
          data: data!,
          initialDeparture: departure,
          favouritesRepository: store,
          searchRunner: (request) async {
            searches.add(request);
            return null;
          },
        ),
      );

      await tester.binding.setSurfaceSize(const Size(420, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(firstDate));
      await tester.pumpAndSettle();
      await select(tester, 'origin', 'Klang', 'KLANG (KTM Komuter)');
      await tester.tap(find.byTooltip('Save From stop'));
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Remove From stop from favourites'),
        findsOneWidget,
      );
      await select(tester, 'destination', 'Monash', 'Sunu-monash (Sunway BRT)');
      await tap(tester, find.text('Save journey'));
      expect(store.favourites.stations, hasLength(1));
      expect(store.favourites.journeys, hasLength(1));
      expect(searches, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(app(nextDate));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Favourites'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Use saved station'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use as To'));
      await tester.pumpAndSettle();
      final from = find.byKey(const Key('origin-station-field'));
      final to = find.byKey(const Key('destination-station-field'));
      expect(
        tester.widget<TextField>(to).controller!.text,
        'KLANG (KTM Komuter)',
      );
      expect(tester.widget<TextField>(from).controller!.text, isEmpty);
      await tester.tap(find.byTooltip('Favourites'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Tap to fill From and To'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(from).controller!.text,
        'KLANG (KTM Komuter)',
      );
      expect(
        tester.widget<TextField>(to).controller!.text,
        'Sunu-monash (Sunway BRT)',
      );
      expect(searches, isEmpty);
      await tap(tester, find.byKey(const Key('find-journey-button')));
      expect(searches.single.origin.stopIds, ['ktmb:54700']);
      expect(searches.single.departure, nextDate);

      await tester.tap(find.byTooltip('Favourites'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove saved journey'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove saved station'));
      await tester.pumpAndSettle();
      expect(store.favourites.journeys, isEmpty);
      expect(store.favourites.stations, isEmpty);
    },
  );

  testWidgets('unavailable saved stops stay visible and removable', (
    tester,
  ) async {
    final data = await tester.runAsync(AssetRoutingGraphRepository().load);
    final store = _MemoryRepository()
      ..favourites = FavouritesSnapshot(
        stations: [
          SavedStation(label: 'Old stop', stopIds: ['missing:42']),
        ],
      );
    await tester.pumpWidget(
      MaterialApp(
        home: JourneyPlannerScreen(data: data!, favouritesRepository: store),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Favourites'));
    await tester.pumpAndSettle();
    expect(find.text('Old stop'), findsOneWidget);
    expect(find.text('Unavailable in this network'), findsOneWidget);
    expect(find.byTooltip('Use saved station'), findsNothing);
    await tester.tap(find.byTooltip('Remove saved station'));
    await tester.pumpAndSettle();
    expect(store.favourites.stations, isEmpty);
  });
}

class _MemoryRepository implements FavouritesRepository {
  FavouritesSnapshot favourites = FavouritesSnapshot();

  @override
  Future<FavouritesSnapshot> load() async => favourites;

  @override
  Future<void> save(FavouritesSnapshot value) async => favourites = value;
}
