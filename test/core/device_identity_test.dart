import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/security/device_identity.dart';

void main() {
  late DeviceIdentity identity;

  setUpAll(() => identity = DeviceIdentity.generate());

  test('fingerprint is the SHA-256 of the DER certificate', () {
    final body = const LineSplitter()
        .convert(identity.certificatePem)
        .where((line) => !line.startsWith('-----'))
        .join();
    final der = base64.decode(body);
    expect(identity.fingerprint, sha256.convert(der).toString());
    expect(identity.fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('builds a TLS context from the generated cert and key', () {
    expect(identity.toSecurityContext, returnsNormally);
  });

  test('loadOrCreate keeps the same fingerprint across launches', () async {
    final dir = await Directory.systemTemp.createTemp('zajel_identity_');
    addTearDown(() => dir.delete(recursive: true));

    final first = await DeviceIdentity.loadOrCreate(dir);
    final second = await DeviceIdentity.loadOrCreate(dir);
    expect(second.fingerprint, first.fingerprint);
  });
}
