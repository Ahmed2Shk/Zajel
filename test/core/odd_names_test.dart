import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/security/file_name_sanitizer.dart';
import 'package:zajel/core/transfer/protocol_models.dart';
import 'package:zajel/core/transfer/send_client.dart';

import '../support/transfer_harness.dart';

/// One oddly named file must not fail a whole batch (AUDIT.md, A4).
void main() {
  group('normalizeSentFileName', () {
    test('leaves ordinary names alone', () {
      for (final name in ['photo.jpg', 'هاتف سارة.pdf', 'trip/day 1/a.b.c.mp4', '.hidden']) {
        expect(normalizeSentFileName(name), name);
      }
    });

    test('repairs what the receiver would refuse', () {
      expect(normalizeSentFileName('notes .txt '), 'notes .txt');
      expect(normalizeSentFileName('draft.'), 'draft');
      expect(normalizeSentFileName(' report.pdf'), 'report.pdf');
      expect(normalizeSentFileName('a\tb\n.txt'), 'a_b_.txt');
      expect(normalizeSentFileName(r'folder\file.txt'), 'folder/file.txt');
      expect(normalizeSentFileName('C:notes.txt'), '_notes.txt');
      expect(normalizeSentFileName('/abs/path.txt'), 'abs/path.txt');
      expect(normalizeSentFileName('../../etc/passwd'), 'etc/passwd');
      expect(normalizeSentFileName('trip /day1. /a.jpg'), 'trip/day1/a.jpg');
      expect(normalizeSentFileName(' . '), 'file');
      expect(normalizeSentFileName(''), 'file');
    });

    test('whatever goes in, the receiver accepts what comes out', () {
      const nasty = [
        'a ', ' a', 'a.', 'a..', '..', '.', '', '/', r'\', 'a/../b', 'a//b', 'C:', r'C:\x\y.txt',
        'tab\there', 'nul\x00l', 'x/ /y', 'x/./y', '....', 'ملف .', 'a/b/ c .txt.',
      ];
      for (final name in nasty) {
        final normalized = normalizeSentFileName(name);
        expect(() => sanitizeReceivedFileName(normalized), returnsNormally, reason: '"$name" -> "$normalized"');
        expect(normalized.contains('..'), isFalse, reason: name);
      }
    });
  });

  group('transfer', () {
    late TransferHarness harness;
    late Directory source;

    setUp(() async {
      harness = await TransferHarness.start();
      source = await createTestDir('zajel_names_src_');
    });

    tearDown(() async {
      await harness.dispose();
      await deleteTestDir(source);
    });

    test('a Zajel sender delivers a file with a trailing space and dot in its name', () async {
      final good = await SendFile.fromPath((await writeTestFile(source, 'a.bin', 2000)).path, id: 'a');
      final odd = await SendFile.fromPath(
        (await writeTestFile(source, 'b.bin', 3000, seed: 2)).path,
        id: 'b',
        name: 'my notes .', // as a file manager on the phone may show it
      );

      final session = await harness.prepare([good, odd]);
      expect(session.tokens.keys, containsAll(['a', 'b']));
      await harness.sender.upload(session: session, files: [good, odd]);

      expect(await File('${harness.downloads.path}/a.bin').length(), 2000);
      expect(await File('${harness.downloads.path}/my notes').length(), 3000);
    });

    test('from another app, an unsafe name is left out and the rest is accepted', () async {
      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      addTearDown(() => client.close(force: true));
      Future<HttpClientResponse> prepare(Map<String, Object?> files) async {
        final request = await client.postUrl(
          Uri.parse('https://127.0.0.1:${harness.server.port}$localSendApiPrefix/prepare-upload'),
        );
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({
          'info': {'alias': 'x', 'fingerprint': 'x'},
          'files': files,
        }));
        return request.close();
      }

      Map<String, Object?> file(String id, String name) => {
        'id': id,
        'fileName': name,
        'size': 3,
        'fileType': 'a/b',
      };

      final mixed = await prepare({
        'ok': file('ok', 'fine.txt'),
        'bad': file('bad', '../../outside.txt'),
        'odd': file('odd', 'trailing space .txt '),
      });
      expect(mixed.statusCode, 200);
      final tokens = (jsonDecode(await utf8.decodeStream(mixed)) as Map<String, dynamic>)['files'] as Map;
      expect(tokens.keys, ['ok'], reason: 'only the safe file gets a token');
      await harness.server.cancelSession();

      // Nothing acceptable at all is still a plain refusal.
      final none = await prepare({'bad': file('bad', '../../outside.txt')});
      await none.drain<void>();
      expect(none.statusCode, 400);
      expect(harness.downloads.listSync(recursive: true), isEmpty);
    });
  });
}
