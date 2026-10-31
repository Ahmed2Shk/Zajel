import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/logging/app_log.dart';
import 'core/logging/log_providers.dart';
import 'features/settings/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // A local log the user can export. It works offline and stays on the device.
  AppLog? log;
  if (!kIsWeb) {
    try {
      final support = await getApplicationSupportDirectory();
      log = await AppLog.open(Directory('${support.path}/logs'));
      log.info('app', 'started');
    } catch (_) {
      log = null;
    }
  }
  final logger = log;
  if (logger != null) {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      logger.error('flutter', details.exception, details.stack);
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      logger.error('platform', error, stack);
      return true;
    };
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appLogProvider.overrideWithValue(logger),
      ],
      child: const ZajelApp(),
    ),
  );
}
