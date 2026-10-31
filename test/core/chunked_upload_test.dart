import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/transfer/protocol_models.dart';
import 'package:zajel/core/transfer/receive_server.dart';
import 'package:zajel/core/transfer/send_client.dart';

import '../support/transfer_harness.dart';

const _mib = 1024 * 1024;

void main() {
  TransferHarness? harness;
  late Directory source;

  TransferHarness h() => harness!;

  setUp(() async {
    source = await createTestDir('zajel_chunk_src_');
  });

  tearDown(() async {
    await harness?.dispose();
    harness = null;
    await source.delete(recursive: true);
  });

  Future<SendFile> sourceFile(String name, int size, {int seed = 1}) async =>
      SendFile.fromPath(
        (await writeTestFile(source, name, size, seed: seed)).path,
        id: name,
      );

  Future<void> expectSameContent(SendFile sent) async {
    final received = File('${h().downloads.path}/${sent.name}');
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

  group('negotiation', () {
    test('a Zajel receiver turns on chunked uploads', () async {
      harness = await TransferHarness.start();
      final session = await h().prepare([await sourceFile('a.bin', 100)]);
      expect(session.chunked, isTrue);
    });

    test('a receiver without the extension looks like stock LocalSend', () async {
      harness = await TransferHarness.start(enableChunking: false);
      final file = await sourceFile('a.bin', 5 * _mib + 3);
      final session = await h().prepare([file]);
      expect(session.chunked, isFalse);

      await h().sender.upload(session: session, files: [file], options: small);
      await expectSameContent(file);
    });

    test('a sender that does not offer it gets plain uploads', () async {
      harness = await TransferHarness.start();
      h().sender.offerExtensions = false;
      final file = await sourceFile('a.bin', 5 * _mib + 3);
      final session = await h().prepare([file]);
      expect(session.chunked, isFalse);

      await h().sender.upload(session: session, files: [file], options: small);
      await expectSameContent(file);
    });

    test('a stock sender cannot use chunk parameters on a plain receiver', () async {
      harness = await TransferHarness.start(enableChunking: false);
      final file = await sourceFile('a.bin', 4096);
      final session = await h().prepare([file]);
      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      final request = await client.postUrl(Uri.parse(
        'https://127.0.0.1:${h().server.port}$localSendApiPrefix/upload'
        '?sessionId=${session.sessionId}&fileId=a.bin&token=${session.tokens['a.bin']}&offset=0',
      ));
      request.add(List.filled(4096, 7));
      final response = await request.close();
      await response.drain<void>();
      client.close();
      // The plain route treats it as a whole-file upload; offset is ignored.
      expect(response.statusCode, 200);
    });
  });

  group('parallel chunked transfer', () {
    test('delivers an uneven-sized file intact over 4 connections', () async {
      harness = await TransferHarness.start();
      final file = await sourceFile('big.bin', 23 * _mib + 12345);
      final session = await h().prepare([file]);
      await h().sender.upload(session: session, files: [file], options: small);

      await expectSameContent(file);
      expect(leftovers(), isEmpty);
    });

    test('a file of exactly one chunk and one just above it', () async {
      harness = await TransferHarness.start();
      final exact = await sourceFile('exact.bin', 1 * _mib, seed: 3);
      final above = await sourceFile('above.bin', 1 * _mib + 1, seed: 4);
      final session = await h().prepare([exact, above]);
      await h().sender.upload(session: session, files: [exact, above], options: small);

      await expectSameContent(exact);
      await expectSameContent(above);
    });

    test('files below the chunk size use the plain upload path', () async {
      harness = await TransferHarness.start();
      final tiny = await sourceFile('tiny.bin', 1000);
      final session = await h().prepare([tiny]);
      await h().sender.upload(session: session, files: [tiny], options: small);
      await expectSameContent(tiny);
    });

    test('progress reaches the full size and ends the session', () async {
      harness = await TransferHarness.start();
      final file = await sourceFile('big.bin', 6 * _mib);
      final events = <ReceiveEvent>[];
      h().server.events.listen(events.add);

      final session = await h().prepare([file]);
      var lastSent = 0;
      await h().sender.upload(
        session: session,
        files: [file],
        options: small,
        onProgress: (_, sent) => lastSent = sent,
      );
      await Future<void>.delayed(Duration.zero);

      expect(lastSent, file.size);
      final progress = events.whereType<FileProgress>().map((e) => e.received);
      expect(progress.last, file.size);
      expect(progress.every((n) => n <= file.size), isTrue);
      expect(events.last, isA<SessionEnded>());
    });

    test('a verified sha256 is checked once all chunks are in', () async {
      harness = await TransferHarness.start();
      final file = await sourceFile('a.bin', 3 * _mib);
      final digest = await sha256OfFile(file.file);

      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      Future<Map<String, dynamic>> prepare(String sha) async {
        final request = await client.postUrl(Uri.parse(
          'https://127.0.0.1:${h().server.port}$localSendApiPrefix/prepare-upload',
        ));
        request.headers
          ..contentType = ContentType.json
          ..set(zajelExtensionHeader, zajelExtensionVersion);
        request.write(jsonEncode({
          'info': {'alias': 'x', 'fingerprint': 'x'},
          'files': {
            'f': {
              'id': 'f',
              'fileName': 'a.bin',
              'size': file.size,
              'fileType': 'a/b',
              'sha256': sha,
            },
          },
        }));
        final response = await request.close();
        return jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;
      }

      Future<int> chunk(Map<String, dynamic> session, int start, int end) async {
        final request = await client.postUrl(Uri.parse(
          'https://127.0.0.1:${h().server.port}$localSendApiPrefix/upload'
          '?sessionId=${session['sessionId']}&fileId=f&token=${(session['files'] as Map)['f']}&offset=$start',
        ));
        request.headers.contentLength = end - start;
        request.add(await file.file.openRead(start, end).expand((b) => b).toList());
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      }

      // Wrong checksum: the last chunk is refused and nothing is kept.
      final bad = await prepare('0' * 64);
      expect(await chunk(bad, 0, _mib), 200);
      expect(await chunk(bad, _mib, file.size), 422);
      expect(h().downloads.listSync().where((e) => e.path.endsWith('a.bin')), isEmpty);
      expect(leftovers(), isEmpty);
      client.close();
      expect(digest, isNotEmpty);
    });
  });

  group('resume', () {
    test('a second upload on the same session sends only what is missing', () async {
      harness = await TransferHarness.start();
      final file = await sourceFile('big.bin', 12 * _mib);
      final session = await h().prepare([file]);

      // First attempt is stopped part-way through.
      var cancelAfter = 4 * _mib;
      var sentFirst = 0;
      await h().sender.upload(
        session: session,
        files: [file],
        options: const UploadOptions(chunkSize: 1 * _mib, parallel: 2),
        onProgress: (_, sent) => sentFirst = sent,
        isCancelled: () => sentFirst >= cancelAfter,
      );
      expect(File('${h().downloads.path}/big.bin').existsSync(), isFalse,
          reason: 'incomplete file must not appear under its final name');

      // Second attempt: the first progress report is what the receiver held.
      cancelAfter = 1 << 40;
      final reports = <int>[];
      await h().sender.upload(
        session: session,
        files: [file],
        options: small,
        onProgress: (_, sent) => reports.add(sent),
      );

      expect(reports.first, greaterThanOrEqualTo(2 * _mib),
          reason: 'resume should skip chunks the receiver already has');
      expect(reports.last, file.size);
      await expectSameContent(file);
    });

    test('progress endpoint lists what has arrived', () async {
      harness = await TransferHarness.start();
      final file = await sourceFile('big.bin', 4 * _mib);
      final session = await h().prepare([file]);

      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      final chunkUri =
          'https://127.0.0.1:${h().server.port}$localSendApiPrefix/upload'
          '?sessionId=${session.sessionId}&fileId=big.bin&token=${session.tokens['big.bin']}';
      final post = await client.postUrl(Uri.parse('$chunkUri&offset=$_mib'));
      post.headers.contentLength = _mib;
      post.add(List.filled(_mib, 1));
      await (await post.close()).drain<void>();

      final get = await client.getUrl(Uri.parse(
        'https://127.0.0.1:${h().server.port}$zajelProgressRoute'
        '?sessionId=${session.sessionId}&fileId=big.bin&token=${session.tokens['big.bin']}',
      ));
      final body = jsonDecode(await utf8.decodeStream(await get.close())) as Map<String, dynamic>;
      client.close();

      expect(body['ranges'], [[_mib, 2 * _mib]]);
      expect(body['size'], 4 * _mib);
    });

    test('a retried chunk is harmless', () async {
      harness = await TransferHarness.start();
      final file = await sourceFile('big.bin', 3 * _mib);
      final session = await h().prepare([file]);
      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      final bytes = await file.file.openRead(0, _mib).expand((b) => b).toList();
      for (var i = 0; i < 2; i++) {
        final post = await client.postUrl(Uri.parse(
          'https://127.0.0.1:${h().server.port}$localSendApiPrefix/upload'
          '?sessionId=${session.sessionId}&fileId=big.bin&token=${session.tokens['big.bin']}&offset=0',
        ));
        post.headers.contentLength = _mib;
        post.add(bytes);
        final response = await post.close();
        await response.drain<void>();
        expect(response.statusCode, 200);
      }
      client.close();

      await h().sender.upload(session: session, files: [file], options: small);
      await expectSameContent(file);
    });
  });

  group('chunk validation', () {
    Future<int> rawChunk(SendSession session, String query, List<int> body) async {
      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      final request = await client.postUrl(Uri.parse(
        'https://127.0.0.1:${h().server.port}$localSendApiPrefix/upload'
        '?sessionId=${session.sessionId}&fileId=a.bin&token=${session.tokens['a.bin']}$query',
      ));
      request.headers.contentLength = body.length;
      request.add(body);
      final response = await request.close();
      await response.drain<void>();
      client.close();
      return response.statusCode;
    }

    test('rejects ranges outside the file and a non-numeric offset', () async {
      harness = await TransferHarness.start();
      final file = await sourceFile('a.bin', 2 * _mib);
      final session = await h().prepare([file]);

      expect(await rawChunk(session, '&offset=-1', [1, 2, 3]), 400);
      expect(await rawChunk(session, '&offset=abc', [1, 2, 3]), 400);
      expect(await rawChunk(session, '&offset=${2 * _mib - 1}', [1, 2, 3]), 400);
      expect(await rawChunk(session, '&offset=${2 * _mib + 10}', [1, 2, 3]), 400);
      expect(await rawChunk(session, '&offset=0', []), 400);
    });

    test('rejects a chunk with the wrong token', () async {
      harness = await TransferHarness.start();
      final file = await sourceFile('a.bin', 2 * _mib);
      final session = await h().prepare([file]);
      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      final request = await client.postUrl(Uri.parse(
        'https://127.0.0.1:${h().server.port}$localSendApiPrefix/upload'
        '?sessionId=${session.sessionId}&fileId=a.bin&token=wrong&offset=0',
      ));
      request.headers.contentLength = 3;
      request.add([1, 2, 3]);
      final response = await request.close();
      await response.drain<void>();
      client.close();
      expect(response.statusCode, 403);
    });

    test('cancel removes the partial file', () async {
      harness = await TransferHarness.start();
      final file = await sourceFile('a.bin', 4 * _mib);
      final session = await h().prepare([file]);
      expect(await rawChunk(session, '&offset=0', List.filled(_mib, 1)), 200);
      expect(leftovers(), hasLength(1));

      await h().sender.cancel(session);
      expect(leftovers(), isEmpty);
    });
  });

  group('idle sessions', () {
    test('a silent sender is dropped and its partial file removed', () async {
      harness = await TransferHarness.start(
        sessionIdleTimeout: const Duration(milliseconds: 300),
      );
      final file = await sourceFile('a.bin', 4 * _mib);
      final events = <ReceiveEvent>[];
      h().server.events.listen(events.add);

      final session = await h().prepare([file]);
      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      final request = await client.postUrl(Uri.parse(
        'https://127.0.0.1:${h().server.port}$localSendApiPrefix/upload'
        '?sessionId=${session.sessionId}&fileId=a.bin&token=${session.tokens['a.bin']}&offset=0',
      ));
      request.headers.contentLength = _mib;
      request.add(List.filled(_mib, 1));
      await (await request.close()).drain<void>();
      client.close();
      expect(leftovers(), hasLength(1));

      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(leftovers(), isEmpty);
      expect(events.last, isA<SessionEnded>());
      expect((events.last as SessionEnded).cancelled, isTrue);
      // The receiver is free again.
      expect((await h().prepare([file])).tokens, isNotEmpty);
    });

    test('an active transfer is not cut off by the timeout', () async {
      harness = await TransferHarness.start(
        sessionIdleTimeout: const Duration(seconds: 2),
      );
      final file = await sourceFile('a.bin', 16 * _mib);
      final session = await h().prepare([file]);
      await h().sender.upload(session: session, files: [file], options: small);
      await expectSameContent(file);
    });
  });

  group('benchmark', () {
    test('measures throughput without touching disk', () async {
      harness = await TransferHarness.start();
      final result = await h().sender.benchmark(
        address: InternetAddress.loopbackIPv4,
        port: h().server.port,
        expectedFingerprint: receiverIdentity.fingerprint,
        bytes: 16 * _mib,
      );
      expect(result.bytes, 16 * _mib);
      expect(result.transferMs, greaterThan(0));
      expect(result.megabytesPerSecond, greaterThan(0));
      expect(h().downloads.listSync(), isEmpty);
    });

    test('is not served by a stock receiver', () async {
      harness = await TransferHarness.start(enableChunking: false);
      await expectLater(
        h().sender.benchmark(
          address: InternetAddress.loopbackIPv4,
          port: h().server.port,
          expectedFingerprint: receiverIdentity.fingerprint,
          bytes: 1 * _mib,
        ),
        throwsA(isA<SendException>()),
      );
    });
  });
}
