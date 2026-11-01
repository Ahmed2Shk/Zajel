import 'dart:io';

import 'package:zajel/core/platform/native_data_bridge.dart';
import 'package:zajel/core/security/device_identity.dart';
import 'package:zajel/core/transfer/protocol_models.dart';

class _Registration {
  _Registration(this.token, this.path, this.size, this.senderAddress);

  final String token;
  final String path;
  final int size;
  final String senderAddress;
}

/// Stands in for the Kotlin data server in tests. It speaks the same protocol
/// (chunk in, write at offset, ask Dart, answer with Dart's status) so the
/// Dart side of the native path can be tested without a phone. It does not
/// test the Kotlin code itself.
class FakeNativeDataBridge extends NativeDataBridge {
  FakeNativeDataBridge({this.failToStart = false});

  final bool failToStart;
  HttpServer? _server;
  final _registered = <String, _Registration>{};

  int startCalls = 0;
  int chunksServed = 0;

  List<String> get registeredKeys => _registered.keys.toList();
  int? get port => _server?.port;

  @override
  Future<int> start(DeviceIdentity identity) async {
    startCalls++;
    if (failToStart) throw StateError('native server unavailable');
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      identity.toSecurityContext(),
    );
    _server = server;
    server.listen(_handle);
    return server.port;
  }

  /// Makes the port unreachable while the receiver still advertises it, like a
  /// firewall dropping the data port.
  Future<void> breakServer() async {
    await _server?.close(force: true);
  }

  @override
  Future<void> register({
    required String sessionId,
    required String fileId,
    required String token,
    required String path,
    required int size,
    required String senderAddress,
  }) async {
    _registered['$sessionId|$fileId'] = _Registration(
      token,
      path,
      size,
      senderAddress,
    );
  }

  @override
  Future<void> unregisterSession(String sessionId) async {
    _registered.removeWhere((key, _) => key.startsWith('$sessionId|'));
  }

  @override
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _registered.clear();
  }

  Future<void> _handle(HttpRequest request) async {
    Future<void> answer(int status) async {
      request.response.statusCode = status;
      await request.response.close();
    }

    final query = request.uri.queryParameters;
    if (request.method != 'POST' ||
        request.uri.path != '$localSendApiPrefix/upload') {
      return answer(404);
    }
    final sessionId = query['sessionId'];
    final fileId = query['fileId'];
    final offset = int.tryParse(query['offset'] ?? '');
    final reg = _registered['$sessionId|$fileId'];
    if (reg == null ||
        reg.token != query['token'] ||
        reg.senderAddress != request.connectionInfo!.remoteAddress.address) {
      return answer(403);
    }
    final length = request.contentLength;
    if (offset == null || offset < 0 || length <= 0 || offset + length > reg.size) {
      return answer(400);
    }

    final handle = await File(reg.path).open(mode: FileMode.append);
    try {
      await handle.setPosition(offset);
      var written = 0;
      await for (final data in request) {
        await handle.writeFrom(data);
        written += data.length;
        // The Kotlin server reports bytes in flight while a chunk arrives.
        onProgress?.call(sessionId!, fileId!, written);
      }
      if (written != length) return answer(400);
    } finally {
      await handle.close();
    }

    chunksServed++;
    final status = await onChunk!(sessionId!, fileId!, offset, length);
    await answer(status);
  }
}
