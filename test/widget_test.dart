import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transitkl/data/routing/routing_graph_repository.dart';
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
          initialDeparture: DateTime(2026, 11, 2, 8),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Plan your journey'), findsOneWidget);
    expect(find.textContaining('187'), findsNothing);
    expect(find.textContaining('valid until 31 Dec 2026'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('origin-station-field')),
      'Gombak',
    );
    await tester.pump();
    await tester.tap(find.text('Gombak').last);
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('destination-station-field')),
      'Kajang',
    );
    await tester.pump();
    await tester.tap(find.text('Kajang').last);
    await tester.pump();

    final button = find.byKey(const Key('find-journey-button'));
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pump();

    expect(find.byKey(const Key('journey-result')), findsOneWidget);
    expect(find.text('Recommended journey'), findsOneWidget);
    expect(find.textContaining('transfer'), findsWidgets);
    expect(find.textContaining('Kelana Jaya'), findsOneWidget);
  });
}
