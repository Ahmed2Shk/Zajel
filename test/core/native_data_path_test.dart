import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/transfer/protocol_models.dart';
import 'package:zajel/core/transfer/receive_server.dart';
import 'package:zajel/core/transfer/send_client.dart';

import '../support/fake_native_data_bridge.dart';
import '../support/transfer_harness.dart';

const _mib = 1024 * 1024;

/// The Dart side of the Android data path, with a fake standing in for the
/// Kotlin server. See FakeNativeDataBridge.
void main() {
  TransferHarness? harness;
  late Directory source;
  late FakeNativeDataBridge native;

  TransferHarness h() => harness!;

  setUp(() async {
    source = await createTestDir('zajel_native_src_');
    native = FakeNativeDataBridge();
  });

  tearDown(() async {
    await harness?.dispose();
    harness = null;
    await source.delete(recursive: true);
  });

  Future<SendFile> sourceFile(String name, int size, {int seed = 1, String? asName}) async =>
      SendFile.fromPath(
        (await writeTestFile(source, name, size, seed: seed)).path,
        id: name,
        name: asName,
      );

  Future<void> expectSameContent(SendFile sent, {String? asName}) async {
    final received = File('${h().downloads.path}/${asName ?? sent.name}');
    expect(await received.length(), sent.size);
    expect(await sha256OfFile(received), await sha256OfFile(sent.file));
  }

  List<String> leftovers() => h().downloads
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.zajel-part'))
      .map((f) => f.path)
      .toList();

  const small = UploadOptions(chunkSize: 1 * _mib, parallel: 4);

  test('the receiver advertises the data port to a Zajel sender', () async {
    harness = await TransferHarness.start(nativeData: native);
    final file = await sourceFile('a.bin', 2 * _mib);

    final session = await h().prepare([file]);
    expect(session.chunked, isTrue);
    expect(session.dataPort, native.port);
  });

  test('progress moves while a chunk is still arriving, not only when it lands', () async {
    harness = await TransferHarness.start(nativeData: native);
    final file = await sourceFile('a.bin', 4 * _mib);
    final seen = <int>[];
    final subscription = h().server.events.listen((event) {
      if (event is FileProgress) seen.add(event.received);
    });

    final session = await h().prepare([file]);
    await h().sender.upload(
      session: session,
      files: [file],
      options: const UploadOptions(chunkSize: 4 * _mib, parallel: 1),
    );
    await subscription.cancel();

    // One 4 MB chunk: without live progress the only value would be 4 MB.
    expect(seen.where((n) => n > 0 && n < 4 * _mib), isNotEmpty);
    expect(seen.last, 4 * _mib);
    expect(seen, orderedEquals([...seen]..sort()), reason: 'the bar never goes back');
    await expectSameContent(file);
  });

  test('a sender that does not offer extensions is not sent to the data port', () async {
    harness = await TransferHarness.start(nativeData: native);
    h().sender.offerExtensions = false;
    final file = await sourceFile('a.bin', 2 * _mib);

    final session = await h().prepare([file]);
    expect(session.chunked, isFalse);
    expect(session.dataPort, isNull);
  });

  test('a stock sender gets no port header', () async {
    harness = await TransferHarness.start(nativeData: native);
    final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
    final request = await client.postUrl(Uri.parse(
      'https://127.0.0.1:${h().server.port}$localSendApiPrefix/prepare-upload',
    ));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'info': {'alias': 'stock', 'fingerprint': 'x'},
      'files': {
        'f': {'id': 'f', 'fileName': 'a.bin', 'size': 5, 'fileType': 'a/b'},
      },
    }));
    final response = await request.close();
    await response.drain<void>();
    client.close();
    expect(response.statusCode, 200);
    expect(response.headers.value(zajelDataPortHeader), isNull);
    expect(response.headers.value(zajelExtensionHeader), isNull);
  });

  test('big files travel through the native server, intact', () async {
    harness = await TransferHarness.start(nativeData: native);
    final file = await sourceFile('big.bin', 12 * _mib + 321);
    final events = <ReceiveEvent>[];
    h().server.events.listen(events.add);

    final session = await h().prepare([file]);
    await h().sender.upload(session: session, files: [file], options: small);
    await Future<void>.delayed(Duration.zero);

    await expectSameContent(file);
    expect(native.chunksServed, 13, reason: 'all 13 chunks use the data port');
    expect(leftovers(), isEmpty);
    expect(events.whereType<FileReceived>(), hasLength(1));
    expect(events.last, isA<SessionEnded>());
  });

  test('small files still use the main port, with reserved names kept', () async {
    harness = await TransferHarness.start(nativeData: native);
    final tiny = await sourceFile('tiny.bin', 1000, seed: 2);
    final big = await sourceFile('big.bin', 3 * _mib, seed: 3);
    final session = await h().prepare([tiny, big]);
    await h().sender.upload(session: session, files: [tiny, big], options: small);

    await expectSameContent(tiny);
    await expectSameContent(big);
    expect(native.chunksServed, 3);
    expect(leftovers(), isEmpty);
  });

  test('files with the same name get distinct names', () async {
    harness = await TransferHarness.start(nativeData: native);
    final first = await sourceFile('one.bin', 2 * _mib, seed: 4, asName: 'same.bin');
    final second = await sourceFile('two.bin', 2 * _mib, seed: 5, asName: 'same.bin');
    final session = await h().prepare([first, second]);
    await h().sender.upload(session: session, files: [first, second], options: small);

    final a = File('${h().downloads.path}/same.bin');
    final b = File('${h().downloads.path}/same (1).bin');
    expect(a.existsSync() && b.existsSync(), isTrue);
    final hashes = {await sha256OfFile(a), await sha256OfFile(b)};
    expect(hashes, {await sha256OfFile(first.file), await sha256OfFile(second.file)});
  });

  test('a finished session is unregistered from the native server', () async {
    harness = await TransferHarness.start(nativeData: native);
    final file = await sourceFile('a.bin', 2 * _mib);
    final session = await h().prepare([file]);
    expect(native.registeredKeys, isNotEmpty);
    await h().sender.upload(session: session, files: [file], options: small);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(native.registeredKeys, isEmpty);
  });

  test('cancel unregisters and removes partial files', () async {
    harness = await TransferHarness.start(nativeData: native);
    final file = await sourceFile('a.bin', 4 * _mib);
    final session = await h().prepare([file]);
    expect(leftovers(), hasLength(1), reason: 'part file is reserved up front');
    await h().sender.cancel(session);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(native.registeredKeys, isEmpty);
    expect(leftovers(), isEmpty);
  });

  test('an unreachable data port falls back to the main port', () async {
    harness = await TransferHarness.start(nativeData: native);
    final file = await sourceFile('big.bin', 6 * _mib + 5);
    final session = await h().prepare([file]);
    expect(session.dataPort, isNotNull);
    await native.breakServer();

    await h().sender.upload(session: session, files: [file], options: small);
    await expectSameContent(file);
    expect(native.chunksServed, 0);
    expect(leftovers(), isEmpty);
  });

  test('a native server that fails to start leaves chunks on the Dart route', () async {
    final broken = FakeNativeDataBridge(failToStart: true);
    harness = await TransferHarness.start(nativeData: broken);
    final file = await sourceFile('big.bin', 4 * _mib);
    final session = await h().prepare([file]);
    expect(session.chunked, isTrue);
    expect(session.dataPort, isNull);
    await h().sender.upload(session: session, files: [file], options: small);
    await expectSameContent(file);
  });

  test('a receiver without chunking never starts the native server', () async {
    harness = await TransferHarness.start(nativeData: native, enableChunking: false);
    expect(native.startCalls, 0);
  });

  test('the native route refuses a Dart-route chunk once it has written', () async {
    harness = await TransferHarness.start(nativeData: native);
    final file = await sourceFile('big.bin', 4 * _mib);
    final session = await h().prepare([file]);

    // One chunk lands through the native server...
    final chunk = await file.file.openRead(0, _mib).expand((b) => b).toList();
    final nativeClient = HttpClient()..badCertificateCallback = (_, _, _) => true;
    final nativePost = await nativeClient.postUrl(Uri.parse(
      'https://127.0.0.1:${native.port}$localSendApiPrefix/upload'
      '?sessionId=${session.sessionId}&fileId=big.bin&token=${session.tokens['big.bin']}&offset=0',
    ));
    nativePost.headers.contentLength = _mib;
    nativePost.add(chunk);
    final nativeResponse = await nativePost.close();
    await nativeResponse.drain<void>();
    expect(nativeResponse.statusCode, 200);

    // ...so a chunk through Dart would truncate it, and is refused instead.
    final dartPost = await nativeClient.postUrl(Uri.parse(
      'https://127.0.0.1:${h().server.port}$localSendApiPrefix/upload'
      '?sessionId=${session.sessionId}&fileId=big.bin&token=${session.tokens['big.bin']}&offset=$_mib',
    ));
    dartPost.headers.contentLength = _mib;
    dartPost.add(List.filled(_mib, 9));
    final dartResponse = await dartPost.close();
    await dartResponse.drain<void>();
    nativeClient.close();
    expect(dartResponse.statusCode, 409);
  });
}
