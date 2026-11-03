import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:transitkl/domain/routing/journey_planner.dart';
import 'package:transitkl/domain/routing/routing_graph.dart';

void main() {
  final departure = DateTime(2026, 11, 2, 8);

  test('Recommended accepts a short walk to avoid changing trains', () {
    final planner = JourneyPlanner(
      _graph(
        rides: [
          _ride('B', 'D', 'direct', 400),
          _ride('A', 'X', 'red', 100),
          _ride('X', 'D', 'blue', 100),
        ],
        walks: const [
          TransferEdge(fromStopId: 'A', toStopId: 'B', walkSeconds: 60),
        ],
      ),
    );
    final recommended = planner.plan(
      originStopId: 'A',
      destinationStopId: 'D',
      departure: departure,
    )!;
    expect(recommended.transferCount, 0);
    expect(recommended.totalWalkingSeconds, 60);
  });

  test('Recommended breaks an equal score in favour of fewer changes', () {
    final planner = JourneyPlanner(
      _graph(
        rides: [
          _ride('A', 'D', 'direct', 1001),
          _ride('A', 'B', 'red', 200),
          _ride('B', 'D', 'blue', 200),
        ],
      ),
    );
    final result = planner.plan(
      originStopId: 'A',
      destinationStopId: 'D',
      departure: departure,
    )!;
    expect(result.generalizedCostSeconds, 1002);
    expect(result.transferCount, 0);
  });

  test('Recommended matches exhaustive paths on 25 small acyclic networks', () {
    final random = Random(37);
    for (var iteration = 0; iteration < 25; iteration++) {
      final edges = <_OracleEdge>[];
      for (var from = 0; from < 5; from++) {
        for (var to = from + 1; to < 6; to++) {
          if (to != from + 1 && random.nextBool()) continue;
          edges.add(
            _OracleEdge(
              from,
              to,
              random.nextInt(4) == 0 ? null : 'line${random.nextInt(3)}',
              30 + random.nextInt(600),
            ),
          );
        }
      }
      final graph = _graph(
        rides: [
          for (final edge in edges)
            if (edge.service != null)
              _ride('${edge.from}', '${edge.to}', edge.service!, edge.seconds),
        ],
        walks: [
          for (final edge in edges)
            if (edge.service == null)
              TransferEdge(
                fromStopId: '${edge.from}',
                toStopId: '${edge.to}',
                walkSeconds: edge.seconds,
              ),
        ],
      );
      final allPaths = <(int, int, int)>[];
      void enumerate(
        int stop,
        String? active,
        bool boarded,
        int elapsed,
        int transfers,
        int walk,
      ) {
        if (stop == 5) {
          allPaths.add((elapsed, transfers, walk));
          return;
        }
        for (final edge in edges.where((edge) => edge.from == stop)) {
          final walking = edge.service == null;
          final boarding = !walking && active != edge.service;
          enumerate(
            edge.to,
            edge.service,
            boarded || !walking,
            elapsed + edge.seconds + (boarding ? 1 : 0),
            transfers + (boarding && boarded ? 1 : 0),
            walk + (walking ? edge.seconds : 0),
          );
        }
      }

      enumerate(0, null, false, 0, 0, 0);
      List<int> rank((int, int, int) cost) {
        final (time, changes, walk) = cost;
        return [time + changes * 600 + walk, changes, walk, time];
      }

      final ranked = allPaths.map(rank).toList()
        ..sort((a, b) {
          for (var index = 0; index < a.length; index++) {
            if (a[index] != b[index]) return a[index].compareTo(b[index]);
          }
          return 0;
        });
      final actual = JourneyPlanner(
        graph,
      ).plan(originStopId: '0', destinationStopId: '5', departure: departure)!;
      expect(
        rank((
          actual.totalTravelSeconds,
          actual.transferCount,
          actual.totalWalkingSeconds,
        )),
        ranked.first,
        reason: 'network $iteration',
      );
    }
  });

  test('recommended trades a small time saving for less walking', () {
    final planner = JourneyPlanner(
      _graph(
        rides: [
          _ride('A', 'D', 'direct', 1000),
          _ride('B', 'D', 'shortcut', 600),
        ],
        walks: const [
          TransferEdge(
            fromStopId: 'A',
            toStopId: 'B',
            walkSeconds: 300,
            distanceMetres: 360,
          ),
        ],
      ),
    );
    final recommended = planner.plan(
      originStopId: 'A',
      destinationStopId: 'D',
      departure: departure,
    )!;
    expect(recommended.totalTravelSeconds, 1001);
    expect(recommended.totalWalkingSeconds, 0);
    expect(recommended.totalWalkingMetres, 0);
  });

  test('a substantial time saving can justify a transfer in Recommended', () {
    final planner = JourneyPlanner(
      _graph(
        rides: [
          _ride('A', 'D', 'direct', 2400),
          _ride('A', 'B', 'red', 200),
          _ride('B', 'D', 'blue', 200),
        ],
      ),
    );
    final recommended = planner.plan(
      originStopId: 'A',
      destinationStopId: 'D',
      departure: departure,
    )!;
    expect(recommended.totalTravelSeconds, 402);
    expect(recommended.transferCount, 1);
    expect(recommended.generalizedCostSeconds, 1002);
  });

  test('Pareto labels retain an earlier arrival needed for a connection', () {
    final planner = JourneyPlanner(
      _graph(
        rides: [
          _ride('A', 'M', 'red', 500),
          _ride('A', 'X', 'blue', 100),
          _ride('X', 'M', 'red', 100),
        ],
        trips: [
          _trip('connection', 'exact', [
            _stop('M', 8 * 3600 + 300),
            _stop('D', 8 * 3600 + 600),
          ]),
        ],
      ),
      maximumJourneySeconds: 1200,
    );

    final journey = planner.plan(
      originStopId: 'A',
      destinationStopId: 'D',
      departure: departure,
    )!;
    // At M: 501s/0 transfers has a lower score than 202s/1 transfer.
    // Both must survive because only the 202s label catches the 08:05 train.
    expect(journey.totalTravelSeconds, 600);
    expect(journey.transferCount, 2);
    expect(journey.generalizedCostSeconds, 1800);
    expect(journey.legs.whereType<TransitLeg>().map((leg) => leg.toStopId), [
      'X',
      'M',
      'D',
    ]);
    expect(
      journey.legs.fold<int>(0, (sum, leg) => sum + leg.durationSeconds),
      600,
    );
  });

  test('changing scheduled vehicles on the same line is still a transfer', () {
    final planner = JourneyPlanner(
      _graph(
        trips: [
          _trip('first', 'exact', [
            _stop('A', 8 * 3600),
            _stop('B', 8 * 3600 + 100),
          ]),
          _trip('second', 'exact', [
            _stop('B', 8 * 3600 + 200),
            _stop('D', 8 * 3600 + 300),
          ]),
        ],
      ),
    );
    final journey = planner.plan(
      originStopId: 'A',
      destinationStopId: 'D',
      departure: departure,
    )!;
    expect(journey.transferCount, 1);
    expect(journey.totalTravelSeconds, 300);
    expect(journey.legs, hasLength(2));
    expect((journey.legs.last as TransitLeg).isTransferBoarding, isTrue);
  });

  test('frequency boarding stays FIFO when headways improve', () {
    final service = TransitService(
      id: 'red',
      routeId: 'red',
      directionId: 0,
      shortName: 'R',
      longName: 'Red',
      headways: const [
        HeadwayWindow(
          calendarId: 'daily',
          startSeconds: 8 * 3600,
          endSeconds: 8 * 3600 + 600,
          headwaySeconds: 600,
        ),
        HeadwayWindow(
          calendarId: 'daily',
          startSeconds: 8 * 3600 + 600,
          endSeconds: 10 * 3600,
          headwaySeconds: 120,
        ),
      ],
    );
    final graph = _graph(
      rides: [_ride('A', 'D', 'red', 100)],
      services: [service],
    );
    final planner = JourneyPlanner(graph);
    final early = planner.plan(
      originStopId: 'A',
      destinationStopId: 'D',
      departure: DateTime(2026, 11, 2, 8, 9),
    )!;
    final later = planner.plan(
      originStopId: 'A',
      destinationStopId: 'D',
      departure: DateTime(2026, 11, 2, 8, 10),
    )!;
    expect(early.arrival, later.arrival);
    expect(early.arrival, DateTime(2026, 11, 2, 8, 12, 40));
    expect((early.legs.single as TransitLeg).waitSeconds, 120);
  });

  test('ties are deterministic and zero-cost cycles cannot loop forever', () {
    final rides = [_ride('A', 'D', 'blue', 100), _ride('A', 'D', 'red', 100)];
    final walks = [
      const TransferEdge(fromStopId: 'A', toStopId: 'A', walkSeconds: 0),
    ];
    for (final ordered in [rides, rides.reversed.toList()]) {
      final journey = JourneyPlanner(
        _graph(rides: ordered, walks: walks),
      ).plan(originStopId: 'A', destinationStopId: 'D', departure: departure)!;
      expect((journey.legs.single as TransitLeg).serviceId, 'blue');
      expect(journey.totalTravelSeconds, 101);
    }
  });
}

