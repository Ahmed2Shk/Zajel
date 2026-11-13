import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/discovery/multicast_discovery.dart';
import 'package:zajel/core/transfer/protocol_models.dart';
import 'package:zajel/core/transport/pairing_payload.dart';
import 'package:zajel/core/transport/transport_manager.dart';

import '../support/transfer_harness.dart';

/// The automatic hotspot: a receiver that waits with its QR hotspot up hands
/// the pairing code to a sender on the same Wi-Fi, which then switches to the
/// hotspot without scanning.
void main() {
  PairingPayload payload({String? fingerprint}) => PairingPayload(
    ssid: 'AndroidShare_1',
    passphrase: 'password123',
    ip: '192.168.43.1',
    port: 53317,
    fingerprint: fingerprint ?? receiverIdentity.fingerprint,
    token: 'tokentokentoken12',
    pin: '4821',
    alias: 'Receiver',
  );

  DiscoveredDevice tapped({String? fingerprint}) => DiscoveredDevice(
    DeviceInfo(alias: 'Receiver', fingerprint: fingerprint ?? receiverIdentity.fingerprint),
    InternetAddress('192.168.1.20'),
  );

  group('receiver', () {
    late TransferHarness harness;

    tearDown(() => harness.dispose());

    Future<String?> ask() => harness.sender.requestDirectCode(
      address: InternetAddress.loopbackIPv4,
      port: harness.server.port,
      expectedFingerprint: receiverIdentity.fingerprint,
    );

    test('offers nothing while it hosts no hotspot', () async {
      harness = await TransferHarness.start();
      expect(await ask(), isNull);
    });

    test('hands out its pairing code while the QR hotspot is up', () async {
      harness = await TransferHarness.start();
      harness.server.directCode = payload().encode();

      final code = await ask();
      expect(PairingPayload.parse(code!).ssid, 'AndroidShare_1');

      harness.server.directCode = null; // the QR screen was closed
      expect(await ask(), isNull);
    });

    test('a permanent PIN is never bypassed', () async {
      harness = await TransferHarness.start(pin: '123456');
      harness.server.directCode = payload().encode();
      expect(await ask(), isNull);
    });

    test('a receiver without the Zajel extensions offers nothing', () async {
      harness = await TransferHarness.start(enableChunking: false);
      harness.server.directCode = payload().encode();
      expect(await ask(), isNull);
    });

    test('a device that does not answer in time counts as no offer', () async {
      harness = await TransferHarness.start();
      final code = await harness.sender.requestDirectCode(
        address: InternetAddress('10.255.255.1'), // nobody there
        port: 53317,
        expectedFingerprint: receiverIdentity.fingerprint,
        timeout: const Duration(milliseconds: 300),
      );
      expect(code, isNull);
    });
  });

  group('sender', () {
    test('an offered hotspot goes first, the Wi-Fi stays as the fallback', () async {
      final routes = await withDirectUpgrade([LanRoute(tapped())], (_) async => payload().encode());
      expect(routes.map((r) => r.kind), [TransportKind.hotspotQr, TransportKind.sameLan]);
      expect((routes.first as QrRoute).payload.token, 'tokentokentoken12');
    });

    test('no offer leaves the routes alone', () async {
      final lan = [LanRoute(tapped())];
      expect(await withDirectUpgrade(lan, (_) async => null), same(lan));
    });

    test('a code for another device is refused', () async {
      final lan = [LanRoute(tapped())];
      final other = payload(fingerprint: 'c' * 64).encode();
      expect(await withDirectUpgrade(lan, (_) async => other), same(lan));
    });

    test('a code that is not a pairing code is refused', () async {
      final lan = [LanRoute(tapped())];
      expect(await withDirectUpgrade(lan, (_) async => 'https://example.com/x'), same(lan));
      // An address on the internet must never be accepted from the network.
      final public = PairingPayload(
        ssid: 'x', passphrase: 'password123', ip: '8.8.8.8', port: 1,
        fingerprint: receiverIdentity.fingerprint, token: 'tokentokentoken12', pin: '0000', alias: 'x',
      ).encode();
      expect(await withDirectUpgrade(lan, (_) async => public), same(lan));
    });

    test('a route that is already direct is not asked again', () async {
      var asked = false;
      final qr = [QrRoute(payload())];
      final result = await withDirectUpgrade(qr, (_) async {
        asked = true;
        return payload().encode();
      });
      expect(result, same(qr));
      expect(asked, isFalse);
    });
  });

  test('discovery starts and announces without a network to announce on', () async {
    // The app must come up with Wi-Fi off: a QR hotspot needs no network.
    final discovery = MulticastDiscovery(
      self: const DeviceInfo(alias: 'x', fingerprint: 'f'),
      port: 53999,
      groupAddress: '224.0.0.167',
    );
    await discovery.start();
    discovery.announce();
    await discovery.stop();
    discovery.announce(); // after stop: harmless
  });
}
