import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/transfer/protocol_models.dart';
import 'package:zajel/core/transfer/receive_server.dart';
import 'package:zajel/core/transfer/send_client.dart';
import 'package:zajel/core/transfer/web_share_page.dart';
import 'package:zajel/core/transfer/web_share_server.dart';

import '../support/transfer_harness.dart';

const _strings = WebPageStrings(
  title: 'Zajel',
  warning: 'NOT-ENCRYPTED-WARNING',
  downloads: 'Downloads',
  uploads: 'Uploads',
  choose: 'Choose',
  send: 'Send',
  waiting: 'Waiting',
  done: 'Done',
  declined: 'Declined',
  busy: 'Busy',
  failed: 'Failed',
  pin: 'PIN',
  noFiles: 'None',
);

void main() {
  late Directory downloads;
  late Directory source;
  late WebShareServer server;
  late ReceiveServer receiver;
  late HttpClient client;

  Future<void> boot({
    List<SendFile> files = const [],
    String alias = 'My phone',
    IncomingDecision? onIncoming,
    String? pin,
  }) async {
    final info = DeviceInfo(alias: alias, fingerprint: receiverIdentity.fingerprint);
    receiver = ReceiveServer(
      identity: receiverIdentity,
      device: info,
      downloadDirectory: downloads,
      onIncoming: onIncoming ?? (t) async => t.files.keys.toSet(),
      pin: pin,
    );
    server = WebShareServer(
      device: info,
      receiver: receiver,
      strings: _strings,
      rtl: false,
      files: files,
    );
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
  }

  setUp(() async {
    downloads = await createTestDir('zajel_web_dl_');
    source = await createTestDir('zajel_web_src_');
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
    await receiver.stop();
    await downloads.delete(recursive: true);
    await source.delete(recursive: true);
  });

  Uri url(String path, {String? token, Map<String, String> extra = const {}}) =>
      Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: server.port,
        path: path,
        queryParameters: {'t': token ?? server.token, ...extra},
      );

  Future<(int, String, HttpHeaders)> get(Uri uri) async {
    final response = await (await client.getUrl(uri)).close();
    return (response.statusCode, await utf8.decodeStream(response), response.headers);
  }

  Future<(int, String)> post(Uri uri, {Object? json}) async {
    final request = await client.postUrl(uri);
    if (json != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(json));
    }
    final response = await request.close();
    return (response.statusCode, await utf8.decodeStream(response));
  }

  group('page and token', () {
    test('the page needs the token', () async {
      await boot();
      expect((await get(Uri.parse('http://127.0.0.1:${server.port}/'))).$1, 403);
      expect((await get(url('/', token: 'wrong'))).$1, 403);
      expect((await get(url('/', token: ''))).$1, 403);
    });

    test('with the token the page loads, warns, and locks down what it may load', () async {
      await boot();
      final (status, body, headers) = await get(url('/'));
      expect(status, 200);
      expect(headers.contentType?.mimeType, 'text/html');
      expect(body, contains('NOT-ENCRYPTED-WARNING'));
      final csp = headers.value('content-security-policy')!;
      expect(csp, contains("default-src 'none'"));
      expect(csp, contains("connect-src 'self'"));
      expect(headers.value('referrer-policy'), 'no-referrer');
      expect(headers.value('cache-control'), 'no-store');
      // Nothing is fetched from elsewhere.
      expect(RegExp(r'(src|href)\s*=\s*"https?://').hasMatch(body), isFalse);
    });

    test('a hostile device name cannot break out of the script', () async {
      await boot(alias: '</script><script>alert(1)</script>');
      final (_, body, _) = await get(url('/'));
      expect(body.contains('</script><script>alert'), isFalse);
      // The name is present, but with every angle bracket written as an escape.
      final escaped = '${String.fromCharCode(0x5c)}u003c/script${String.fromCharCode(0x5c)}u003e';
      expect(body, contains(escaped));
    });

    test('api routes need the token too', () async {
      await boot();
      final bare = Uri.parse('http://127.0.0.1:${server.port}$localSendApiPrefix/info');
      expect((await get(bare)).$1, 403);
      expect((await get(url('$localSendApiPrefix/info'))).$1, 200);
      expect((await post(bare.replace(path: '$localSendApiPrefix/prepare-upload'))).$1, 403);
    });

    test('unknown paths are 404 whatever the token', () async {
      await boot();
      expect((await get(url('/admin'))).$1, 404);
      expect((await get(Uri.parse('http://127.0.0.1:${server.port}/secret'))).$1, 404);
    });

    test('the token is random and long enough to guess-proof a link', () async {
      await boot();
      expect(server.token.length, greaterThanOrEqualTo(20));
      final other = WebShareServer(
        device: const DeviceInfo(alias: 'x', fingerprint: 'f'),
        receiver: receiver,
        strings: _strings,
        rtl: false,
      );
      expect(other.token, isNot(server.token));
    });

    test('the link carries the token', () async {
      await boot();
      final link = server.linkFor(InternetAddress('192.168.1.5'));
      expect(link.scheme, 'http');
      expect(link.host, '192.168.1.5');
      expect(link.queryParameters['t'], server.token);
    });

    test('a busy default port falls back to another', () async {
      await boot();
      final second = WebShareServer(
        device: const DeviceInfo(alias: 'x', fingerprint: 'f'),
        receiver: receiver,
        strings: _strings,
        rtl: false,
      );
      await second.start(address: InternetAddress.loopbackIPv4, port: server.port);
      addTearDown(second.stop);
      expect(second.port, isNot(server.port));
    });
  });

  group('downloads', () {
    late SendFile first;

    setUp(() async {
      first = await SendFile.fromPath(
        (await writeTestFile(source, 'photo one.jpg', 300000, seed: 3)).path,
        id: 'a1',
      );
    });

    test('lists the files and streams them intact', () async {
      await boot(files: [first]);
      final (status, body) = await post(url('$localSendApiPrefix/prepare-download'));
      expect(status, 200);
      final listing = jsonDecode(body) as Map<String, dynamic>;
      final entry = (listing['files'] as Map)['a1'] as Map;
      expect(entry['fileName'], 'photo one.jpg');
      expect(entry['size'], 300000);

      final response = await (await client.getUrl(url(
        '$localSendApiPrefix/download',
        extra: {'sessionId': listing['sessionId'] as String, 'fileId': 'a1'},
      ))).close();
      final bytes = await response.expand((b) => b).toList();
      expect(response.statusCode, 200);
      expect(response.headers.contentLength, 300000);
      expect(response.headers.value('content-disposition'), startsWith('attachment;'));
      expect(response.headers.value('content-disposition'), contains('photo%20one.jpg'));
      expect(response.headers.value('x-content-type-options'), 'nosniff');
      expect(bytes, await first.file.readAsBytes());
    });

    test('a wrong session or file is refused', () async {
      await boot(files: [first]);
      final listing = jsonDecode((await post(url('$localSendApiPrefix/prepare-download'))).$2)
          as Map<String, dynamic>;
      final session = listing['sessionId'] as String;

      expect((await get(url('$localSendApiPrefix/download',
          extra: {'sessionId': 'nope', 'fileId': 'a1'}))).$1, 403);
      expect((await get(url('$localSendApiPrefix/download',
          extra: {'sessionId': session, 'fileId': 'zzz'}))).$1, 404);
      expect((await get(url('$localSendApiPrefix/download',
          extra: {'sessionId': session, 'fileId': 'a1'}, token: 'wrong'))).$1, 403);
    });

    test('with a PIN set, listing needs it', () async {
      await boot(files: [first], pin: '4321');
      expect((await post(url('$localSendApiPrefix/prepare-download'))).$1, 401);
      expect((await post(url('$localSendApiPrefix/prepare-download', extra: {'pin': '0000'}))).$1, 401);
      expect((await post(url('$localSendApiPrefix/prepare-download', extra: {'pin': '4321'}))).$1, 200);
    });

    test('with nothing shared the list is empty', () async {
      await boot();
      final (status, body) = await post(url('$localSendApiPrefix/prepare-download'));
      expect(status, 200);
      expect((jsonDecode(body) as Map)['files'], isEmpty);
    });
  });

  group('uploads from the browser', () {
    Map<String, dynamic> prepareBody(String name, int size) => {
      'info': {'alias': 'Browser', 'version': '2.0', 'deviceType': 'web', 'fingerprint': 'web-1', 'protocol': 'http'},
      'files': {
        'f0': {'id': 'f0', 'fileName': name, 'size': size, 'fileType': 'text/plain'},
      },
    };

    test('prepare then upload saves the file after acceptance', () async {
      await boot();
      final (status, body) = await post(
        url('$localSendApiPrefix/prepare-upload'),
        json: prepareBody('hello.txt', 5),
      );
      expect(status, 200);
      final session = jsonDecode(body) as Map<String, dynamic>;
      final token = (session['files'] as Map)['f0'];

      final upload = await client.postUrl(url('$localSendApiPrefix/upload', extra: {
        'sessionId': session['sessionId'] as String,
        'fileId': 'f0',
        'token': token as String,
      }));
      upload.add(utf8.encode('hello'));
      final response = await upload.close();
      await response.drain<void>();
      expect(response.statusCode, 200);
      expect(File('${downloads.path}/hello.txt').readAsStringSync(), 'hello');
    });

    test('a declined request is a 403 and nothing is written', () async {
      await boot(onIncoming: (_) async => null);
      expect((await post(url('$localSendApiPrefix/prepare-upload'),
          json: prepareBody('hello.txt', 5))).$1, 403);
      expect(downloads.listSync(), isEmpty);
    });

    test('hostile names from the browser are refused', () async {
      await boot();
      for (final name in ['../../evil.txt', '/etc/passwd', r'..\evil.txt']) {
        expect((await post(url('$localSendApiPrefix/prepare-upload'),
            json: prepareBody(name, 5))).$1, 400, reason: name);
      }
      expect(downloads.listSync(), isEmpty);
    });

    test('a PIN is required when set', () async {
      await boot(pin: '2468');
      expect((await post(url('$localSendApiPrefix/prepare-upload'),
          json: prepareBody('a.txt', 1))).$1, 401);
      expect((await post(url('$localSendApiPrefix/prepare-upload', extra: {'pin': '2468'}),
          json: prepareBody('a.txt', 1))).$1, 200);
    });
  });

  group('helpers', () {
    test('scriptSafeJson escapes characters that can end a script', () {
      final text = scriptSafeJson({'a': '</script><b>& '});
      expect(text.contains('<'), isFalse);
      expect(text.contains('>'), isFalse);
      expect(text.contains('&'), isFalse);
      expect(jsonDecode(text), {'a': '</script><b>& '});
    });

    test('lanAddresses never includes loopback', () async {
      final addresses = await lanAddresses();
      expect(addresses.where((a) => a.isLoopback), isEmpty);
    });
  });
}
