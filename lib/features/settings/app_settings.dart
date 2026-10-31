import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'app_settings.freezed.dart';

@freezed
abstract class AppSettings with _$AppSettings {
  const factory AppSettings({
    @Default(ThemeMode.dark) ThemeMode themeMode,
    @Default(Locale('ar')) Locale locale,

    /// Null means "use the default name derived from the device fingerprint".
    String? deviceName,

    /// Null means the platform default folder. Android keeps the app folder.
    String? downloadPath,

    /// Optional PIN senders must enter (4-8 digits). Null means no PIN.
    String? receivePin,
  }) = _AppSettings;
}

/// Overridden in `main` with the real instance, so settings load synchronously.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider not overridden'),
);

class AppSettingsNotifier extends Notifier<AppSettings> {
  static const _theme = 'themeMode';
  static const _locale = 'locale';
  static const _deviceName = 'deviceName';
  static const _downloadPath = 'downloadPath';
  static const _receivePin = 'receivePin';

  late final SharedPreferences _prefs;

  @override
  AppSettings build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == _prefs.getString(_theme),
        orElse: () => ThemeMode.dark,
      ),
      locale: Locale(_prefs.getString(_locale) ?? 'ar'),
      deviceName: _prefs.getString(_deviceName),
      downloadPath: _prefs.getString(_downloadPath),
      receivePin: _prefs.getString(_receivePin),
    );
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _prefs.setString(_theme, mode.name);
  }

  void setLocale(Locale locale) {
    state = state.copyWith(locale: locale);
    _prefs.setString(_locale, locale.languageCode);
  }

  /// An empty name goes back to the default.
  void setDeviceName(String? name) {
    final clean = name?.trim();
    final value = (clean == null || clean.isEmpty) ? null : clean;
    state = state.copyWith(deviceName: value);
    _persist(_deviceName, value);
  }

  void setDownloadPath(String? path) {
    state = state.copyWith(downloadPath: path);
    _persist(_downloadPath, path);
  }

  /// Only 4-8 digits are accepted. Anything else clears the PIN.
  void setReceivePin(String? pin) {
    final valid = pin != null && RegExp(r'^\d{4,8}$').hasMatch(pin);
    final value = valid ? pin : null;
    state = state.copyWith(receivePin: value);
    _persist(_receivePin, value);
  }

  void _persist(String key, String? value) {
    if (value == null) {
      _prefs.remove(key);
    } else {
      _prefs.setString(key, value);
    }
  }
}

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);
