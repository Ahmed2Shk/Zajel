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
  /// CPU time this process has used so far, in milliseconds.
  int getProcessCpuTimeMs();
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
