import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/favourites/favourites.dart';

final class SharedPreferencesFavouritesRepository
    implements FavouritesRepository {
  SharedPreferencesFavouritesRepository({SharedPreferencesAsync? preferences})
    : _preferencesOverride = preferences;

  static const storageKey = 'transitkl.favourites';
  final SharedPreferencesAsync? _preferencesOverride;
  late final SharedPreferencesAsync _store =
      _preferencesOverride ?? SharedPreferencesAsync();

  @override
  Future<FavouritesSnapshot> load() async {
    final serialized = await _store.getString(storageKey);
    if (serialized == null) return FavouritesSnapshot();
    final data = _object(jsonDecode(serialized));
    if (data['version'] != 1) {
      throw const FormatException('Unsupported favourites version.');
    }
    return FavouritesSnapshot(
      stations: _list(data['stations']).map(_readStation),
      journeys: _list(data['journeys']).map((value) {
        final pair = _object(value);
        return SavedJourney(
          origin: _readStation(pair['origin']),
          destination: _readStation(pair['destination']),
        );
      }),
    );
  }

  @override
  Future<void> save(FavouritesSnapshot favourites) => _store.setString(
    storageKey,
    jsonEncode({
      'version': 1,
      'stations': favourites.stations.map(_writeStation).toList(),
      'journeys': [
        for (final journey in favourites.journeys)
          {
            'origin': _writeStation(journey.origin),
            'destination': _writeStation(journey.destination),
          },
      ],
    }),
  );

  static Map<String, Object?> _object(Object? value) {
    if (value is Map<String, Object?>) return value;
    throw const FormatException('Invalid favourites object.');
  }

  static List<Object?> _list(Object? value) {
    if (value is List<Object?>) return value;
    throw const FormatException('Invalid favourites list.');
  }

  static SavedStation _readStation(Object? value) {
    final data = _object(value);
    final label = data['label'];
    final ids = _list(data['stopIds']);
    if (label is! String ||
        label.trim().isEmpty ||
        ids.isEmpty ||
        ids.any((id) => id is! String || id.trim().isEmpty)) {
      throw const FormatException('Invalid saved station.');
    }
    return SavedStation(label: label, stopIds: ids.cast<String>());
  }

  static Map<String, Object?> _writeStation(SavedStation station) => {
    'label': station.label,
    'stopIds': station.stopIds,
  };
}
