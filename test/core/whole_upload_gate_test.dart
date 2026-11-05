import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/transfer/protocol_models.dart';
import 'package:zajel/core/transfer/send_client.dart';

import '../support/transfer_harness.dart';

/// Whole-file uploads (plain `/upload`) of one file run one at a time, so a
/// resume never writes into a part file the previous attempt still holds.
void main() {
  TransferHarness? harness;
  late Directory source;
  late HttpClient client;

  TransferHarness h() => harness!;

  setUp(() async {
    source = await createTestDir('zajel_gate_src_');
    client = HttpClient()..badCertificateCallback = (_, _, _) => true;
  });

  tearDown(() async {
    client.close(force: true);
    await harness?.dispose();
    harness = null;
    await source.delete(recursive: true);
  });

  Future<SendFile> sourceFile(String name, int size) async =>
      SendFile.fromPath((await writeTestFile(source, name, size)).path, id: name);

  Future<HttpClientRequest> openUpload(SendSession session, String fileId, int size) async {
    final request = await client.postUrl(Uri.parse(
      'https://127.0.0.1:${h().server.port}$localSendApiPrefix/upload'
      '?sessionId=${session.sessionId}&fileId=$fileId&token=${session.tokens[fileId]}',
    ));
    request.headers.contentLength = size;
    return request;
  }

  List<String> savedNames() => h().downloads
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => !n.endsWith('.zajel-part'))
      .toList();

  List<String> leftoverParts() => h().downloads
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.zajel-part'))
      .toList();

  test('a resume that waited for a finished attempt gets OK and leaves one copy', () async {
    harness = await TransferHarness.start();
    final a = await sourceFile('a.bin', 64 * 1024);
    final b = await sourceFile('b.bin', 1024); // keeps the session open
    final session = await h().prepare([a, b]);
    final bytes = await a.file.readAsBytes();

    // The first attempt is still sending when the resume arrives.
    final first = await openUpload(session, 'a.bin', a.size);
    first.add(bytes.sublist(0, 1000));
    await first.flush();
    final second = await openUpload(session, 'a.bin', a.size);
    second.add(bytes);
    final secondResponse = second.close();

    first.add(bytes.sublist(1000));
    final firstResponse = await first.close();
    await firstResponse.drain<void>();
    expect(firstResponse.statusCode, 200);

    final resumed = await secondResponse;
    await resumed.drain<void>();
    expect(resumed.statusCode, 200);
    expect(savedNames(), ['a.bin'], reason: 'no "a (1).bin"');
  });

  test('an upload that stops sending frees the file for the next attempt', () async {
    harness = await TransferHarness.start(stallTimeout: const Duration(milliseconds: 300));
    final a = await sourceFile('a.bin', 64 * 1024);
    final b = await sourceFile('b.bin', 1024);
    final session = await h().prepare([a, b]);
    final bytes = await a.file.readAsBytes();

    // Half the file, then silence (a sender whose network vanished).
    final stalled = await openUpload(session, 'a.bin', a.size);
    stalled.add(bytes.sublist(0, 1000));
    await stalled.flush();

    final retry = await openUpload(session, 'a.bin', a.size);
    retry.add(bytes);
    final response = await retry.close().timeout(const Duration(seconds: 5));
    await response.drain<void>();
    expect(response.statusCode, 200);
    expect(await File('${h().downloads.path}/a.bin').length(), a.size);
    // End the dead attempt before the folder is removed.
    client.close(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(leftoverParts(), isEmpty, reason: 'the dead attempt cleans up its own part file');
  });

  test('another file of the session does not wait for a slow one', () async {
    harness = await TransferHarness.start();
    final a = await sourceFile('a.bin', 64 * 1024);
    final b = await sourceFile('b.bin', 1024);
    final session = await h().prepare([a, b]);

    final slow = await openUpload(session, 'a.bin', a.size);
    slow.add((await a.file.readAsBytes()).sublist(0, 1000));
    await slow.flush();

    final other = await openUpload(session, 'b.bin', b.size);
    other.add(await b.file.readAsBytes());
    final response = await other.close().timeout(const Duration(seconds: 5));
    await response.drain<void>();
    expect(response.statusCode, 200);

    slow.add((await a.file.readAsBytes()).sublist(1000));
    await (await slow.close()).drain<void>();
  });
}
