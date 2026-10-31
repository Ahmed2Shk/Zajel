import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/transfer/protocol_models.dart';
import 'package:zajel/core/transfer/send_client.dart';
import 'package:zajel/core/transfer/tar_stream.dart';

import '../support/transfer_harness.dart';

void main() {
  TransferHarness? harness;
  late Directory source;

  TransferHarness h() => harness!;

  setUp(() async {
    source = await createTestDir('zajel_tar_src_');
  });

  tearDown(() async {
    await harness?.dispose();
    harness = null;
    await source.delete(recursive: true);
  });

  Future<List<SendFile>> smallFiles(int count, {int maxSize = 100 * 1024}) async {
    final files = <SendFile>[];
    for (var i = 0; i < count; i++) {
      // Includes empty and block-boundary sizes.
      final size = switch (i) {
        0 => 0,
        1 => 1,
        2 => 512,
        3 => 513,
        _ => (i * 7919) % maxSize,
      };
      final file = await writeTestFile(source, 'f$i.bin', size, seed: i + 1);
      files.add(await SendFile.fromPath(file.path, id: 'id$i', name: 'f$i.bin'));
    }
    return files;
  }

  Future<void> expectAllReceived(List<SendFile> files) async {
    for (final f in files) {
      final received = File('${h().downloads.path}/${f.name}');
      expect(await received.length(), f.size, reason: f.name);
      expect(await sha256OfFile(received), await sha256OfFile(f.file), reason: f.name);
    }
  }

  List<String> leftovers() => h().downloads
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.zajel-part'))
      .map((f) => f.path)
      .toList();

  int finishedFiles() => h().downloads
      .listSync()
      .whereType<File>()
      .where((f) => !f.path.endsWith('.zajel-part'))
      .length;

  group('sending many small files', () {
    test('30 files go in one archive request', () async {
      harness = await TransferHarness.start();
      final files = await smallFiles(30);
      final events = <dynamic>[];
      h().server.events.listen(events.add);

      final session = await h().prepare(files);
      expect(session.tarToken, isNotNull);
      await h().sender.upload(session: session, files: files);
      await Future<void>.delayed(Duration.zero);

      await expectAllReceived(files);
      expect(h().server.tarUploadRequests, 1);
      expect(h().server.plainUploadRequests, 0);
      expect(events.where((e) => e.runtimeType.toString() == 'FileReceived'), hasLength(30));
      expect(events.last.runtimeType.toString(), 'SessionEnded');
      expect(leftovers(), isEmpty);
    });

    test('progress reaches each file size', () async {
      harness = await TransferHarness.start();
      final files = await smallFiles(8);
      final session = await h().prepare(files);
      final sent = <String, int>{};
      await h().sender.upload(
        session: session,
        files: files,
        onProgress: (id, bytes) => sent[id] = bytes,
      );
      for (final f in files) {
        expect(sent[f.id], f.size, reason: f.name);
      }
    });

    test('fewer files than the threshold use plain uploads', () async {
      harness = await TransferHarness.start();
      final files = await smallFiles(3);
      final session = await h().prepare(files);
      await h().sender.upload(session: session, files: files);
      await expectAllReceived(files);
      expect(h().server.tarUploadRequests, 0);
      expect(h().server.plainUploadRequests, 3);
    });

    test('a stock receiver gets plain uploads and no tar', () async {
      harness = await TransferHarness.start(enableChunking: false);
      final files = await smallFiles(10);
      final session = await h().prepare(files);
      expect(session.tarToken, isNull);
      await h().sender.upload(session: session, files: files);
      await expectAllReceived(files);
      expect(h().server.tarUploadRequests, 0);
    });

    test('small and large files mix', () async {
      harness = await TransferHarness.start();
      final files = await smallFiles(6);
      final big = await SendFile.fromPath(
        (await writeTestFile(source, 'big.bin', 3 * 1024 * 1024, seed: 99)).path,
        id: 'big',
        name: 'big.bin',
      );
      final all = [...files, big];
      final session = await h().prepare(all);
      await h().sender.upload(
        session: session,
        files: all,
        options: const UploadOptions(chunkSize: 1024 * 1024),
      );
      await expectAllReceived(all);
      expect(h().server.tarUploadRequests, 1);
    });

    test('a file id too long for a tar name falls back to a plain upload', () async {
      harness = await TransferHarness.start();
      final files = await smallFiles(5);
      final longFile = await SendFile.fromPath(
        files.first.file.path,
        id: 'x' * 120,
        name: 'long-id.bin',
      );
      final all = [...files.skip(1), longFile];
      final session = await h().prepare(all);
      await h().sender.upload(session: session, files: all);
      await expectAllReceived(all);
    });

    test('an interrupted archive resumes with only the missing files', () async {
      harness = await TransferHarness.start();
      final files = await smallFiles(20, maxSize: 200 * 1024);
      final session = await h().prepare(files);

      // Abort once the sender is well into the archive. The receiver finishes
      // whatever arrived before the connection dropped.
      var stop = true;
      final started = <String>{};
      await expectLater(
        h().sender.upload(
          session: session,
          files: files,
          onProgress: (id, _) => started.add(id),
          isCancelled: () => stop && started.contains('id14'),
        ),
        throwsA(isA<SendException>()),
      );
      stop = false;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(finishedFiles(), inInclusiveRange(1, 19));

      final reports = <String>{};
      await h().sender.upload(
        session: session,
        files: files,
        onProgress: (id, _) => reports.add(id),
      );
      await expectAllReceived(files);
      expect(leftovers(), isEmpty);
      expect(reports, isNotEmpty);
    });
  });

  group('hostile archives', () {
    late SendSession session;
    late List<SendFile> files;

    setUp(() async {
      harness = await TransferHarness.start();
      files = await smallFiles(5);
      session = await h().prepare(files);
    });

    Future<int> postTar(
      Iterable<TarEntry> entries, {
      String? token,
      Uint8List Function(Uint8List)? corrupt,
      int? cutAt,
    }) async {
      final out = BytesBuilder();
      await for (final chunk in tarEncode(entries)) {
        out.add(chunk);
      }
      var bytes = out.toBytes();
      if (corrupt != null) bytes = corrupt(bytes);
      if (cutAt != null) bytes = bytes.sublist(0, cutAt);

      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      final request = await client.postUrl(Uri.parse(
        'https://127.0.0.1:${h().server.port}$zajelTarRoute'
        '?sessionId=${session.sessionId}&token=${token ?? session.tarToken}',
      ));
      request.headers.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close();
      await response.drain<void>();
      client.close();
      return response.statusCode;
    }

    TarEntry entry(String name, List<int> data) =>
        TarEntry(name: name, size: data.length, open: () => Stream.value(data));

    Future<List<int>> contentOf(SendFile f) => f.file.readAsBytes();

    test('a wrong token is refused', () async {
      expect(await postTar([entry('id1', await contentOf(files[1]))], token: 'nope'), 403);
    });

    test('path-like entry names are not file ids', () async {
      for (final name in ['../../evil.txt', '/etc/passwd', r'..\evil', 'f1.bin']) {
        expect(await postTar([entry(name, [1, 2, 3])]), 400, reason: name);
      }
      expect(h().downloads.listSync().whereType<File>(), isEmpty);
      expect(File('${h().downloads.parent.path}/evil.txt').existsSync(), isFalse);
    });

    test('an entry with the wrong size is refused', () async {
      expect(await postTar([entry('id2', List.filled(5, 1))]), 400);
      expect(h().downloads.listSync().whereType<File>(), isEmpty);
    });

    test('a corrupted header is refused', () async {
      final data = await contentOf(files[2]);
      expect(await postTar([entry('id2', data)], corrupt: (b) => b..[3] ^= 0xff), 400);
    });

    test('a symlink entry is refused', () async {
      final data = await contentOf(files[2]);
      expect(
        await postTar([entry('id2', data)], corrupt: (b) {
          b[156] = 0x32;
          var sum = 0;
          for (var i = 0; i < 512; i++) {
            sum += (i >= 148 && i < 156) ? 0x20 : b[i];
          }
          b.setRange(148, 154, ascii.encode(sum.toRadixString(8).padLeft(6, '0')));
          return b;
        }),
        400,
      );
    });

    test('a truncated archive keeps finished files and drops the partial one', () async {
      final first = await contentOf(files[3]); // 513 bytes
      final second = await contentOf(files[4]);
      final cut = 512 + 1024 + 512 + 100; // inside the second entry
      expect(await postTar([entry('id3', first), entry('id4', second)], cutAt: cut), 400);
      expect(File('${h().downloads.path}/f3.bin').existsSync(), isTrue);
      expect(File('${h().downloads.path}/f4.bin').existsSync(), isFalse);
      expect(leftovers().where((p) => p.contains('f4')), isEmpty);
    });

    test('an entry that was already received is refused', () async {
      final data = await contentOf(files[3]);
      expect(await postTar([entry('id3', data)]), 200);
      expect(await postTar([entry('id3', data)]), 409);
    });
  });

  test('a checksum mismatch inside an archive is a 422', () async {
    harness = await TransferHarness.start();
    final data = List.filled(100, 3);
    final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
    final prepare = await client.postUrl(Uri.parse(
      'https://127.0.0.1:${h().server.port}$localSendApiPrefix/prepare-upload',
    ));
    prepare.headers
      ..contentType = ContentType.json
      ..set(zajelExtensionHeader, zajelExtensionVersion);
    prepare.write(jsonEncode({
      'info': {'alias': 'x', 'fingerprint': 'x'},
      'files': {
        'f': {
          'id': 'f',
          'fileName': 'a.bin',
          'size': 100,
          'fileType': 'a/b',
          'sha256': '0' * 64,
        },
      },
    }));
    final prepared = await prepare.close();
    final tarToken = prepared.headers.value(zajelTarTokenHeader);
    final sessionId = (jsonDecode(await utf8.decodeStream(prepared)) as Map)['sessionId'];

    final bytes = BytesBuilder();
    await for (final c in tarEncode([
      TarEntry(name: 'f', size: 100, open: () => Stream.value(data)),
    ])) {
      bytes.add(c);
    }
    final post = await client.postUrl(Uri.parse(
      'https://127.0.0.1:${h().server.port}$zajelTarRoute?sessionId=$sessionId&token=$tarToken',
    ));
    post.headers.contentLength = bytes.length;
    post.add(bytes.toBytes());
    final response = await post.close();
    await response.drain<void>();
    client.close();

    expect(response.statusCode, 422);
    expect(h().downloads.listSync().whereType<File>(), isEmpty);
  });
}
