import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zajel/app.dart';
import 'package:zajel/core/discovery/multicast_discovery.dart';
import 'package:zajel/core/router/app_router.dart';
import 'package:zajel/core/transfer/localsend_service.dart';
import 'package:zajel/core/transfer/protocol_models.dart';
import 'package:zajel/core/transfer/send_client.dart';
import 'package:zajel/core/transfer/transfer_providers.dart';
import 'package:zajel/core/transport/pairing_payload.dart';
import 'package:zajel/core/transport/transport_manager.dart';
import 'package:zajel/features/qr/qr_scan_screen.dart';
import 'package:zajel/features/settings/app_settings.dart';

import 'support/fake_transport_backend.dart';
import 'support/transfer_harness.dart';

const _qrPort = 53411;

PairingPayload _payload() => PairingPayload(
  ssid: 'AndroidShare_1',
  passphrase: 'password123',
  ip: '192.168.43.1',
  port: 53317,
  fingerprint: 'a' * 64,
  token: 'tokentokentoken12',
  pin: '4821',
  alias: 'Sara phone',
);

TransportManager _manager(FakeTransportBackend backend) => TransportManager(
  backend,
  addressPoll: const Duration(milliseconds: 5),
  listAddresses: () async => [
    InternetAddress('192.168.1.7'),
    // The hotspot's interface appears once it has started.
    if (backend.calls.contains('startHotspot')) InternetAddress('192.168.43.1'),
  ],
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  LocalSendService? service,
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      localSendServiceProvider.overrideWith((ref) async => service),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const ZajelApp()));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _go(WidgetTester tester, ProviderContainer container, String route) async {
  container.read(appRouterProvider).go(route);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// A real service on loopback-friendly settings, started outside the test's
/// fake clock.
Future<LocalSendService> _startService(WidgetTester tester) async {
  final dir = Directory.systemTemp.createTempSync('zajel_qr_dl_');
  final service = (await tester.runAsync(
    () => LocalSendService.start(
      identity: receiverIdentity,
      alias: 'Ahmed phone',
      downloadDirectory: dir,
      port: _qrPort,
    ),
  ))!;
  addTearDown(() async {
    await tester.runAsync(service.stop);
    dir.deleteSync(recursive: true);
  });
  return service;
}

Future<SendFile> _makeFile(WidgetTester tester, String name, int size) async {
  final dir = Directory.systemTemp.createTempSync('zajel_qr_src_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return (await tester.runAsync(() async {
    final written = await writeTestFile(dir, name, size);
    return SendFile.fromPath(written.path, id: name);
  }))!;
}

/// Stands in for the camera: each button "scans" one code.
QrScannerBuilder _fakeScanner(Map<String, String> codes) =>
    (context, onCode) => Column(
      children: [
        for (final entry in codes.entries)
          TextButton(onPressed: () => onCode(entry.value), child: Text(entry.key)),
      ],
    );

