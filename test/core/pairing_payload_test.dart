import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/transport/pairing_payload.dart';

PairingPayload _good() => PairingPayload(
  ssid: 'AndroidShare_1234',
  passphrase: 'correct-horse',
  ip: '192.168.43.1',
  port: 53317,
  fingerprint: 'a' * 64,
  token: 'tokentokentoken12',
  pin: '4821',
  alias: 'Sara phone',
);

String _encodeList(List<Object?> list) =>
    'zajel://pair?d=${base64Url.encode(utf8.encode(jsonEncode(list))).replaceAll('=', '')}';

String _fp(String hexChar) =>
    base64Url.encode(List.filled(32, int.parse(hexChar * 2, radix: 16))).replaceAll('=', '');

// [version, ssid, pass, ip, port, fp, tok, pin, name]
List<Object?> _goodList() => [2, 'net', 'password1', '192.168.43.1', 53317, _fp('b'), 'abcdefghijklmnop', '1234', 'x'];

List<Object?> _with(int index, Object? value) => [..._goodList()]..[index] = value;

void main() {
  test('encode and parse round-trip', () {
    final original = _good();
    final copy = PairingPayload.parse(original.encode());
    expect(copy.ssid, original.ssid);
    expect(copy.passphrase, original.passphrase);
    expect(copy.ip, original.ip);
    expect(copy.port, original.port);
    expect(copy.fingerprint, original.fingerprint);
    expect(copy.token, original.token);
    expect(copy.pin, original.pin);
    expect(copy.alias, original.alias);
  });

  test('the code fits comfortably in a QR code', () {
    expect(_good().encode().length, lessThan(300));
  });

  test('unicode device names survive', () {
    final copy = PairingPayload.parse(
      PairingPayload(
        ssid: 'net', passphrase: 'password1', ip: '10.0.0.1', port: 1,
        fingerprint: 'c' * 64, token: 'abcdefghijklmnop', pin: '0000', alias: 'هاتف سارة',
      ).encode(),
    );
    expect(copy.alias, 'هاتف سارة');
  });

  test('padding-free base64 of every length decodes', () {
    for (var i = 1; i < 12; i++) {
      final payload = PairingPayload(
        ssid: 'n' * i, passphrase: 'password1', ip: '10.0.0.1', port: 1,
        fingerprint: 'c' * 64, token: 'abcdefghijklmnop', pin: '0000', alias: 'a' * i,
      );
      expect(PairingPayload.parse(payload.encode()).ssid, 'n' * i);
    }
  });

  group('rejects what is not a valid Zajel code', () {
    void bad(String name, String raw) {
      test(name, () => expect(() => PairingPayload.parse(raw), throwsA(isA<PairingFormatException>())));
    }

    bad('empty', '');
    bad('a website', 'https://example.com/pair?d=abc');
    bad('wrong scheme', 'localsend://pair?d=abc');
    bad('wrong host', 'zajel://other?d=abc');
    bad('no data', 'zajel://pair');
    bad('data that is not base64', 'zajel://pair?d=!!!!');
    bad('data that is not json', 'zajel://pair?d=${base64Url.encode(utf8.encode('hello'))}');
    bad('json that is not a list', _encodeMapRaw('{"v":2}'));
    bad('oversized data', 'zajel://pair?d=${'a' * 3000}');
  });

  group('rejects bad fields', () {
    void badField(String name, int index, Object? value) {
      test(name, () {
        expect(() => PairingPayload.parse(_encodeList(_with(index, value))), throwsA(isA<PairingFormatException>()));
      });
    }

    test('the good list is accepted', () {
      final parsed = PairingPayload.parse(_encodeList(_goodList()));
      expect(parsed.ssid, 'net');
      expect(parsed.fingerprint, 'b' * 64);
    });

    test('a list of the wrong length', () {
      expect(
        () => PairingPayload.parse(_encodeList(_goodList()..removeLast())),
        throwsA(isA<PairingFormatException>()),
      );
    });

    badField('old version', 0, 1);
    badField('missing version', 0, null);
    badField('empty ssid', 1, '');
    badField('long ssid', 1, 'x' * 33);
    badField('short passphrase', 2, 'short');
    badField('long passphrase', 2, 'x' * 64);
    badField('port 0', 4, 0);
    badField('port too big', 4, 70000);
    badField('port as text', 4, '53317');
    badField('short fingerprint', 5, _fp('a').substring(1));
    badField('fingerprint that is not base64', 5, '!' * 43);
    badField('short token', 6, 'abc');
    badField('token with odd characters', 6, 'abc defghijklmnop!');
    badField('pin with letters', 7, 'abcd');
    badField('pin too short', 7, '12');
    badField('empty name', 8, '');
    badField('name as number', 8, 5);
    badField('hostname instead of ip', 3, 'example.com');
    badField('public ip', 3, '8.8.8.8');
    badField('ipv6', 3, '::1');
    badField('loopback', 3, '127.0.0.1');
    badField('link-local', 3, '169.254.1.1');
    badField('172 outside the private range', 3, '172.32.0.1');
  });

  test('accepts every private address range', () {
    for (final ip in ['10.1.2.3', '172.16.0.1', '172.31.255.254', '192.168.49.1']) {
      expect(PairingPayload.parse(_encodeList(_with(3, ip))).ip, ip);
    }
  });

  test('surrounding whitespace from a scanner is tolerated', () {
    expect(PairingPayload.parse('  ${_good().encode()}\n').ssid, 'AndroidShare_1234');
  });
}

String _encodeMapRaw(String json) =>
    'zajel://pair?d=${base64Url.encode(utf8.encode(json)).replaceAll('=', '')}';
