import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transitkl/data/routing/journey_search_executor.dart';
import 'package:transitkl/data/routing/routing_graph_repository.dart';
import 'package:transitkl/domain/routing/journey_planner.dart';
import 'package:transitkl/domain/routing/routing_graph.dart';
import 'package:transitkl/presentation/journey_planner/journey_planner_screen.dart';

void main() {
  Future<void> select(WidgetTester tester, JourneySearchRunner runner) async {
    await tester.pumpWidget(
      MaterialApp(
        home: JourneyPlannerScreen(
          data: _data(),
          initialDeparture: DateTime(2026, 11, 9, 8),
          searchRunner: runner,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('origin-station-field')),
      'alpha',
    );
    await tester.pump();
    await tester.tap(find.text('ALPHA').last);
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('destination-station-field')),
      'delta',
    );
    await tester.pump();
    await tester.tap(find.text('DELTA').last);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('find-journey-button')),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('find-journey-button')));
    await tester.pump();
  }

  testWidgets(
    'editing selections during an asynchronous search discards stale results',
    (tester) async {
      final pending = Completer<Journey?>();
      await select(tester, (_) => pending.future);
      expect(find.text('Finding journey...'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('find-journey-button')))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const Key('origin-station-field')),
        'changed',
      );
      await tester.pump();
      pending.complete(
        JourneyPlanner(_data().graph).plan(
          originStopId: 'A',
          destinationStopId: 'D',
          departure: DateTime(2026, 11, 9, 8),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('journey-result')), findsNothing);
      expect(find.text('Finding journey...'), findsNothing);
    },
  );

  testWidgets('a worker failure gives a retryable message', (tester) async {
    await select(tester, (_) async => throw StateError('worker failed'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('journey-search-error')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('find-journey-button')))
          .onPressed,
      isNotNull,
    );
  });
}

TransitDataBundle _data() => TransitDataBundle(
  feed: TransitFeedMetadata(
    id: 'test',
    sourceSha256: 'test',
    serviceDateStart: DateTime(2026),
    serviceDateEnd: DateTime(2026, 12, 31),
  ),
  graph: RoutingGraph(
    stops: const [
      StopNode(id: 'A', name: 'ALPHA'),
      StopNode(id: 'D', name: 'DELTA'),
    ],
    serviceCalendars: [
      ServiceCalendar(
        id: 'daily',
        weekdays: List.filled(7, true),
        startDate: DateTime(2026),
        endDate: DateTime(2026, 12, 31),
      ),
    ],
    services: [
      TransitService(
        id: 'line',
        routeId: 'line',
        directionId: 0,
        shortName: 'L',
        longName: 'Test line',
        headways: const [
          HeadwayWindow(
            calendarId: 'daily',
            startSeconds: 0,
            endSeconds: 86400,
            headwaySeconds: 600,
          ),
        ],
      ),
    ],
    scheduledTrips: const [],
    rideEdges: const [
      RideEdge(
        fromStopId: 'A',
        toStopId: 'D',
        serviceId: 'line',
        travelSeconds: 60,
      ),
    ],
    transferEdges: const [],
  ),
);