void main() {
  group('QR show', () {
    testWidgets('on a device without the transports it says so', (tester) async {
      final container = await _pump(tester);
      await _go(tester, container, AppRoutes.qrShow);
      expect(find.text('هذا الجهاز لا يدعم هذه الميزة.'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
    });

    testWidgets('shows a QR code and PIN, and arms the one-time pairing', (tester) async {
      final service = await _startService(tester);
      final backend = FakeTransportBackend();
      final container = await _pump(tester, service: service, overrides: [
        transportManagerProvider.overrideWithValue(_manager(backend)),
      ]);
      await _go(tester, container, AppRoutes.qrShow);
      await tester.pump(const Duration(milliseconds: 200));

      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      final payload = PairingPayload.parse((qr.key! as ValueKey<String>).value);
      expect(payload.fingerprint, service.device.fingerprint, reason: 'the scanner can verify it');
      expect(payload.ip, '192.168.43.1');
      expect(payload.port, _qrPort);
      expect(payload.ssid, 'AndroidShare_1');
      expect(payload.alias, 'Ahmed phone');
      expect(find.text(payload.pin), findsOneWidget);
      expect(service.isPairingArmed, isTrue);
      expect(backend.calls, contains('startHotspot'));

      // Leaving the screen takes the hotspot and the pairing away.
      await _go(tester, container, AppRoutes.home);
      await tester.pump(const Duration(milliseconds: 100));
      expect(service.isPairingArmed, isFalse);
      expect(backend.calls, contains('stopHotspot'));
    });

    for (final (name, configure, message) in <(String, void Function(FakeTransportBackend), String)>[
      ('permission denied', (b) => b.permissions = false, 'اسمح بإذن «الأجهزة القريبة» (أو «الموقع» على أندرويد 12 وما قبله) ثم أعد المحاولة.'),
      ('location off', (b) => b.location = false, 'شغّل خدمة الموقع في الجهاز، فهي مطلوبة على أندرويد 12 وما قبله.'),
      ('Wi-Fi off', (b) => b.wifi = false, 'شغّل الواي فاي (لا يلزم الاتصال بشبكة).'),
    ]) {
      testWidgets('$name gets its own message and retry works', (tester) async {
        final service = await _startService(tester);
        final backend = FakeTransportBackend();
        configure(backend);
        final container = await _pump(tester, service: service, overrides: [
          transportManagerProvider.overrideWithValue(_manager(backend)),
        ]);
        await _go(tester, container, AppRoutes.qrShow);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text(message), findsOneWidget);
        expect(find.byType(QrImageView), findsNothing);

        // The user fixes it, then retries.
        backend
          ..permissions = true
          ..location = true
          ..wifi = true;
        await tester.tap(find.text('إعادة المحاولة'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(QrImageView), findsOneWidget);
      });
    }

    testWidgets('a busy hotspot is explained', (tester) async {
      final service = await _startService(tester);
      final backend = FakeTransportBackend()
        ..hotspotError = const TransportException(TransportKind.hotspotQr, TransportFailure.busy);
      final container = await _pump(tester, service: service, overrides: [
        transportManagerProvider.overrideWithValue(_manager(backend)),
      ]);
      await _go(tester, container, AppRoutes.qrShow);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('الواي فاي مشغول'), findsOneWidget);
      expect(service.isPairingArmed, isFalse, reason: 'nothing is armed when the hotspot failed');
    });
  });

  group('QR scan', () {
    final scanner = _fakeScanner({'SCAN_BAD': 'https://example.com', 'SCAN_GOOD': _payload().encode()});

    testWidgets('a code that is not Zajel is refused and scanning continues', (tester) async {
      final container = await _pump(tester, overrides: [qrScannerBuilderProvider.overrideWithValue(scanner)]);
      await _go(tester, container, AppRoutes.qrScan);
      await tester.tap(find.text('SCAN_BAD'));
      await tester.pump();
      expect(find.text('هذا الرمز ليس رمز زاجل'), findsOneWidget);
      expect(find.text('SCAN_GOOD'), findsOneWidget, reason: 'still on the scanner');
    });

    testWidgets('a valid code with no files selected sends you to pick files', (tester) async {
      final container = await _pump(tester, overrides: [qrScannerBuilderProvider.overrideWithValue(scanner)]);
      await _go(tester, container, AppRoutes.qrScan);
      await tester.tap(find.text('SCAN_GOOD'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('اختيار الملفات'), findsOneWidget);
    });

    testWidgets('a valid code with files joins the hotspot and starts sending', (tester) async {
      final backend = FakeTransportBackend();
      final container = await _pump(tester, overrides: [
        qrScannerBuilderProvider.overrideWithValue(scanner),
        transportManagerProvider.overrideWithValue(_manager(backend)),
      ]);
      container.read(selectedFilesProvider.notifier).set([await _makeFile(tester, 'a.bin', 2048)]);
      await _go(tester, container, AppRoutes.qrScan);
      await tester.tap(find.text('SCAN_GOOD'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(backend.calls, contains('join:AndroidShare_1'));
      final job = container.read(sendJobProvider);
      expect(job.target?.info.alias, 'Sara phone');
      expect(job.target?.info.fingerprint, 'a' * 64, reason: 'the fingerprint from the QR is what is verified');
      expect(find.text('Sara phone'), findsOneWidget); // on the progress screen
    });

    testWidgets('a join that cannot start explains why on the progress screen', (tester) async {
      final backend = FakeTransportBackend()..permissions = false;
      final container = await _pump(tester, overrides: [
        qrScannerBuilderProvider.overrideWithValue(scanner),
        transportManagerProvider.overrideWithValue(_manager(backend)),
      ]);
      container.read(selectedFilesProvider.notifier).set([await _makeFile(tester, 'a.bin', 2048)]);
      await _go(tester, container, AppRoutes.qrScan);
      await tester.tap(find.text('SCAN_GOOD'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.textContaining('اسمح بإذن «الأجهزة القريبة»'), findsOneWidget);
      expect(backend.calls, isNot(contains('join:AndroidShare_1')));
    });
  });

  group('discovery', () {
    testWidgets('suggests a QR code after 5 seconds with nobody found', (tester) async {
      final container = await _pump(tester, overrides: [
        nearbyDevicesProvider.overrideWith((ref) => Stream.value(const <DiscoveredDevice>[])),
      ]);
      await _go(tester, container, AppRoutes.discovery);
      expect(find.text('لم نجد أجهزة. جرّب رمز QR للاتصال بدون راوتر.'), findsNothing);

      await tester.pump(const Duration(seconds: 4));
      expect(find.text('لم نجد أجهزة. جرّب رمز QR للاتصال بدون راوتر.'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('لم نجد أجهزة. جرّب رمز QR للاتصال بدون راوتر.'), findsOneWidget);
    });

    testWidgets('does not suggest it when a device is found', (tester) async {
      final container = await _pump(tester, overrides: [
        nearbyDevicesProvider.overrideWith(
          (ref) => Stream.value([
            DiscoveredDevice(
              const DeviceInfo(alias: 'Sara phone', fingerprint: 'f'),
              InternetAddress('192.168.1.20'),
            ),
          ]),
        ),
      ]);
      await _go(tester, container, AppRoutes.discovery);
      await tester.pump(const Duration(seconds: 7));
      expect(find.text('لم نجد أجهزة. جرّب رمز QR للاتصال بدون راوتر.'), findsNothing);
      expect(find.text('Sara phone'), findsOneWidget);
    });

    testWidgets('Wi-Fi Direct is offered only where the phone supports it', (tester) async {
      final container = await _pump(tester);
      await _go(tester, container, AppRoutes.discovery);
      expect(find.text('Wi-Fi Direct'), findsNothing);
      await tester.pump(const Duration(seconds: 6)); // let the suggestion timer end
    });

    testWidgets('a Wi-Fi Direct search adds receivers to the radar', (tester) async {
      final backend = FakeTransportBackend();
      final container = await _pump(tester, overrides: [
        transportManagerProvider.overrideWithValue(_manager(backend)),
        nearbyDevicesProvider.overrideWith((ref) => Stream.value(const <DiscoveredDevice>[])),
      ]);
      await _go(tester, container, AppRoutes.discovery);
      await tester.tap(find.text('Wi-Fi Direct'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('البحث عبر Wi-Fi Direct'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Sara'), findsOneWidget);
      expect(find.text('مباشر'), findsOneWidget, reason: 'marked as found over Wi-Fi Direct');
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('a Wi-Fi Direct search that cannot start says why', (tester) async {
      final backend = FakeTransportBackend()..permissions = false;
      final container = await _pump(tester, overrides: [
        transportManagerProvider.overrideWithValue(_manager(backend)),
        nearbyDevicesProvider.overrideWith((ref) => Stream.value(const <DiscoveredDevice>[])),
      ]);
      await _go(tester, container, AppRoutes.discovery);
      await tester.tap(find.text('Wi-Fi Direct'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('البحث عبر Wi-Fi Direct'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.textContaining('اسمح بإذن «الأجهزة القريبة»'), findsWidgets);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('becoming visible advertises this device', (tester) async {
      final service = await _startService(tester);
      final backend = FakeTransportBackend();
      final container = await _pump(tester, service: service, overrides: [
        transportManagerProvider.overrideWithValue(_manager(backend)),
      ]);
      await _go(tester, container, AppRoutes.discovery);
      await tester.tap(find.text('Wi-Fi Direct'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byType(Switch));
      await tester.pump(const Duration(milliseconds: 300));
      expect(backend.calls, contains('startDirect:Ahmed phone'));
      await tester.pump(const Duration(seconds: 6));
    });
  });
}
