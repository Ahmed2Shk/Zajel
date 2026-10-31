import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform_api.g.dart';

final platformApiProvider = Provider<PlatformApi>((ref) => PlatformApi());

/// Device info from the native (Kotlin) side. Only available on Android.
final nativeDeviceInfoProvider = FutureProvider<NativeDeviceInfo>(
  (ref) => ref.watch(platformApiProvider).getDeviceInfo(),
);
