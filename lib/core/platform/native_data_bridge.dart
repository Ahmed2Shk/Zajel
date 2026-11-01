import '../security/device_identity.dart';
import 'platform_api.g.dart';

/// Called when a whole chunk is on disk. Returns the HTTP status for the sender.
typedef NativeChunkHandler =
    Future<int> Function(String sessionId, String fileId, int offset, int length);

/// Called a few times a second with the bytes of a file that are in chunks still
/// arriving, so progress moves before a whole chunk has landed.
typedef NativeProgressHandler = void Function(String sessionId, String fileId, int liveBytes);

/// The native (Kotlin) side of the chunked upload data path.
///
/// File bytes go from the socket to the disk inside native code; Dart only
/// authorizes uploads and is told when each chunk has landed. An interface so
/// tests can stand in for Android.
abstract class NativeDataBridge {
  /// Set by the receiver; invoked after every chunk.
  NativeChunkHandler? onChunk;

  /// Set by the receiver; invoked while chunks arrive.
  NativeProgressHandler? onProgress;

  /// Starts the native server and returns its port.
  Future<int> start(DeviceIdentity identity);

  Future<void> register({
    required String sessionId,
    required String fileId,
    required String token,
    required String path,
    required int size,
    required String senderAddress,
  });

  Future<void> unregisterSession(String sessionId);

  Future<void> stop();
}

/// The real bridge, backed by the Pigeon-generated Android API.
class PigeonNativeDataBridge extends NativeDataBridge implements NativeDataCallbacks {
  PigeonNativeDataBridge() : _api = NativeDataApi() {
    NativeDataCallbacks.setUp(this);
  }

  final NativeDataApi _api;

  @override
  Future<int> start(DeviceIdentity identity) =>
      _api.startDataServer(identity.certificatePem, identity.privateKeyPem);

  @override
  Future<void> register({
    required String sessionId,
    required String fileId,
    required String token,
    required String path,
    required int size,
    required String senderAddress,
  }) => _api.registerUpload(sessionId, fileId, token, path, size, senderAddress);

  @override
  Future<void> unregisterSession(String sessionId) =>
      _api.unregisterSession(sessionId);

  @override
  Future<void> stop() => _api.stopDataServer();

  @override
  Future<int> onNativeChunk(
    String sessionId,
    String fileId,
    int offset,
    int length,
  ) async {
    final handler = onChunk;
    if (handler == null) return 500;
    return handler(sessionId, fileId, offset, length);
  }

  @override
  void onNativeProgress(String sessionId, String fileId, int liveBytes) =>
      onProgress?.call(sessionId, fileId, liveBytes);
}
