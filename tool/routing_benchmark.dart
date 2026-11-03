import 'dart:convert';
import 'dart:io';

import 'package:transitkl/domain/routing/routing_graph.dart';
import 'package:transitkl/domain/search/journey_search_service.dart';

/// A repeatable desktop smoke benchmark, not a device performance claim.
Future<void> main(List<String> arguments) async {
  final path = arguments.isEmpty
      ? 'assets/data/transitkl-rail-routing.json'
      : arguments.single;
  final decoded =
      jsonDecode(await File(path).readAsString()) as Map<String, Object?>;
  final search = JourneySearchService(RoutingGraph.fromJson(decoded));
  final pairs = [
    ('putra heights', 'pasar seni'),
    ('gombak', 'kajang'),
    ('titiwangsa', 'bukit bintang'),
    ('ampang', 'kwasa damansara'),
    if (search.stations.any((station) => station.id == 'batu caves')) ...[
      ('batu caves', 'klcc'),
      ('gombak', 'batu caves'),
    ],
  ];
  final departure = DateTime(2026, 11, 3, 8);
  final samples = <int>[];
  var queries = 0;
  // First round warms up Dart JIT and is excluded from reported samples.
  for (var round = 0; round < 6; round++) {
    for (final (from, to) in pairs) {
      final origin = search.stations.singleWhere(
        (station) => station.id == from,
      );
      final destination = search.stations.singleWhere(
        (station) => station.id == to,
      );
      final timer = Stopwatch()..start();
      final journey = search.search(
        origin: origin,
        destination: destination,
        departure: departure,
      );
      timer.stop();
      if (journey == null) throw StateError('No route for $from -> $to');
      if (round > 0) {
        queries++;
        samples.add(timer.elapsedMicroseconds);
      }
    }
  }
  samples.sort();
  final median = samples[samples.length ~/ 2] / 1000;
  final p95 = samples[(samples.length * 0.95).ceil() - 1] / 1000;
  stdout.writeln(
    'Recommended: $queries station searches, '
    'median ${median.toStringAsFixed(2)} ms, '
    'p95 ${p95.toStringAsFixed(2)} ms',
  );
}
