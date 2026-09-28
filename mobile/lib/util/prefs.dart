import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small app preferences (onboarding seen, theme). Kept in the same secure
/// storage as the token rather than adding a SharedPreferences dependency
/// for two values. Every read falls back to the default on any error, so a
/// storage problem never blocks the app from starting.
class Prefs {
  static const _storage = FlutterSecureStorage();
  static const _onboardingKey = 'onboarding_seen';
  static const _themeKey = 'theme_mode';

  static Future<bool> onboardingSeen() async {
    try {
      return await _storage.read(key: _onboardingKey) == '1';
    } catch (_) {
      return false;
    }
  }

  static Future<void> setOnboardingSeen() async {
    try {
      await _storage.write(key: _onboardingKey, value: '1');
    } catch (_) {}
  }

  static Future<ThemeMode> themeMode() async {
    try {
      return switch (await _storage.read(key: _themeKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      return ThemeMode.system;
    }
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    try {
      await _storage.write(key: _themeKey, value: mode.name);
    } catch (_) {}
  }
}
