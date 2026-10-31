import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zajel/features/settings/app_settings.dart';

Future<ProviderContainer> _container(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('defaults: dark, Arabic, no name, no folder, no PIN', () async {
    final settings = (await _container({})).read(appSettingsProvider);
    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.locale, const Locale('ar'));
    expect(settings.deviceName, isNull);
    expect(settings.downloadPath, isNull);
    expect(settings.receivePin, isNull);
  });

  test('settings survive a restart', () async {
    final first = await _container({});
    first.read(appSettingsProvider.notifier)
      ..setThemeMode(ThemeMode.light)
      ..setLocale(const Locale('en'))
      ..setDeviceName('  My phone ')
      ..setDownloadPath('/tmp/zajel')
      ..setReceivePin('1234');

    // A new container over the same preferences is a fresh app launch.
    final prefs = await SharedPreferences.getInstance();
    final second = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(second.dispose);
    final settings = second.read(appSettingsProvider);
    expect(settings.themeMode, ThemeMode.light);
    expect(settings.locale, const Locale('en'));
    expect(settings.deviceName, 'My phone');
    expect(settings.downloadPath, '/tmp/zajel');
    expect(settings.receivePin, '1234');
  });

  test('an empty device name goes back to the default', () async {
    final container = await _container({'deviceName': 'Old'});
    container.read(appSettingsProvider.notifier).setDeviceName('   ');
    expect(container.read(appSettingsProvider).deviceName, isNull);
    expect((await SharedPreferences.getInstance()).containsKey('deviceName'), isFalse);
  });

  test('only 4-8 digit PINs are accepted', () async {
    final container = await _container({});
    final notifier = container.read(appSettingsProvider.notifier);
    for (final bad in ['', '123', '123456789', 'abcd', '12 34', '١٢٣٤']) {
      notifier.setReceivePin(bad);
      expect(container.read(appSettingsProvider).receivePin, isNull, reason: bad);
    }
    for (final good in ['1234', '12345678']) {
      notifier.setReceivePin(good);
      expect(container.read(appSettingsProvider).receivePin, good);
    }
    notifier.setReceivePin(null);
    expect(container.read(appSettingsProvider).receivePin, isNull);
  });

  test('an unknown stored theme falls back to dark', () async {
    final container = await _container({'themeMode': 'neon'});
    expect(container.read(appSettingsProvider).themeMode, ThemeMode.dark);
  });
}
