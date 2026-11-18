import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class AppearanceStore {
  Future<ThemeMode> load();
  Future<void> save(ThemeMode mode);
}

final class LocalAppearanceStore implements AppearanceStore {
  static const _key = 'transitkl.appearance';
  late final _preferences = SharedPreferencesAsync();

  @override
  Future<ThemeMode> load() async =>
      switch (await _preferences.getString(_key)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  @override
  Future<void> save(ThemeMode mode) => _preferences.setString(_key, mode.name);
}

final class AppearanceController extends ChangeNotifier {
  AppearanceController(this._store);

  final AppearanceStore _store;
  ThemeMode _mode = ThemeMode.system;
  bool _saving = false;
  bool _disposed = false;
  int _revision = 0;

  ThemeMode get mode => _mode;
  bool get saving => _saving;

  Future<void> load() async {
    final revision = _revision;
    try {
      final stored = await _store.load();
      if (_disposed || _revision != revision) return;
      _mode = stored;
      notifyListeners();
    } on Object {
      // A storage failure must not stop offline journey planning.
    }
  }

  Future<bool> select(ThemeMode mode) async {
    if (_disposed || _saving) return false;
    if (mode == _mode) return true;
    _revision++;
    _saving = true;
    notifyListeners();
    try {
      await _store.save(mode);
      _mode = mode;
      return true;
    } on Object {
      return false;
    } finally {
      _saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
