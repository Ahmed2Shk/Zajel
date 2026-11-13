import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/transfer/protocol_models.dart';
import 'package:zajel/core/transfer/range_set.dart';
import 'package:zajel/core/transfer/send_client.dart';

import '../support/transfer_harness.dart';

const _mib = 1024 * 1024;

/// What happens around the end of a transfer: answers that get lost, resumes
/// of files that are already there, and a cancel in the middle of a file.
void main() {
  TransferHarness? harness;
  late Directory source;

  TransferHarness h() => harness!;

  setUp(() async {
    source = await createTestDir('zajel_done_src_');
  });

  tearDown(() async {
    await harness?.dispose();
    harness = null;
    await source.delete(recursive: true);
  });

  Future<SendFile> sourceFile(String name, int size, {int seed = 1}) async =>
      SendFile.fromPath((await writeTestFile(source, name, size, seed: seed)).path, id: name);

  List<String> saved() =>
      h().downloads.listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toList()..sort();

  /// The same session as [session], as a sender that remembers nothing.
  SendSession forgetful(SendSession session) => SendSession(
    sessionId: session.sessionId,
    tokens: session.tokens,
    target: session.target,
    chunked: session.chunked,
    dataPort: session.dataPort,
    tarToken: session.tarToken,
  );

  group('piece size', () {
    const options = UploadOptions();

    test('a medium file is cut so every connection gets a piece', () {
      expect(options.pieceSizeFor(3 * _mib), _mib);
      expect(options.pieceSizeFor(20 * _mib), 5 * _mib);
    });

    test('a big file uses the full chunk size', () {
      expect(options.pieceSizeFor(100 * _mib), 8 * _mib);
      expect(options.pieceSizeFor(4 * 1024 * _mib), 8 * _mib);
    });

    test('files from 1 MB are sent in pieces, smaller ones whole', () {
      expect(options.chunkedFrom, _mib);
      expect(const UploadOptions(chunkSize: 256 * 1024).chunkedFrom, 256 * 1024);
      expect(const UploadOptions(chunkSize: 256 * 1024).pieceSizeFor(_mib), 256 * 1024);
    });
  });

  test('RangeSet.contains', () {
    final set = RangeSet()
      ..add(0, 100)
      ..add(200, 300);
    expect(set.contains(0, 100), isTrue);
    expect(set.contains(10, 90), isTrue);
    expect(set.contains(90, 210), isFalse);
    expect(set.contains(300, 301), isFalse);
  });

  test('a medium file travels in parallel pieces and arrives intact', () async {
    harness = await TransferHarness.start();
    final file = await sourceFile('photo.bin', 3 * _mib);
    final session = await h().prepare([file]);

    await h().sender.upload(session: session, files: [file]);

    expect(h().server.plainUploadRequests, 3, reason: 'three 1 MB pieces, not one stream');
    final received = File('${h().downloads.path}/photo.bin');
    expect(await sha256OfFile(received), await sha256OfFile(file.file));
  });

  test('a resumed upload does not send delivered files again', () async {
    harness = await TransferHarness.start();
    final a = await sourceFile('a.bin', 300 * 1024);
    final b = await sourceFile('b.bin', 2 * _mib, seed: 2);
    final session = await h().prepare([a, b]);

    await h().sender.upload(session: session, files: [a, b]);
    final requests = h().server.plainUploadRequests;
    final progress = <String, int>{};
    await h().sender.upload(
      session: session,
      files: [a, b],
      onProgress: (id, bytes) => progress[id] = bytes,
    );

    expect(h().server.plainUploadRequests, requests, reason: 'nothing was sent twice');
    expect(progress, {'a.bin': a.size, 'b.bin': b.size});
    expect(saved(), ['a.bin', 'b.bin']);
  });

  test('a sender that missed the last answer hears "done", not "declined"', () async {
    harness = await TransferHarness.start();
    final a = await sourceFile('a.bin', 300 * 1024); // whole-file upload
    final b = await sourceFile('b.bin', 3 * _mib, seed: 2); // pieces
    final session = await h().prepare([a, b]);
    await h().sender.upload(session: session, files: [a, b]);

    // The receiver has closed the session. A sender that never heard the last
    // answers tries everything again.
    await h().sender.upload(session: forgetful(session), files: [a, b]);

    expect(saved(), ['a.bin', 'b.bin'], reason: 'no second copies');
    expect(await sha256OfFile(File('${h().downloads.path}/b.bin')), await sha256OfFile(b.file));
  });

  test('a file that was arriving when the receiver cancelled is not saved', () async {
    harness = await TransferHarness.start();
    final a = await sourceFile('a.bin', 300 * 1024);
    final b = await sourceFile('b.bin', 1024);
    final session = await h().prepare([a, b]);
    final bytes = await a.file.readAsBytes();

    final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
    addTearDown(() => client.close(force: true));
    final request = await client.postUrl(Uri.parse(
      'https://127.0.0.1:${h().server.port}$localSendApiPrefix/upload'
      '?sessionId=${session.sessionId}&fileId=a.bin&token=${session.tokens['a.bin']}',
    ));
    request.headers.contentLength = a.size;
    request.add(bytes.sublist(0, 1000));
    await request.flush();

    await h().server.cancelSession();
    request.add(bytes.sublist(1000));
    final response = await request.close();
    await response.drain<void>();

    expect(response.statusCode, isNot(200));
    expect(saved(), isEmpty);
  });
}
