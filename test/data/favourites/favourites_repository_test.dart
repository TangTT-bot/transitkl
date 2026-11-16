import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transitkl/data/favourites/shared_preferences_favourites_repository.dart';
import 'package:transitkl/domain/favourites/favourites.dart';
import 'package:transitkl/domain/search/journey_search_service.dart';
import 'package:transitkl/presentation/favourites/favourites_controller.dart';

const _klang = StationGroup(
  id: 'klang',
  name: 'Klang',
  stopIds: ['ktmb:54700'],
  modes: [StationMode.ktmKomuter],
);
const _bd28 = StationGroup(
  id: 'bd28 ktm klang',
  name: 'BD28 KTM Klang',
  stopIds: ['prasarana_rapid_bus_kl:1006000'],
  modes: [StationMode.rapidBus],
);
const _monash = StationGroup(
  id: 'sunu monash',
  name: 'SunU-Monash',
  stopIds: ['prasarana_rapid_rail:BRT5'],
  modes: [StationMode.sunwayBrt],
);

void main() {
  test(
    'round-trips station and directed journey IDs through a new repository',
    () async {
      final preferences = _MemoryPreferences();
      SharedPreferencesFavouritesRepository repository() =>
          SharedPreferencesFavouritesRepository(preferences: preferences);
      final controller = FavouritesController(repository(), [
        _klang,
        _bd28,
        _monash,
      ]);
      addTearDown(controller.dispose);
      await controller.load();
      expect(await controller.toggleStation(_klang), isTrue);
      expect(await controller.toggleJourney(_klang, _monash), isTrue);
      expect(await controller.toggleJourney(_monash, _klang), isTrue);
      expect(await controller.toggleJourney(_klang, _klang), isFalse);

      final reopened = FavouritesController(repository(), [
        _klang,
        _bd28,
        _monash,
      ]);
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.snapshot!.stations.single.stopIds, _klang.stopIds);
      expect(reopened.hasStation(_klang), isTrue);
      expect(reopened.hasStation(_bd28), isFalse);
      expect(reopened.snapshot!.journeys, hasLength(2));
      expect(reopened.hasJourney(_klang, _monash), isTrue);
      expect(reopened.hasJourney(_monash, _klang), isTrue);

      expect(await reopened.toggleJourney(_klang, _monash), isTrue);
      expect(reopened.hasJourney(_klang, _monash), isFalse);
      expect(reopened.hasJourney(_monash, _klang), isTrue);
      expect(
        await reopened.removeStation(reopened.snapshot!.stations.single),
        isTrue,
      );
      final saved = await repository().load();
      expect(saved.stations, isEmpty);
      expect(saved.journeys.single.origin.stopIds, _monash.stopIds);
    },
  );

  test(
    'read failure is retryable without overwriting the saved value',
    () async {
      final preferences = _MemoryPreferences()..value = '{"version":2}';
      final repository = SharedPreferencesFavouritesRepository(
        preferences: preferences,
      );
      final controller = FavouritesController(repository, [_klang]);
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.loadFailed, isTrue);
      expect(await controller.toggleStation(_klang), isFalse);
      expect(preferences.value, '{"version":2}');
      preferences.value = null;
      await controller.load();
      expect(controller.loadFailed, isFalse);
      expect(controller.canEdit, isTrue);
    },
  );

  test('failed save does not claim the favourite was saved', () async {
    final preferences = _MemoryPreferences()..rejectWrites = true;
    final controller = FavouritesController(
      SharedPreferencesFavouritesRepository(preferences: preferences),
      [_klang],
    );
    addTearDown(controller.dispose);
    await controller.load();
    expect(await controller.toggleStation(_klang), isFalse);
    expect(controller.hasStation(_klang), isFalse);
    preferences.rejectWrites = false;
    expect(await controller.toggleStation(_klang), isTrue);
    expect(controller.hasStation(_klang), isTrue);
  });

  test(
    'resolves surviving IDs but never guesses by name or across split stations',
    () {
      const separate = StationGroup(
        id: 'new',
        name: 'Klang',
        stopIds: ['other:id'],
      );
      final fallback = SavedStation.fromGroup(_klang);
      final withOldPlatform = SavedStation(
        label: 'Old Klang label',
        stopIds: ['removed:id', ..._klang.stopIds],
      );
      final split = SavedStation(
        label: 'Old combined Klang label',
        stopIds: [..._klang.stopIds, ...separate.stopIds],
      );
      expect(SavedStationResolver([separate]).resolve(fallback), isNull);
      expect(SavedStationResolver([_klang]).resolve(withOldPlatform), _klang);
      expect(SavedStationResolver([_klang, separate]).resolve(split), isNull);
    },
  );
}

class _MemoryPreferences implements SharedPreferencesAsync {
  final _state = _PreferenceState();
  String? get value => _state.value;
  set value(String? value) => _state.value = value;
  bool get rejectWrites => _state.rejectWrites;
  set rejectWrites(bool value) => _state.rejectWrites = value;

  @override
  Future<String?> getString(String key) async => value;

  @override
  Future<void> setString(String key, String updated) async {
    if (rejectWrites) throw Exception('Write failed');
    value = updated;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreferenceState {
  String? value;
  bool rejectWrites = false;
}
