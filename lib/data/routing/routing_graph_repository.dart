import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/routing/routing_graph.dart';

abstract interface class RoutingGraphRepository {
  Future<TransitDataBundle> load();
}

final class AssetRoutingGraphRepository implements RoutingGraphRepository {
  AssetRoutingGraphRepository({
    AssetBundle? assetBundle,
    this.assetPath = 'assets/data/rapid-rail-kl-routing.json',
  }) : _assetBundle = assetBundle ?? rootBundle;

  final AssetBundle _assetBundle;
  final String assetPath;

  @override
  Future<TransitDataBundle> load() async {
    final source = await _assetBundle.loadString(assetPath);
    final decoded = jsonDecode(source);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('Routing data must be a JSON object.');
    }
    return TransitDataBundle.fromJson(decoded.cast<String, Object?>());
  }
}

final class TransitDataBundle {
  const TransitDataBundle({required this.feed, required this.graph});

  factory TransitDataBundle.fromJson(Map<String, Object?> json) {
    final feed = json['feed'];
    if (feed is! Map<String, Object?>) {
      throw const FormatException('Routing data must contain feed metadata.');
    }
    return TransitDataBundle(
      feed: TransitFeedMetadata.fromJson(feed),
      graph: RoutingGraph.fromJson(json),
    );
  }

  final TransitFeedMetadata feed;
  final RoutingGraph graph;
}

final class TransitFeedMetadata {
  const TransitFeedMetadata({
    required this.id,
    required this.sourceSha256,
    required this.serviceDateStart,
    required this.serviceDateEnd,
  });

  factory TransitFeedMetadata.fromJson(Map<String, Object?> json) {
    return TransitFeedMetadata(
      id: _requiredString(json, 'id'),
      sourceSha256: _requiredString(json, 'sourceSha256'),
      serviceDateStart: _gtfsDate(json, 'serviceDateStart'),
      serviceDateEnd: _gtfsDate(json, 'serviceDateEnd'),
    );
  }

  final String id;
  final String sourceSha256;
  final DateTime serviceDateStart;
  final DateTime serviceDateEnd;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

DateTime _gtfsDate(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  if (value.length != 8 || int.tryParse(value) == null) {
    throw FormatException('$key must use GTFS YYYYMMDD format.');
  }
  final parsed = DateTime(
    int.parse(value.substring(0, 4)),
    int.parse(value.substring(4, 6)),
    int.parse(value.substring(6, 8)),
  );
  final normalized =
      '${parsed.year.toString().padLeft(4, '0')}'
      '${parsed.month.toString().padLeft(2, '0')}'
      '${parsed.day.toString().padLeft(2, '0')}';
  if (normalized != value) {
    throw FormatException('$key contains an invalid date.');
  }
  return parsed;
}
