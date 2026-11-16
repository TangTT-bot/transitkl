import 'package:flutter/foundation.dart';

import '../../domain/routing/journey_planner.dart';
import '../../domain/routing/routing_graph.dart';
import '../../domain/search/journey_search_service.dart';

typedef JourneySearchRunner =
    Future<Journey?> Function(JourneySearchRequest request);

/// Immutable input crossing the worker-isolate boundary on mobile/desktop.
final class JourneySearchRequest {
  const JourneySearchRequest({
    required this.graph,
    required this.origin,
    required this.destination,
    required this.departure,
  });

  final RoutingGraph graph;
  final StationGroup origin;
  final StationGroup destination;
  final DateTime departure;
}

Future<Journey?> runJourneySearch(JourneySearchRequest request) =>
    compute(_search, request, debugLabel: 'TransitKL Recommended search');

Journey? _search(JourneySearchRequest request) =>
    JourneySearchService(request.graph).search(
      origin: request.origin,
      destination: request.destination,
      departure: request.departure,
    );
