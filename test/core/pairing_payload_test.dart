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

String _encodeMap(Map<String, Object?> map) =>
    'zajel://pair?d=${base64Url.encode(utf8.encode(jsonEncode(map))).replaceAll('=', '')}';

Map<String, Object?> _goodMap() => {
  'v': 1,
  'ssid': 'net',
  'pass': 'password1',
  'ip': '192.168.43.1',
  'port': 53317,
  'fp': 'b' * 64,
  'tok': 'abcdefghijklmnop',
  'pin': '1234',
  'name': 'x',
};

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
    expect(_good().encode().length, lessThan(400));
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
    bad('json that is not an object', _encodeMapRaw('[1,2]'));
    bad('oversized data', 'zajel://pair?d=${'a' * 3000}');
  });

  group('rejects bad fields', () {
    void badField(String name, Map<String, Object?> change) {
      test(name, () {
        final map = {..._goodMap(), ...change};
        expect(() => PairingPayload.parse(_encodeMap(map)), throwsA(isA<PairingFormatException>()));
      });
    }

    test('the good map is accepted', () {
      expect(PairingPayload.parse(_encodeMap(_goodMap())).ssid, 'net');
    });

    badField('wrong version', {'v': 2});
    badField('missing version', {'v': null});
    badField('empty ssid', {'ssid': ''});
    badField('long ssid', {'ssid': 'x' * 33});
    badField('short passphrase', {'pass': 'short'});
    badField('long passphrase', {'pass': 'x' * 64});
    badField('port 0', {'port': 0});
    badField('port too big', {'port': 70000});
    badField('port as text', {'port': '53317'});
    badField('short fingerprint', {'fp': 'a' * 63});
    badField('uppercase fingerprint', {'fp': 'A' * 64});
    badField('non-hex fingerprint', {'fp': 'g' * 64});
    badField('short token', {'tok': 'abc'});
    badField('token with odd characters', {'tok': 'abc defghijklmnop!'});
    badField('pin with letters', {'pin': 'abcd'});
    badField('pin too short', {'pin': '12'});
    badField('empty name', {'name': ''});
    badField('name as number', {'name': 5});
    badField('hostname instead of ip', {'ip': 'example.com'});
    badField('public ip', {'ip': '8.8.8.8'});
    badField('ipv6', {'ip': '::1'});
    badField('loopback', {'ip': '127.0.0.1'});
    badField('link-local', {'ip': '169.254.1.1'});
    badField('172 outside the private range', {'ip': '172.32.0.1'});
  });

  test('accepts every private address range', () {
    for (final ip in ['10.1.2.3', '172.16.0.1', '172.31.255.254', '192.168.49.1']) {
      final map = {..._goodMap(), 'ip': ip};
      expect(PairingPayload.parse(_encodeMap(map)).ip, ip);
    }
  });

  test('surrounding whitespace from a scanner is tolerated', () {
    expect(PairingPayload.parse('  ${_good().encode()}\n').ssid, 'AndroidShare_1234');
  });
}

String _encodeMapRaw(String json) =>
    'zajel://pair?d=${base64Url.encode(utf8.encode(json)).replaceAll('=', '')}';
