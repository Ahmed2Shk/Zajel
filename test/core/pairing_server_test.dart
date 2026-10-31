import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/transfer/receive_server.dart';
import 'package:zajel/core/transfer/send_client.dart';

import '../support/transfer_harness.dart';

const _token = 'one-time-token-1234567';
const _pairingPin = '4821';

void main() {
  TransferHarness? harness;
  late Directory source;

  TransferHarness h() => harness!;

  setUp(() async {
    source = await createTestDir('zajel_pair_src_');
  });

  tearDown(() async {
    await harness?.dispose();
    harness = null;
    await source.delete(recursive: true);
  });

  Future<SendFile> file() async => SendFile.fromPath(
    (await writeTestFile(source, 'a.bin', 100)).path,
    id: 'a',
  );

  Future<SendSession> prepare(SendFile f, {String? pin, String? pair}) =>
      h().sender.prepareUpload(
        address: InternetAddress.loopbackIPv4,
        port: h().server.port,
        files: [f],
        expectedFingerprint: receiverIdentity.fingerprint,
        pin: pin,
        pairToken: pair,
      );

  Matcher status(int code) =>
      throwsA(isA<SendException>().having((e) => e.statusCode, 'status', code));

  test('an armed pairing refuses senders without the token or PIN', () async {
    harness = await TransferHarness.start();
    h().server.armPairing(token: _token, pin: _pairingPin);
    final f = await file();
    await expectLater(prepare(f), status(401));
    await expectLater(prepare(f, pair: 'wrong-token'), status(401));
    await expectLater(prepare(f, pin: '0000'), status(401));
  });

  test('the QR token is accepted', () async {
    harness = await TransferHarness.start();
    h().server.armPairing(token: _token, pin: _pairingPin);
    final session = await prepare(await file(), pair: _token);
    expect(session.tokens, isNotEmpty);
  });

  test('the typed PIN is accepted too', () async {
    harness = await TransferHarness.start();
    h().server.armPairing(token: _token, pin: _pairingPin);
    final session = await prepare(await file(), pin: _pairingPin);
    expect(session.tokens, isNotEmpty);
  });

  test('a pairing works once', () async {
    harness = await TransferHarness.start();
    h().server.armPairing(token: _token, pin: _pairingPin);
    final f = await file();
    final first = await prepare(f, pair: _token);
    expect(h().server.isPairingArmed, isFalse);

    // Once the first session is over, the same code no longer unlocks anything
    // and the receiver is open again (it has no permanent PIN here).
    await h().sender.cancel(first);
    final second = await prepare(f); // no credentials needed, none are armed
    expect(second.tokens, isNotEmpty);
  });

  test('a declined request does not use up the pairing', () async {
    var accept = false;
    harness = await TransferHarness.start(onIncoming: (t) async => accept ? t.files.keys.toSet() : null);
    h().server.armPairing(token: _token, pin: _pairingPin);
    final f = await file();
    await expectLater(prepare(f, pair: _token), status(403));
    expect(h().server.isPairingArmed, isTrue);

    accept = true;
    expect((await prepare(f, pair: _token)).tokens, isNotEmpty);
  });

  test('while armed it replaces the permanent PIN', () async {
    harness = await TransferHarness.start(pin: '9999');
    h().server.armPairing(token: _token, pin: _pairingPin);
    expect((await prepare(await file(), pair: _token)).tokens, isNotEmpty);
  });

  test('after the pairing is used the permanent PIN applies again', () async {
    harness = await TransferHarness.start(pin: '9999');
    h().server.armPairing(token: _token, pin: _pairingPin);
    final f = await file();
    final first = await prepare(f, pair: _token);
    await h().sender.cancel(first);
    await expectLater(prepare(f), status(401));
    expect((await prepare(f, pin: '9999')).tokens, isNotEmpty);
  });

  test('wrong guesses lock the sender out after 5 attempts', () async {
    harness = await TransferHarness.start();
    h().server.armPairing(token: _token, pin: _pairingPin);
    final f = await file();
    for (var i = 0; i < ReceiveServer.maxPinAttempts; i++) {
      await expectLater(prepare(f, pin: '000$i'), status(401));
    }
    // Even the right answer is refused during the lockout.
    await expectLater(prepare(f, pair: _token), status(429));
  });

  test('disarming opens the receiver again', () async {
    harness = await TransferHarness.start();
    h().server.armPairing(token: _token, pin: _pairingPin);
    h().server.disarmPairing();
    expect((await prepare(await file())).tokens, isNotEmpty);
  });

  test('a stock receiver without pairing ignores the pair parameter', () async {
    harness = await TransferHarness.start();
    expect((await prepare(await file(), pair: 'anything')).tokens, isNotEmpty);
  });
}
