import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transitkl/data/routing/routing_graph_repository.dart';
import 'package:transitkl/main.dart';
import 'package:transitkl/presentation/journey_planner/journey_planner_screen.dart';
import 'package:transitkl/presentation/settings/appearance_controller.dart';

void main() {
  testWidgets('the tab layout fits a small phone with large text', (
    tester,
  ) async {
    final data = await tester.runAsync(AssetRoutingGraphRepository().load);
    final end = data!.sources
        .singleWhere((feed) => feed.id == 'ktmb')
        .serviceDateEnd;
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.6)),
          child: child!,
        ),
        home: JourneyPlannerScreen(
          data: data,
          initialDeparture: DateTime(end.year, end.month, end.day + 1, 8),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Plan your journey'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('plan-data-warning')),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('KTM Komuter'), findsOneWidget);
    await tester.tap(find.byKey(const Key('timetables-tab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('timetable-station-field')), findsOneWidget);
    await tester.tap(find.byKey(const Key('saved-tab')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('appearance updates the app and reloads on restart', (
    tester,
  ) async {
    final data = await tester.runAsync(AssetRoutingGraphRepository().load);
    final store = _AppearanceStore();
    Widget app() =>
        TransitKlApp(repository: _FixedGraph(data!), appearanceStore: store);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Dark'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(find.text('Appearance'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(find.text('Plan your journey'), findsOneWidget);
  });
}

class _AppearanceStore implements AppearanceStore {
  ThemeMode mode = ThemeMode.system;

  @override
  Future<ThemeMode> load() async => mode;

  @override
  Future<void> save(ThemeMode next) async => mode = next;
}

class _FixedGraph implements RoutingGraphRepository {
  _FixedGraph(this.data);

  final TransitDataBundle data;

  @override
  Future<TransitDataBundle> load() async => data;
}
