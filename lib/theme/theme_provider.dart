import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_mode_enum.dart';

const _themeModeKey = 'themeMode';

final initialThemeModeProvider = Provider<ThemeMode>((ref) {
  return ThemeMode.system;
});

final themeModeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(
  ThemeNotifier.new,
);

class ThemeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final initialMode = ref.read(initialThemeModeProvider);
    _load();
    return initialMode;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_themeModeKey);
    final nextMode = _themeModeFromString(value);
    if (nextMode != state) {
      state = nextMode;
    }
  }

  Future<void> _save(AppThemeMode value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, value.name);
  }

  Future<void> setSystem() async {
    state = ThemeMode.system;
    await _save(AppThemeMode.system);
  }

  Future<void> setLight() async {
    state = ThemeMode.light;
    await _save(AppThemeMode.light);
  }

  Future<void> setDark() async {
    state = ThemeMode.dark;
    await _save(AppThemeMode.dark);
  }
}

ThemeMode themeModeFromPrefsString(String? value) {
  return _themeModeFromString(value);
}

ThemeMode _themeModeFromString(String? value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}
