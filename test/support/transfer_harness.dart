import 'dart:io';
import 'dart:math';

import 'package:zajel/core/platform/native_data_bridge.dart';
import 'package:zajel/core/security/device_identity.dart';
import 'package:zajel/core/transfer/protocol_models.dart';
import 'package:zajel/core/transfer/receive_server.dart';
import 'package:zajel/core/transfer/send_client.dart';

/// Generating an RSA key is slow, so identities are shared across tests.
final receiverIdentity = DeviceIdentity.generate(commonName: 'receiver');
final senderIdentity = DeviceIdentity.generate(commonName: 'sender');

/// A receiver and a sender talking over loopback with real TLS.
class TransferHarness {
  TransferHarness._(this.server, this.downloads, this.sender, this.receiverInfo);

  final ReceiveServer server;
  final Directory downloads;
  final SendClient sender;
  final DeviceInfo receiverInfo;

  static Future<TransferHarness> start({
    IncomingDecision? onIncoming,
    String? pin,
    bool enableChunking = true,
    Duration sessionIdleTimeout = const Duration(minutes: 2),
    NativeDataBridge? nativeData,
  }) async {
    final downloads = await createTestDir('zajel_downloads_');
    final receiverInfo = DeviceInfo(
      alias: 'Receiver',
      fingerprint: receiverIdentity.fingerprint,
    );
    final server = ReceiveServer(
      identity: receiverIdentity,
      device: receiverInfo,
      downloadDirectory: downloads,
      onIncoming: onIncoming ?? (t) async => t.files.keys.toSet(),
      pin: pin,
      enableChunking: enableChunking,
      sessionIdleTimeout: sessionIdleTimeout,
      nativeData: nativeData,
    );
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    final sender = SendClient(
      self: DeviceInfo(alias: 'Sender', fingerprint: senderIdentity.fingerprint),
    );
    return TransferHarness._(server, downloads, sender, receiverInfo);
  }

  Future<SendSession> prepare(List<SendFile> files, {String? pin, String? fingerprint}) =>
      sender.prepareUpload(
        address: InternetAddress.loopbackIPv4,
        port: server.port,
        files: files,
        expectedFingerprint: fingerprint ?? receiverIdentity.fingerprint,
        pin: pin,
      );

  Future<void> dispose() async {
    await server.stop();
    await downloads.delete(recursive: true);
  }
}

/// Writes a file of [size] bytes without holding it in memory.
Future<File> writeTestFile(Directory dir, String name, int size, {int seed = 1}) async {
  final file = File('${dir.path}/$name');
  final random = Random(seed);
  final block = List<int>.generate(1 << 20, (_) => random.nextInt(256));
  final sink = file.openWrite();
  var written = 0;
  var counter = 0;
  while (written < size) {
    final n = min(block.length, size - written);
    // Vary each block so a repeated-block bug cannot go unnoticed.
    block[0] = counter & 0xff;
    block[1] = (counter >> 8) & 0xff;
    block[2] = (counter >> 16) & 0xff;
    sink.add(n == block.length ? block : block.sublist(0, n));
    written += n;
    counter++;
  }
  await sink.close();
  return file;
}

/// Temp folder for tests. Set ZAJEL_TEST_TMP to put big test files on another
/// drive (the 1 GB test needs about 2 GB).
Future<Directory> createTestDir(String prefix) async {
  final root = Platform.environment['ZAJEL_TEST_TMP'];
  if (root == null) return Directory.systemTemp.createTemp(prefix);
  await Directory(root).create(recursive: true);
  return Directory(root).createTemp(prefix);
}
