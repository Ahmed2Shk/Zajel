import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform_api.g.dart';

final platformApiProvider = Provider<PlatformApi>((ref) => PlatformApi());

/// Device info from the native (Kotlin) side. Only available on Android.
final nativeDeviceInfoProvider = FutureProvider<NativeDeviceInfo>(
  (ref) => ref.watch(platformApiProvider).getDeviceInfo(),
);

/// Launchable apps that can be sent as APK files. Empty away from Android.
final installedAppsProvider = FutureProvider.autoDispose<List<NativeAppInfo>>((
  ref,
) async {
  if (kIsWeb || !Platform.isAndroid) return const [];
  return ref.watch(platformApiProvider).listInstalledApps();
});
