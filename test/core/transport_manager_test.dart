import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/discovery/multicast_discovery.dart';
import 'package:zajel/core/platform/platform_api.g.dart';
import 'package:zajel/core/transfer/protocol_models.dart';
import 'package:zajel/core/transport/pairing_payload.dart';
import 'package:zajel/core/transport/transport_manager.dart';

import '../support/fake_transport_backend.dart';

DirectPeer _peer() => const DirectPeer(
  deviceAddress: 'aa:bb:cc:dd:ee:ff',
  alias: 'Sara',
  fingerprint: 'f',
  port: 53317,
);

PairingPayload _payload() => PairingPayload(
  ssid: 'AndroidShare_1',
  passphrase: 'password123',
  ip: '192.168.43.1',
  port: 53317,
  fingerprint: 'a' * 64,
  token: 'tokentokentoken12',
  pin: '4821',
  alias: 'Sara',
);

DiscoveredDevice _lan() => DiscoveredDevice(
  const DeviceInfo(alias: 'Sara', fingerprint: 'f', port: 53317),
  InternetAddress('192.168.1.20'),
);

TransportException _fail(TransportKind kind, TransportFailure reason) =>
    TransportException(kind, reason);

void main() {
  late FakeTransportBackend backend;
  late TransportManager manager;

  setUp(() {
    backend = FakeTransportBackend();
    manager = TransportManager(backend);
  });

  group('order', () {
    test('Wi-Fi Direct, then QR, then the shared Wi-Fi', () {
      final ordered = TransportManager.prioritized([
        LanRoute(_lan()),
        QrRoute(_payload()),
        DirectRoute(_peer()),
      ]);
      expect(ordered.map((r) => r.kind), [
        TransportKind.wifiDirect,
        TransportKind.hotspotQr,
        TransportKind.sameLan,
      ]);
    });

    test('the fastest working route wins', () async {
      final endpoint = await manager.establish([LanRoute(_lan()), DirectRoute(_peer())]);
      expect(endpoint.via, TransportKind.wifiDirect);
      expect(endpoint.address.address, '192.168.49.1');
      expect(endpoint.port, 53317);
      expect(backend.calls, contains('connectDirect:Sara'));
    });

    test('the shared Wi-Fi needs no setup at all', () async {
      final endpoint = await manager.establish([LanRoute(_lan())]);
      expect(endpoint.via, TransportKind.sameLan);
      expect(endpoint.address.address, '192.168.1.20');
      expect(backend.calls, isEmpty);
    });
  });

  group('fallback', () {
    test('a failed Wi-Fi Direct falls back to the shared Wi-Fi', () async {
      backend.directError = _fail(TransportKind.wifiDirect, TransportFailure.timeout);
      final endpoint = await manager.establish([DirectRoute(_peer()), LanRoute(_lan())]);
      expect(endpoint.via, TransportKind.sameLan);
      expect(backend.calls, contains('disconnectDirect'), reason: 'the failed attempt is cleaned up');
    });

    test('a failed QR join falls back to the shared Wi-Fi', () async {
      backend.joinError = _fail(TransportKind.hotspotQr, TransportFailure.timeout);
      final endpoint = await manager.establish([QrRoute(_payload()), LanRoute(_lan())]);
      expect(endpoint.via, TransportKind.sameLan);
      expect(backend.calls, contains('leave'));
    });

    test('with no working route, every reason is reported', () async {
      backend
        ..directError = _fail(TransportKind.wifiDirect, TransportFailure.busy)
        ..joinError = _fail(TransportKind.hotspotQr, TransportFailure.timeout);
      await expectLater(
        manager.establish([DirectRoute(_peer()), QrRoute(_payload())]),
        throwsA(
          isA<AllTransportsFailed>().having(
            (e) => e.failures.map((f) => f.reason).toList(),
            'reasons',
            [TransportFailure.busy, TransportFailure.timeout],
          ),
        ),
      );
    });

    test('with no routes at all it fails cleanly', () async {
      await expectLater(manager.establish([]), throwsA(isA<AllTransportsFailed>()));
    });
  });

  group('preconditions give a specific error', () {
    Future<TransportFailure> reasonOf(Future<Object?> Function() action) async {
      try {
        await action();
      } on AllTransportsFailed catch (e) {
        return e.failures.single.reason;
      } on TransportException catch (e) {
        return e.reason;
      }
      fail('expected a failure');
    }

    test('permission denied', () async {
      backend.permissions = false;
      expect(await reasonOf(() => manager.establish([QrRoute(_payload())])), TransportFailure.permissionDenied);
      expect(backend.calls, isNot(contains('join:AndroidShare_1')));
    });

    test('location off (older Android)', () async {
      backend.location = false;
      expect(await reasonOf(() => manager.establish([DirectRoute(_peer())])), TransportFailure.locationOff);
    });

    test('Wi-Fi off', () async {
      backend.wifi = false;
      expect(await reasonOf(() => manager.establish([QrRoute(_payload())])), TransportFailure.wifiOff);
    });

    test('the same checks guard hosting a hotspot', () async {
      backend.location = false;
      expect(await reasonOf(manager.startHotspot), TransportFailure.locationOff);
      expect(backend.calls, isNot(contains('startHotspot')));
    });

    test('and advertising over Wi-Fi Direct', () async {
      backend.permissions = false;
      expect(
        await reasonOf(() => manager.advertiseDirect(alias: 'a', fingerprint: 'f', port: 1)),
        TransportFailure.permissionDenied,
      );
    });
  });

  group('QR pairing', () {
    test('carries the token and PIN to the sender', () async {
      final endpoint = await manager.establish([QrRoute(_payload())]);
      expect(endpoint.via, TransportKind.hotspotQr);
      expect(endpoint.address.address, '192.168.43.1');
      expect(endpoint.fingerprint, 'a' * 64);
      expect(endpoint.pairToken, 'tokentokentoken12');
      expect(endpoint.pin, '4821');
      expect(backend.calls, contains('join:AndroidShare_1'));
    });

    test('release leaves the network it joined', () async {
      final endpoint = await manager.establish([QrRoute(_payload())]);
      await manager.release(endpoint);
      expect(backend.calls.last, 'leave');
    });

    test('release of a Wi-Fi Direct route disconnects the group', () async {
      final endpoint = await manager.establish([DirectRoute(_peer())]);
      await manager.release(endpoint);
      expect(backend.calls.last, 'disconnectDirect');
    });

    test('release of the shared Wi-Fi does nothing', () async {
      final endpoint = await manager.establish([LanRoute(_lan())]);
      await manager.release(endpoint);
      expect(backend.calls, isEmpty);
    });
  });

  group('hosting a hotspot', () {
    test('finds the new address that appears after it starts', () async {
      var started = false;
      final custom = TransportManager(
        backend,
        addressPoll: const Duration(milliseconds: 5),
        listAddresses: () async {
          started = backend.calls.contains('startHotspot');
          return [
            InternetAddress('192.168.1.7'),
            if (started) InternetAddress('192.168.43.1'),
          ];
        },
      );
      final hosted = await custom.startHotspot();
      expect(hosted.address.address, '192.168.43.1');
      expect(hosted.credentials.ssid, 'AndroidShare_1');
    });

    test('waits for an interface that shows up late', () async {
      var polls = 0;
      final custom = TransportManager(
        backend,
        addressPoll: const Duration(milliseconds: 5),
        listAddresses: () async {
          polls++;
          return [
            InternetAddress('192.168.1.7'),
            if (backend.calls.contains('startHotspot') && polls > 6) InternetAddress('10.5.5.1'),
          ];
        },
      );
      expect((await custom.startHotspot()).address.address, '10.5.5.1');
    });

    test('gives up and stops the hotspot if no address appears', () async {
      final custom = TransportManager(
        backend,
        addressWait: const Duration(milliseconds: 60),
        addressPoll: const Duration(milliseconds: 5),
        listAddresses: () async => [InternetAddress('192.168.1.7')],
      );
      await expectLater(
        custom.startHotspot(),
        throwsA(isA<TransportException>().having((e) => e.reason, 'reason', TransportFailure.timeout)),
      );
      expect(backend.calls, contains('stopHotspot'));
    });

    test('a hotspot the system refuses is reported as such', () async {
      backend.hotspotError = _fail(TransportKind.hotspotQr, TransportFailure.busy);
      final custom = TransportManager(backend, listAddresses: () async => []);
      await expectLater(
        custom.startHotspot(),
        throwsA(isA<TransportException>().having((e) => e.reason, 'reason', TransportFailure.busy)),
      );
    });
  });

  group('Wi-Fi Direct', () {
    test('advertising starts the receiver side', () async {
      await manager.advertiseDirect(alias: 'Ahmed', fingerprint: 'f', port: 53317);
      expect(backend.calls, contains('startDirect:Ahmed'));
      await manager.stopAdvertisingDirect();
      expect(backend.calls.last, 'stopDirect');
    });

    test('finds peers', () async {
      final peers = await manager.findDirectPeers(timeout: const Duration(milliseconds: 10));
      expect(peers.single.alias, 'Sara');
    });
  });

  group('error codes from the phone', () {
    test('each code maps to its own failure', () {
      expect(TransportFailure.fromCode('permission_denied'), TransportFailure.permissionDenied);
      expect(TransportFailure.fromCode('location_off'), TransportFailure.locationOff);
      expect(TransportFailure.fromCode('wifi_off'), TransportFailure.wifiOff);
      expect(TransportFailure.fromCode('unsupported'), TransportFailure.unsupported);
      expect(TransportFailure.fromCode('busy'), TransportFailure.busy);
      expect(TransportFailure.fromCode('timeout'), TransportFailure.timeout);
      expect(TransportFailure.fromCode('anything else'), TransportFailure.failed);
      expect(TransportFailure.fromCode(null), TransportFailure.failed);
    });

    test('the real backend turns platform errors into transport errors', () async {
      final backend = PigeonTransportBackend(_ThrowingApi(PlatformException(code: 'wifi_off', message: 'off')));
      await expectLater(
        backend.joinNetwork('a', 'b'),
        throwsA(isA<TransportException>().having((e) => e.reason, 'reason', TransportFailure.wifiOff)),
      );
      await expectLater(
        backend.startHotspot(),
        throwsA(isA<TransportException>().having((e) => e.kind, 'kind', TransportKind.hotspotQr)),
      );
      await expectLater(
        backend.connectDirect(_peer()),
        throwsA(isA<TransportException>().having((e) => e.kind, 'kind', TransportKind.wifiDirect)),
      );
    });
  });
}

class _ThrowingApi implements TransportApi {
  _ThrowingApi(this.error);

  final PlatformException error;

  @override
  Future<void> joinNetwork(String ssid, String passphrase) => Future.error(error);
  @override
  Future<NativeNetworkInfo> startHotspot() => Future.error(error);
  @override
  Future<String> connectDirect(NativeDirectPeer peer) => Future.error(error);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