final class _OracleEdge {
  const _OracleEdge(this.from, this.to, this.service, this.seconds);
  final int from;
  final int to;
  final String? service;
  final int seconds;
}

RideEdge _ride(String from, String to, String service, int seconds) => RideEdge(
  fromStopId: from,
  toStopId: to,
  serviceId: service,
  travelSeconds: seconds,
);
ScheduledStopTime _stop(String id, int seconds) => ScheduledStopTime(
  stopId: id,
  arrivalSeconds: seconds,
  departureSeconds: seconds,
);
ScheduledTrip _trip(String id, String service, List<ScheduledStopTime> times) =>
    ScheduledTrip(
      id: id,
      serviceId: service,
      calendarId: 'daily',
      headsign: 'Destination',
      stopTimes: times,
    );

RoutingGraph _graph({
  List<RideEdge> rides = const [],
  List<TransferEdge> walks = const [],
  List<ScheduledTrip> trips = const [],
  List<TransitService>? services,
}) {
  final ids = <String>{
    for (final edge in rides) ...[edge.fromStopId, edge.toStopId],
    for (final edge in walks) ...[edge.fromStopId, edge.toStopId],
    for (final trip in trips)
      for (final time in trip.stopTimes) time.stopId,
  };
  final serviceIds = {
    for (final edge in rides) edge.serviceId,
    for (final trip in trips) trip.serviceId,
  };
  return RoutingGraph(
    stops: ids.map((id) => StopNode(id: id, name: id)),
    serviceCalendars: [
      ServiceCalendar(
        id: 'daily',
        weekdays: const [true, true, true, true, true, true, true],
        startDate: DateTime(2026),
        endDate: DateTime(2026, 12, 31),
      ),
    ],
    services:
        services ??
        [
          for (final id in serviceIds)
            TransitService(
              id: id,
              routeId: id,
              directionId: 0,
              shortName: id,
              longName: id,
              headways: trips.any((trip) => trip.serviceId == id)
                  ? const []
                  : const [
                      HeadwayWindow(
                        calendarId: 'daily',
                        startSeconds: 6 * 3600,
                        endSeconds: 24 * 3600,
                        headwaySeconds: 2,
                      ),
                    ],
            ),
        ],
    scheduledTrips: trips,
    rideEdges: rides,
    transferEdges: walks,
  );
}
