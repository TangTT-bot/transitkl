import 'package:flutter_test/flutter_test.dart';
import 'package:transitkl/domain/routing/journey_planner.dart';
import 'package:transitkl/domain/routing/routing_graph.dart';

void main() {
  test(
    'frequency windows shift to downstream stops including after origin closing',
    () {
      final planner = JourneyPlanner(
        _graph([
          _edge('A', 'B', 0, 600, 0),
          _edge('B', 'D', 1, 60, 600),
        ], end: 8 * 3600 + 600),
      );
      final first = planner.plan(
        originStopId: 'B',
        destinationStopId: 'D',
        departure: DateTime(2026, 11, 9, 8),
      )!;
      expect(first.arrival, DateTime(2026, 11, 9, 8, 16));
      final late = planner.plan(
        originStopId: 'B',
        destinationStopId: 'D',
        departure: DateTime(2026, 11, 9, 8, 12),
      )!;
      expect(late.arrival, DateTime(2026, 11, 9, 8, 18));
    },
  );

  test(
    'staying aboard includes dwell but boarding at that stop does not add it twice',
    () {
      final planner = JourneyPlanner(
        _graph([
          _edge('A', 'B', 0, 600, 0),
          _edge('B', 'D', 1, 300, 720, dwell: 120),
        ]),
      );
      final journey = planner.plan(
        originStopId: 'A',
        destinationStopId: 'D',
        departure: DateTime(2026, 11, 9, 8),
      )!;
      expect(journey.totalTravelSeconds, 1320);
      expect(journey.transferCount, 0);
      expect(journey.legs, hasLength(1));
      expect((journey.legs.single as TransitLeg).rideSeconds, 1020);
    },
  );

  test(
    'a repeated stop cannot skip the middle of a loop while staying aboard',
    () {
      final planner = JourneyPlanner(
        _graph([
          _edge('A', 'B', 0, 60, 0),
          _edge('B', 'X', 1, 300, 60),
          _edge('X', 'B', 2, 300, 360),
          _edge('B', 'D', 3, 60, 660),
        ]),
      );
      final journey = planner.plan(
        originStopId: 'A',
        destinationStopId: 'D',
        departure: DateTime(2026, 11, 9, 8),
      )!;
      expect(journey.transferCount, 0);
      expect((journey.legs.single as TransitLeg).stopIds, [
        'A',
        'B',
        'X',
        'B',
        'D',
      ]);
      expect(journey.totalTravelSeconds, 1020);
    },
  );

  test(
    'restricted frequency stops allow through riding but not illegal boarding or exit',
    () {
      final planner = JourneyPlanner(
        _graph([
          _edge('A', 'B', 0, 600, 0, dropOff: false),
          _edge('B', 'D', 1, 60, 600, pickup: false),
        ]),
      );
      final departure = DateTime(2026, 11, 9, 8);
      expect(
        planner.plan(
          originStopId: 'A',
          destinationStopId: 'D',
          departure: departure,
        ),
        isNotNull,
      );
      expect(
        planner.plan(
          originStopId: 'A',
          destinationStopId: 'B',
          departure: departure,
        ),
        isNull,
      );
      expect(
        planner.plan(
          originStopId: 'B',
          destinationStopId: 'D',
          departure: departure,
        ),
        isNull,
      );
    },
  );

  test(
    'multi source and destination search agrees with exhaustive platform combinations',
    () {
      final planner = JourneyPlanner(
        _graph([_edge('A', 'B', 0, 600, 0), _edge('B', 'D', 1, 60, 600)]),
      );
      final departure = DateTime(2026, 11, 9, 8, 15);
      final combined = planner.planBetween(
        originStopIds: ['A', 'B'],
        destinationStopIds: ['D'],
        departure: departure,
      )!;
      final candidates = [
        for (final from in ['A', 'B'])
          planner.plan(
            originStopId: from,
            destinationStopId: 'D',
            departure: departure,
          )!,
      ]..sort((a, b) => a.cost.compareTo(b.cost));
      expect(combined.cost.compareTo(candidates.first.cost), 0);
      expect(combined.originStopId, 'B');
    },
  );

  test('inconsistent frequency sequence offsets fail graph validation', () {
    expect(
      () => _graph([_edge('A', 'B', 0, 600, 0), _edge('B', 'D', 1, 60, 500)]),
      throwsFormatException,
    );
  });
}

RideEdge _edge(
  String from,
  String to,
  int sequence,
  int travel,
  int offset, {
  int dwell = 0,
  bool pickup = true,
  bool dropOff = true,
}) => RideEdge(
  fromStopId: from,
  toStopId: to,
  serviceId: 'bus',
  travelSeconds: travel,
  sequence: sequence,
  departureOffsetSeconds: offset,
  dwellSeconds: dwell,
  pickupAllowed: pickup,
  dropOffAllowed: dropOff,
);

RoutingGraph _graph(List<RideEdge> edges, {int end = 23 * 3600}) =>
    RoutingGraph(
      stops: [
        for (final id in {'A', 'B', 'D', 'X'}) StopNode(id: id, name: id),
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
          id: 'bus',
          routeId: 'bus-route',
          directionId: 0,
          shortName: 'T1',
          longName: 'Bus test',
          headways: [
            HeadwayWindow(
              calendarId: 'daily',
              startSeconds: 8 * 3600,
              endSeconds: end,
              headwaySeconds: 600,
            ),
          ],
        ),
      ],
      scheduledTrips: const [],
      rideEdges: edges,
      transferEdges: const [],
    );
