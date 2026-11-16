import '../search/journey_search_service.dart';

final class SavedStation {
  SavedStation({required this.label, required Iterable<String> stopIds})
    : stopIds = List.unmodifiable(stopIds);

  factory SavedStation.fromGroup(StationGroup group) =>
      SavedStation(label: group.displayLabel, stopIds: group.stopIds);

  // The label is only a fallback for removed stops. It is not a routing ID.
  final String label;
  final List<String> stopIds;
}

final class SavedJourney {
  const SavedJourney({required this.origin, required this.destination});

  final SavedStation origin;
  final SavedStation destination;
}

final class FavouritesSnapshot {
  FavouritesSnapshot({
    Iterable<SavedStation> stations = const [],
    Iterable<SavedJourney> journeys = const [],
  }) : stations = List.unmodifiable(stations),
       journeys = List.unmodifiable(journeys);

  final List<SavedStation> stations;
  final List<SavedJourney> journeys;
}

abstract interface class FavouritesRepository {
  Future<FavouritesSnapshot> load();
  Future<void> save(FavouritesSnapshot favourites);
}

final class SavedStationResolver {
  SavedStationResolver(Iterable<StationGroup> stations)
    : _byStopId = {
        for (final station in stations)
          for (final stopId in station.stopIds) stopId: station,
      };

  final Map<String, StationGroup> _byStopId;

  /// Resolve against the current graph without guessing from similar names.
  /// If a formerly grouped station has split, require a fresh selection.
  StationGroup? resolve(SavedStation saved) {
    final matches = {for (final id in saved.stopIds) ?_byStopId[id]};
    return matches.length == 1 ? matches.single : null;
  }
}
