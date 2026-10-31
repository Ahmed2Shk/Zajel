import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zajel/core/transfer/protocol_models.dart';
import 'package:zajel/core/transfer/receive_server.dart';
import 'package:zajel/core/transfer/send_client.dart';

import '../support/transfer_harness.dart';

void main() {
  late TransferHarness harness;
  var started = false;
  late Directory source;

  Future<void> begin({IncomingDecision? onIncoming, String? pin}) async {
    harness = await TransferHarness.start(onIncoming: onIncoming, pin: pin);
    started = true;
  }

  setUp(() async {
    source = await Directory.systemTemp.createTemp('zajel_source_');
    started = false;
  });

  tearDown(() async {
    if (started) await harness.dispose();
    started = false;
    await source.delete(recursive: true);
  });

  Future<SendFile> sourceFile(String name, int size, {int seed = 1}) async {
    final file = await writeTestFile(source, name, size, seed: seed);
    return SendFile.fromPath(file.path, id: name);
  }

  test('sends files end to end with matching SHA-256', () async {
    await begin();
    final files = [
      await sourceFile('a.bin', 3 * 1024 * 1024 + 17, seed: 1),
      await sourceFile('b.bin', 1, seed: 2),
      await sourceFile('empty.bin', 0),
    ];
    final events = <ReceiveEvent>[];
    harness.server.events.listen(events.add);

    final session = await harness.prepare(files);
    expect(session.tokens.keys, containsAll(['a.bin', 'b.bin', 'empty.bin']));
    await harness.sender.upload(session: session, files: files);

    for (final f in files) {
      final received = File('${harness.downloads.path}/${f.name}');
      expect(await sha256OfFile(received), await sha256OfFile(f.file));
      expect(await received.length(), f.size);
    }
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<SessionStarted>(), hasLength(1));
    expect(events.whereType<FileReceived>(), hasLength(3));
    expect(events.last, isA<SessionEnded>());
    expect(harness.downloads.listSync().whereType<File>().where((f) => f.path.endsWith('.zajel-part')), isEmpty);
  });

  test('GET /info answers over HTTPS', () async {
    await begin();
    final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
    final request = await client.getUrl(
      Uri.parse('https://127.0.0.1:${harness.server.port}$localSendApiPrefix/info'),
    );
    final response = await request.close();
    final info = jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;
    client.close();
    expect(response.statusCode, 200);
    expect(info['alias'], 'Receiver');
    expect(info['fingerprint'], receiverIdentity.fingerprint);
  });

  test('plain HTTP is not served', () async {
    await begin();
    await expectLater(
      http
          .get(Uri.parse('http://127.0.0.1:${harness.server.port}$localSendApiPrefix/info'))
          .timeout(const Duration(seconds: 5)),
      throwsA(anything),
    );
  });

  test('refuses a peer whose certificate does not match the fingerprint', () async {
    await begin();
    final file = await sourceFile('a.bin', 10);
    await expectLater(
      harness.prepare([file], fingerprint: 'f' * 64),
      throwsA(isA<HandshakeException>()),
    );
  });

  test('declined transfer returns 403', () async {
    await begin(onIncoming: (_) async => null);
    final file = await sourceFile('a.bin', 10);
    await expectLater(
      harness.prepare([file]),
      throwsA(isA<SendException>().having((e) => e.declined, 'declined', isTrue)),
    );
  });

  test('partial accept only issues tokens for accepted files', () async {
    await begin(onIncoming: (_) async => {'a.bin'});
    final files = [await sourceFile('a.bin', 100), await sourceFile('b.bin', 100)];
    final session = await harness.prepare(files);
    expect(session.tokens.keys, ['a.bin']);
    await harness.sender.upload(session: session, files: files);
    expect(File('${harness.downloads.path}/a.bin').existsSync(), isTrue);
    expect(File('${harness.downloads.path}/b.bin').existsSync(), isFalse);
  });

  test('an empty file list finishes with 204', () async {
    await begin();
    final session = await harness.prepare([]);
    expect(session.sessionId, isEmpty);
  });

  group('PIN', () {
    test('missing and wrong PIN get 401, correct PIN is accepted', () async {
      await begin(pin: '123456');
      final file = await sourceFile('a.bin', 10);

      await expectLater(
        harness.prepare([file]),
        throwsA(isA<SendException>().having((e) => e.pinRequired, 'pinRequired', isTrue)),
      );
      await expectLater(
        harness.prepare([file], pin: '000000'),
        throwsA(isA<SendException>().having((e) => e.statusCode, 'status', 401)),
      );
      final session = await harness.prepare([file], pin: '123456');
      expect(session.tokens, isNotEmpty);
    });

    test('locks out after 5 wrong attempts, even for the right PIN', () async {
      await begin(pin: '123456');
      final file = await sourceFile('a.bin', 10);

      for (var i = 0; i < ReceiveServer.maxPinAttempts; i++) {
        await expectLater(
          harness.prepare([file], pin: '00000$i'),
          throwsA(isA<SendException>().having((e) => e.statusCode, 'status', 401)),
        );
      }
      await expectLater(
        harness.prepare([file], pin: '123456'),
        throwsA(isA<SendException>().having((e) => e.tooManyRequests, 'locked', isTrue)),
      );
    });
  });

  group('hostile input', () {
    Future<int> rawPrepare(Map<String, dynamic> files) async {
      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      final request = await client.postUrl(
        Uri.parse('https://127.0.0.1:${harness.server.port}$localSendApiPrefix/prepare-upload'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'info': {'alias': 'evil', 'fingerprint': 'x'},
        'files': files,
      }));
      final response = await request.close();
      await response.drain<void>();
      client.close();
      return response.statusCode;
    }

    for (final name in ['../../evil.txt', '/abs/evil.txt', r'..\evil.txt', 'a/../../b']) {
      test('prepare-upload rejects file name "$name"', () async {
        await begin();
        final status = await rawPrepare({
          'f': {'id': 'f', 'fileName': name, 'size': 1, 'fileType': 'text/plain'},
        });
        expect(status, 400);
        expect(harness.downloads.listSync(), isEmpty);
      });
    }

    test('malformed JSON is a 400', () async {
      await begin();
      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      final request = await client.postUrl(
        Uri.parse('https://127.0.0.1:${harness.server.port}$localSendApiPrefix/prepare-upload'),
      );
      request.write('{not json');
      final response = await request.close();
      await response.drain<void>();
      client.close();
      expect(response.statusCode, 400);
    });

    test('a sub-folder name stays inside the download folder', () async {
      await begin();
      final file = await writeTestFile(source, 'x.bin', 100);
      final send = SendFile(id: 'x', file: file, size: 100, name: 'trip/day1/x.bin');
      final session = await harness.prepare([send]);
      await harness.sender.upload(session: session, files: [send]);
      expect(File('${harness.downloads.path}/trip/day1/x.bin').existsSync(), isTrue);
    });

    test('existing files are never overwritten', () async {
      await begin();
      File('${harness.downloads.path}/a.bin').writeAsStringSync('keep me');
      final file = await sourceFile('a.bin', 100);
      final session = await harness.prepare([file]);
      await harness.sender.upload(session: session, files: [file]);
      expect(File('${harness.downloads.path}/a.bin').readAsStringSync(), 'keep me');
      expect(File('${harness.downloads.path}/a (1).bin').existsSync(), isTrue);
    });
  });

  group('upload checks', () {
    Future<int> rawUpload(String query, {List<int> body = const [1, 2, 3]}) async {
      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      final request = await client.postUrl(
        Uri.parse('https://127.0.0.1:${harness.server.port}$localSendApiPrefix/upload$query'),
      );
      request.add(body);
      final response = await request.close();
      await response.drain<void>();
      client.close();
      return response.statusCode;
    }

    test('missing parameters are a 400', () async {
      await begin();
      expect(await rawUpload(''), 400);
    });

    test('wrong token or session is a 403', () async {
      await begin();
      final file = await sourceFile('a.bin', 3);
      final session = await harness.prepare([file]);
      expect(await rawUpload('?sessionId=${session.sessionId}&fileId=a.bin&token=nope'), 403);
      expect(await rawUpload('?sessionId=nope&fileId=a.bin&token=${session.tokens['a.bin']}'), 403);
      expect(await rawUpload('?sessionId=${session.sessionId}&fileId=zzz&token=nope'), 403);
    });

    test('a token cannot be used twice', () async {
      await begin();
      final file = await sourceFile('a.bin', 3);
      final other = await sourceFile('b.bin', 3);
      final session = await harness.prepare([file, other]);
      final query = '?sessionId=${session.sessionId}&fileId=a.bin&token=${session.tokens['a.bin']}';
      expect(await rawUpload(query), 200);
      expect(await rawUpload(query), 403);
    });

    test('checksum mismatch is a 422 and nothing is kept', () async {
      await begin();
      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      final prepare = await client.postUrl(
        Uri.parse('https://127.0.0.1:${harness.server.port}$localSendApiPrefix/prepare-upload'),
      );
      prepare.headers.contentType = ContentType.json;
      prepare.write(jsonEncode({
        'info': {'alias': 'x', 'fingerprint': 'x'},
        'files': {
          'f': {'id': 'f', 'fileName': 'f.bin', 'size': 3, 'fileType': 'a/b', 'sha256': '0' * 64},
        },
      }));
      final prepared = jsonDecode(await utf8.decodeStream(await prepare.close())) as Map<String, dynamic>;
      client.close();

      final token = (prepared['files'] as Map)['f'];
      final status = await rawUpload('?sessionId=${prepared['sessionId']}&fileId=f&token=$token');
      expect(status, 422);
      expect(harness.downloads.listSync(), isEmpty);
    });

    test('a size mismatch is rejected and nothing is kept', () async {
      await begin();
      final file = await sourceFile('a.bin', 100);
      final session = await harness.prepare([file]);
      final status = await rawUpload(
        '?sessionId=${session.sessionId}&fileId=a.bin&token=${session.tokens['a.bin']}',
        body: [1, 2, 3],
      );
      expect(status, 400);
      expect(harness.downloads.listSync(), isEmpty);
    });
  });

  group('sessions', () {
    test('a second sender is blocked while a session is active', () async {
      await begin();
      final file = await sourceFile('a.bin', 10);
      await harness.prepare([file]);
      await expectLater(
        harness.prepare([file]),
        throwsA(isA<SendException>().having((e) => e.busy, 'busy', isTrue)),
      );
    });

    test('cancel ends the session and frees the receiver', () async {
      await begin();
      final file = await sourceFile('a.bin', 10);
      final session = await harness.prepare([file]);
      await harness.sender.cancel(session);
      final again = await harness.prepare([file]);
      expect(again.tokens, isNotEmpty);
    });
  });
}
