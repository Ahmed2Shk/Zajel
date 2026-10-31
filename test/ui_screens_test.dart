import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zajel/app.dart';
import 'package:zajel/core/discovery/multicast_discovery.dart';
import 'package:zajel/core/router/app_router.dart';
import 'package:zajel/core/transfer/protocol_models.dart';
import 'package:zajel/core/transfer/send_client.dart';
import 'package:zajel/core/transfer/transfer_providers.dart';
import 'package:zajel/features/history/history_store.dart';
import 'package:zajel/features/settings/app_settings.dart';

import 'support/transfer_harness.dart';

class _FakeSendJob extends SendJobNotifier {
  _FakeSendJob(this._initial);

  final SendJob _initial;

  @override
  SendJob build() => _initial;
}

/// Real file IO does not run inside a widget test's fake clock, so it goes
/// through `runAsync`.
Future<SendFile> _makeFile(WidgetTester tester, String name, int size) async {
  final dir = Directory.systemTemp.createTempSync('zajel_ui_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = await tester.runAsync(() async {
    final written = await writeTestFile(dir, name, size);
    return SendFile.fromPath(written.path, id: name);
  });
  return file!;
}

DiscoveredDevice _device(String alias, String fingerprint) => DiscoveredDevice(
  DeviceInfo(alias: alias, fingerprint: fingerprint, deviceModel: 'Pixel 8'),
  InternetAddress('192.168.1.20'),
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  List<Override> overrides = const [],
  Locale? locale,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final instance = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(instance),
      localSendServiceProvider.overrideWith((ref) async => null),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  // A tall phone, so lazily built lists show all their rows.
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (locale != null) {
    container.read(appSettingsProvider.notifier).setLocale(locale);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ZajelApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _go(WidgetTester tester, ProviderContainer container, String route) async {
  container.read(appRouterProvider).go(route);
  // Some screens animate forever, so never wait for them to settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  // The discovery screen starts a 5 second timer; let it run out so the test
  // does not end with a pending timer.
  if (route == AppRoutes.discovery) {
    await tester.pump(const Duration(seconds: 6));
  }
}

void main() {
  group('home', () {
    testWidgets('shows the two actions and an empty history message', (tester) async {
      await _pump(tester);
      expect(find.text('إرسال'), findsOneWidget);
      expect(find.text('استقبال'), findsOneWidget);
      expect(find.text('لا توجد عمليات نقل بعد'), findsOneWidget);
      expect(find.text('جاهز للإرسال والاستقبال'), findsOneWidget);
    });

    testWidgets('lists recent transfers with direction and size', (tester) async {
      final entries = '[{"name":"trip.mp4","size":5242880,"peer":"Sara","direction":"received","at":1700000000000},'
          '{"name":"notes.pdf","size":2048,"peer":"Omar","direction":"sent","at":1700000100000}]';
      await _pump(tester, prefs: {'history': entries});
      expect(find.text('trip.mp4'), findsOneWidget);
      expect(find.text('notes.pdf'), findsOneWidget);
      expect(find.textContaining('5.0 MB'), findsOneWidget);
      expect(find.textContaining('Sara'), findsOneWidget);
      expect(find.text('لا توجد عمليات نقل بعد'), findsNothing);
    });

    testWidgets('a damaged history is ignored instead of crashing', (tester) async {
      await _pump(tester, prefs: {'history': '{not json'});
      expect(find.text('لا توجد عمليات نقل بعد'), findsOneWidget);
    });

    testWidgets('history can be cleared', (tester) async {
      await _pump(tester, prefs: {
        'history': '[{"name":"a.txt","size":1,"peer":"","direction":"sent","at":1700000000000}]',
      });
      expect(find.text('a.txt'), findsOneWidget);
      await tester.tap(find.text('مسح'));
      await tester.pumpAndSettle();
      expect(find.text('a.txt'), findsNothing);
    });

    testWidgets('English layout is left to right', (tester) async {
      await _pump(tester, locale: const Locale('en'));
      expect(find.text('Send'), findsOneWidget);
      expect(Directionality.of(tester.element(find.text('Send'))), TextDirection.ltr);
    });
  });

  group('history store', () {
    test('keeps at most 50 entries, newest first', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(historyProvider.notifier);
      for (var i = 0; i < 60; i++) {
        notifier.add([
          HistoryEntry(
            name: 'f$i',
            size: i,
            peer: '',
            direction: TransferDirection.sent,
            at: DateTime(2026, 1, 1, 0, i),
          ),
        ]);
      }
      final list = container.read(historyProvider);
      expect(list, hasLength(HistoryNotifier.maxEntries));
      expect(list.first.name, 'f59');
      expect(list.last.name, 'f10');
    });
  });

  group('file picker', () {
    testWidgets('shows the tabs and a disabled send bar when empty', (tester) async {
      final container = await _pump(tester);
      await _go(tester, container, AppRoutes.filePicker);
      for (final tab in ['الصور', 'الفيديو', 'التطبيقات', 'الملفات']) {
        expect(find.text(tab), findsOneWidget, reason: tab);
      }
      expect(find.text('لم تختر أي ملف بعد'), findsOneWidget);
      final send = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(send.onPressed, isNull);
    });

    testWidgets('a selection shows its files and enables sending', (tester) async {
      final file = await _makeFile(tester, 'holiday.zip', 3 * 1024 * 1024);

      final container = await _pump(tester);
      container.read(selectedFilesProvider.notifier).set([file]);
      await _go(tester, container, AppRoutes.filePicker);

      expect(find.text('holiday.zip'), findsOneWidget);
      expect(find.textContaining('3.0 MB'), findsWidgets);
      expect(find.text('إرسال (1)'), findsOneWidget);
      final send = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(send.onPressed, isNotNull);
    });

    testWidgets('apps tab says apps are Android-only on other platforms', (tester) async {
      final container = await _pump(tester);
      await _go(tester, container, AppRoutes.filePicker);
      await tester.tap(find.text('التطبيقات'));
      await tester.pumpAndSettle();
      expect(find.text('اختيار التطبيقات متاح على أندرويد فقط'), findsOneWidget);
    });
  });

  group('discovery', () {
    testWidgets('shows the searching state with no devices', (tester) async {
      final container = await _pump(tester, overrides: [
        nearbyDevicesProvider.overrideWith((ref) => Stream.value(const <DiscoveredDevice>[])),
      ]);
      await _go(tester, container, AppRoutes.discovery);
      expect(find.text('البحث عن أجهزة مجاورة…'), findsOneWidget);
    });

    testWidgets('shows found devices as bubbles', (tester) async {
      final container = await _pump(tester, overrides: [
        nearbyDevicesProvider.overrideWith(
          (ref) => Stream.value([_device('Sara phone', 'a'), _device('Office PC', 'b')]),
        ),
      ]);
      await _go(tester, container, AppRoutes.discovery);
      expect(find.text('Sara phone'), findsOneWidget);
      expect(find.text('Office PC'), findsOneWidget);
      expect(find.text('تم العثور على 2'), findsOneWidget);
    });

    testWidgets('tapping a device with nothing selected asks to pick files', (tester) async {
      final container = await _pump(tester, overrides: [
        nearbyDevicesProvider.overrideWith((ref) => Stream.value([_device('Sara phone', 'a')])),
      ]);
      await _go(tester, container, AppRoutes.discovery);
      await tester.tap(find.text('Sara phone'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('اختيار الملفات'), findsOneWidget); // landed on the picker
    });

    testWidgets('many devices stay inside the screen', (tester) async {
      final devices = [for (var i = 0; i < 8; i++) _device('Device $i', 'f$i')];
      final container = await _pump(tester, overrides: [
        nearbyDevicesProvider.overrideWith((ref) => Stream.value(devices)),
      ]);
      await _go(tester, container, AppRoutes.discovery);
      expect(tester.takeException(), isNull);
      final screen = tester.getRect(find.byType(Scaffold));
      for (var i = 0; i < 8; i++) {
        final rect = tester.getRect(find.text('Device $i'));
        expect(screen.contains(rect.center), isTrue, reason: 'Device $i is off screen');
      }
    });
  });

  group('transfer progress', () {
    testWidgets('shows speed, per-file state and overall progress', (tester) async {
      final a = await _makeFile(tester, 'done.bin', 1000);
      final b = await _makeFile(tester, 'active.bin', 2000);
      final c = await _makeFile(tester, 'waiting.bin', 3000);

      final job = SendJob(
        status: SendStatus.sending,
        target: _device('Sara phone', 'a'),
        files: [a, b, c],
        sentPerFile: {a.id: 1000, b.id: 1000},
        bytesPerSecond: 5 * 1024 * 1024,
      );
      final container = await _pump(tester, overrides: [
        sendJobProvider.overrideWith(() => _FakeSendJob(job)),
      ]);
      await _go(tester, container, AppRoutes.transfer);

      expect(find.text('Sara phone'), findsOneWidget);
      expect(find.text('5.0'), findsOneWidget);
      expect(find.text('MB/s'), findsOneWidget);
      expect(find.text('تم النقل بنجاح · 1000 B'), findsOneWidget);
      expect(find.text('جاري الإرسال · 2.0 KB'), findsOneWidget);
      expect(find.text('قيد الانتظار · 2.9 KB'), findsOneWidget);
      expect(find.text('50%'), findsWidgets); // active file and overall (2000/6000 -> 33%)
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('a declined transfer explains itself', (tester) async {
      final job = SendJob(
        status: SendStatus.failed,
        target: _device('Sara phone', 'a'),
        error: 'declined',
      );
      final container = await _pump(tester, overrides: [
        sendJobProvider.overrideWith(() => _FakeSendJob(job)),
      ]);
      await _go(tester, container, AppRoutes.transfer);
      expect(find.text('رفض الجهاز الآخر الطلب'), findsOneWidget);
    });

    testWidgets('a finished send shows the summary', (tester) async {
      final a = await _makeFile(tester, 'a.bin', 1024 * 1024);
      final job = SendJob(
        status: SendStatus.done,
        target: _device('Sara phone', 'a'),
        files: [a],
        sentPerFile: {a.id: a.size},
      );
      final container = await _pump(tester, overrides: [
        sendJobProvider.overrideWith(() => _FakeSendJob(job)),
      ]);
      await _go(tester, container, AppRoutes.done);
      expect(find.text('تم النقل'), findsWidgets);
      expect(find.text('1 ملف · 1.0 MB'), findsOneWidget);
      expect(find.text('Sara phone'), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('shows the saved device name and PIN state', (tester) async {
      final container = await _pump(tester, prefs: {'deviceName': 'Ahmed phone'});
      await _go(tester, container, AppRoutes.settings);
      expect(find.text('Ahmed phone'), findsOneWidget);
      expect(find.text('بدون رمز'), findsOneWidget);
    });
  });
}
