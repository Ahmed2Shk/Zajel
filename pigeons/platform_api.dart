import 'package:pigeon/pigeon.dart';
// Regenerate with: dart run pigeon --input pigeons/platform_api.dart
@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/platform_api.g.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/zajel/zajel/PlatformApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.zajel.zajel'),
  ),
)
class NativeDeviceInfo {
  NativeDeviceInfo({required this.model, required this.sdkInt});
  String model;
  int sdkInt;
}
/// An installed app that can be sent as an APK.
class NativeAppInfo {
  NativeAppInfo({
    required this.name,
    required this.packageName,
    required this.apkPath,
    required this.size,
  });

  String name;
  String packageName;
  String apkPath;
  int size;
}

@HostApi()
abstract class PlatformApi {
  NativeDeviceInfo getDeviceInfo();
  /// Holds or releases the Wi-Fi multicast lock, needed to receive discovery
  /// packets on Android.
  void setMulticastLock(bool enabled);
  /// Starts the foreground service that keeps transfers alive with the screen
  /// off: a notification, a Wi-Fi lock and a partial wake lock. [title] and
  /// [text] are the already-localized notification strings.
  void startTransferService(String title, String text);
  void stopTransferService();

  /// Android 13+: asks for the notification permission (once) so the
  /// ongoing-transfer notification shows. Transfers work without it.
  void requestNotificationPermission();
  /// CPU time this process has used so far, in milliseconds.
  int getProcessCpuTimeMs();

  /// Apps with a launcher icon, so they can be sent as APK files. Only the
  /// base APK is listed; split APKs are not supported.
  List<NativeAppInfo> listInstalledApps();

  /// The launcher icon of an app as PNG bytes, or null. Drawn on a background
  /// thread, so a long list of apps can ask for icons as they scroll into view.
  @async
  Uint8List? getAppIcon(String packageName, int sizePx);
}
/// The Android data path. A TLS server written in Kotlin receives file chunks
/// straight from the socket onto the disk with `FileChannel`, so file bytes
/// never pass through Dart. Dart keeps the control plane: it decides who may
/// upload what and is told after each chunk.
@HostApi()
abstract class NativeDataApi {
  /// Starts the server with the device's TLS identity (PEM, PKCS#8 key) and
  /// returns the port it listens on.
  int startDataServer(String certificatePem, String privateKeyPem);
  /// Allows one file to be uploaded. [path] is the pre-sized `.zajel-part`.
  void registerUpload(
    String sessionId,
    String fileId,
    String token,
    String path,
    int size,
    String senderAddress,
  );
  void unregisterSession(String sessionId);
  void stopDataServer();
}
@FlutterApi()
abstract class NativeDataCallbacks {
  /// A whole chunk is on disk. Returns the HTTP status to answer the sender
  /// with: 200 to accept, 422 for a checksum failure on the last chunk.
  @async
  int onNativeChunk(String sessionId, String fileId, int offset, int length);
}

/// Wi-Fi credentials of a hotspot or Wi-Fi Direct group this phone created.
class NativeNetworkInfo {
  NativeNetworkInfo({required this.ssid, required this.passphrase});

  String ssid;
  String passphrase;
}

/// A Zajel receiver found over Wi-Fi Direct service discovery.
class NativeDirectPeer {
  NativeDirectPeer({
    required this.deviceAddress,
    required this.alias,
    required this.fingerprint,
    required this.port,
    this.networkName,
    this.passphrase,
  });

  String deviceAddress;
  String alias;
  String fingerprint;
  int port;

  /// The receiver's group credentials (Android 10+). With them a sender joins
  /// the group without an invitation prompt on the receiver.
  String? networkName;
  String? passphrase;
}

/// Router-free transports (SPEC.md, Phase 3). Errors use the codes
/// `permission_denied`, `location_off`, `wifi_off`, `unsupported`, `busy`,
/// `timeout` and `failed`, so Dart can show a clear message for each.
@HostApi()
abstract class TransportApi {
  /// Asks for the Wi-Fi permissions of this Android version (NEARBY_WIFI_DEVICES
  /// on 13+, location before that). Returns whether they were granted.
  @async
  bool requestWifiPermissions();

  bool isLocationEnabled();

  bool isWifiEnabled();

  bool supports5GHz();

  /// Starts a LocalOnlyHotspot and returns its name and password. The system
  /// chooses the band; an app cannot pick 5 GHz for this kind of hotspot.
  @async
  NativeNetworkInfo startHotspot();

  void stopHotspot();

  /// Joins a hotspot and binds this app's traffic to it. Android 10+ shows the
  /// system's own approval dialog.
  @async
  void joinNetwork(String ssid, String passphrase);

  void leaveNetwork();

  /// Becomes a Wi-Fi Direct group owner (on 5 GHz where supported) and
  /// advertises this device so senders can find it.
  @async
  void startDirectReceiver(String alias, String fingerprint, int port);

  void stopDirectReceiver();

  @async
  List<NativeDirectPeer> discoverDirectPeers(int timeoutMs);

  /// Connects to a receiver's group and returns the group owner's IP address.
  @async
  String connectDirect(NativeDirectPeer peer);

  void disconnectDirect();
}
