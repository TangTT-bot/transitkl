import 'dart:convert';
import 'dart:io';

import 'package:transitkl/domain/routing/journey_planner.dart';
import 'package:transitkl/domain/routing/routing_graph.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 5) {
    stderr.writeln(
      'Usage: dart run tool/route_demo.dart '
      '<routing-graph.json> <origin name or ID> '
      '<destination name or ID> <YYYY-MM-DD> <HH:MM[:SS]>',
    );
    exitCode = 64;
    return;
  }

  try {
    final graphFile = File(arguments[0]);
    final decoded = jsonDecode(await graphFile.readAsString());
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('The routing graph root must be an object.');
    }
    final graph = RoutingGraph.fromJson(decoded.cast<String, Object?>());
    final departure = _parseDeparture(arguments[3], arguments[4]);
    final origins = _findStops(graph, arguments[1]);
    final destinations = _findStops(graph, arguments[2]);
    if (origins.isEmpty) {
      throw ArgumentError('No stop matched origin "${arguments[1]}".');
    }
    if (destinations.isEmpty) {
      throw ArgumentError('No stop matched destination "${arguments[2]}".');
    }

    final planner = JourneyPlanner(graph);
    Journey? bestJourney;
    for (final origin in origins) {
      for (final destination in destinations) {
        final candidate = planner.plan(
          originStopId: origin.id,
          destinationStopId: destination.id,
          departure: departure,
        );
        if (candidate != null && _isBetter(candidate, bestJourney)) {
          bestJourney = candidate;
        }
      }
    }

    if (bestJourney == null) {
      stdout.writeln(
        'No route was found at ${_formatDateTime(departure)}. '
        'The services may not run on that date or at that time.',
      );
      exitCode = 2;
      return;
    }
    _printJourney(graph, bestJourney);
  } on Object catch (error) {
    stderr.writeln('Route demo failed: $error');
    exitCode = 1;
  }
}

List<StopNode> _findStops(RoutingGraph graph, String query) {
  final exactId = graph.stops[query];
  if (exactId != null) {
    return [exactId];
  }
  final normalized = _normalize(query);
  if (normalized.isEmpty) {
    return const [];
  }
  final exactNames = graph.stops.values
      .where(
        (stop) =>
            stop.normalizedName == normalized ||
            _normalize(stop.name) == normalized,
      )
      .toList(growable: false);
  if (exactNames.isNotEmpty) {
    return exactNames;
  }
  return graph.stops.values
      .where(
        (stop) =>
            stop.normalizedName.contains(normalized) ||
            _normalize(stop.name).contains(normalized),
      )
      .toList(growable: false);
}

bool _isBetter(Journey candidate, Journey? current) {
  if (current == null) return true;
  if (candidate.generalizedCostSeconds != current.generalizedCostSeconds) {
    return candidate.generalizedCostSeconds < current.generalizedCostSeconds;
  }
  return candidate.totalTravelSeconds < current.totalTravelSeconds;
}

void _printJourney(RoutingGraph graph, Journey journey) {
  final origin = graph.stops[journey.originStopId]!.name;
  final destination = graph.stops[journey.destinationStopId]!.name;
  stdout.writeln('$origin -> $destination');
  stdout.writeln(
    'Depart ${_formatDateTime(journey.departure)}, '
    'arrive ${_formatDateTime(journey.arrival)} '
    '(${_formatDuration(journey.totalTravelSeconds)}, '
    '${journey.transferCount} transfer(s))',
  );

  for (final (index, leg) in journey.legs.indexed) {
    final from = graph.stops[leg.fromStopId]!.name;
    final to = graph.stops[leg.toStopId]!.name;
    switch (leg) {
      case TransitLeg():
        final service = graph.services[leg.serviceId]!;
        stdout.writeln(
          '${index + 1}. ${service.shortName} $from -> $to '
          '(${leg.stopIds.length - 1} segment(s), '
          '${_formatDuration(leg.rideSeconds)} riding, '
          '${_formatDuration(leg.waitSeconds)} '
          '${leg.isScheduled ? 'scheduled wait' : 'average wait'})',
        );
      case WalkingLeg():
        final distance = leg.distanceMetres == null
            ? ''
            : ', ${leg.distanceMetres} m';
        stdout.writeln(
          '${index + 1}. Walk $from -> $to '
          '(${_formatDuration(leg.walkSeconds)}$distance)',
        );
    }
  }
}

DateTime _parseDeparture(String dateValue, String timeValue) {
  final date = DateTime.tryParse(dateValue);
  if (date == null ||
      dateValue.length != 10 ||
      '${date.year.toString().padLeft(4, '0')}-'
              '${date.month.toString().padLeft(2, '0')}-'
              '${date.day.toString().padLeft(2, '0')}' !=
          dateValue) {
    throw FormatException('Date must use YYYY-MM-DD.');
  }
  final parts = timeValue.split(':');
  if (parts.length != 2 && parts.length != 3) {
    throw FormatException('Time must use HH:MM or HH:MM:SS.');
  }
  final hours = int.parse(parts[0]);
  final minutes = int.parse(parts[1]);
  final seconds = parts.length == 3 ? int.parse(parts[2]) : 0;
  if (hours < 0 || minutes < 0 || minutes > 59 || seconds < 0 || seconds > 59) {
    throw FormatException('Invalid time: $timeValue');
  }
  if (hours > 23) {
    throw FormatException('CLI clock time must be between 00:00 and 23:59.');
  }
  return DateTime(date.year, date.month, date.day, hours, minutes, seconds);
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(' +'), ' ');

String _formatDateTime(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}:'
      '${value.second.toString().padLeft(2, '0')}';
}

String _formatDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600 + 59) ~/ 60;
  if (hours == 0) return '$minutes min';
  return '$hours h $minutes min';
}
