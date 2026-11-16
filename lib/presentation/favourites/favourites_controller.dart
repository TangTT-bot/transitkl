import 'package:flutter/foundation.dart';

import '../../domain/favourites/favourites.dart';
import '../../domain/search/journey_search_service.dart';

final class FavouritesController extends ChangeNotifier {
  FavouritesController(this._repository, Iterable<StationGroup> stations)
    : _resolver = SavedStationResolver(stations);

  final FavouritesRepository _repository;
  final SavedStationResolver _resolver;
  bool _disposed = false;
  bool _busy = false;
  bool _loadFailed = false;
  FavouritesSnapshot? _snapshot;

  FavouritesSnapshot? get snapshot => _snapshot;
  bool get busy => _busy;
  bool get loadFailed => _loadFailed;
  bool get canEdit => !_disposed && !_busy && _snapshot != null;

  StationGroup? resolve(SavedStation saved) => _resolver.resolve(saved);

  bool hasStation(StationGroup station) =>
      _snapshot?.stations.any((saved) => resolve(saved) == station) ?? false;

  bool hasJourney(StationGroup from, StationGroup to) =>
      _snapshot?.journeys.any((saved) => _matchesJourney(saved, from, to)) ??
      false;

  bool _matchesJourney(
    SavedJourney saved,
    StationGroup from,
    StationGroup to,
  ) => resolve(saved.origin) == from && resolve(saved.destination) == to;

  Future<void> load() async {
    if (_disposed || _busy || _snapshot != null) return;
    _busy = true;
    _loadFailed = false;
    notifyListeners();
    try {
      _snapshot = await _repository.load();
    } on Object {
      _loadFailed = true;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> toggleStation(StationGroup station) async {
    if (!canEdit) return false;
    final previous = _snapshot!;
    final stations = hasStation(station)
        ? previous.stations.where((saved) => resolve(saved) != station)
        : [...previous.stations, SavedStation.fromGroup(station)];
    return _save(
      FavouritesSnapshot(stations: stations, journeys: previous.journeys),
    );
  }

  Future<bool> toggleJourney(StationGroup from, StationGroup to) async {
    if (!canEdit || from == to) return false;
    final previous = _snapshot!;
    final journeys = hasJourney(from, to)
        ? previous.journeys.where((saved) => !_matchesJourney(saved, from, to))
        : [
            ...previous.journeys,
            SavedJourney(
              origin: SavedStation.fromGroup(from),
              destination: SavedStation.fromGroup(to),
            ),
          ];
    return _save(
      FavouritesSnapshot(stations: previous.stations, journeys: journeys),
    );
  }

  Future<bool> removeStation(SavedStation station) async {
    if (!canEdit) return false;
    return _save(
      FavouritesSnapshot(
        stations: _snapshot!.stations.where((saved) => saved != station),
        journeys: _snapshot!.journeys,
      ),
    );
  }

  Future<bool> removeJourney(SavedJourney journey) async {
    if (!canEdit) return false;
    return _save(
      FavouritesSnapshot(
        stations: _snapshot!.stations,
        journeys: _snapshot!.journeys.where((saved) => saved != journey),
      ),
    );
  }

  Future<bool> _save(FavouritesSnapshot updated) async {
    _busy = true;
    notifyListeners();
    try {
      await _repository.save(updated);
      _snapshot = updated;
      return true;
    } on Object {
      return false;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
