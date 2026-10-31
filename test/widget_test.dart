import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/transfer/transfer_providers.dart';
import 'package:zajel/app.dart';
import 'package:zajel/core/router/app_router.dart';
import 'package:zajel/features/settings/app_settings.dart';

Future<ProviderContainer> _pumpApp(WidgetTester tester) async {
  // No sockets in widget tests: the LAN service is replaced by nothing.
  final container = ProviderContainer(
    overrides: [localSendServiceProvider.overrideWith((ref) async => null)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const ZajelApp(),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('home opens in Arabic, RTL, dark theme', (tester) async {
    await _pumpApp(tester);

    expect(find.text('إرسال'), findsOneWidget);
    expect(find.text('استقبال'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('إرسال'))),
      TextDirection.rtl,
    );
    expect(
      Theme.of(tester.element(find.text('إرسال'))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('switching language to English flips to LTR', (tester) async {
    final container = await _pumpApp(tester);

    container.read(appSettingsProvider.notifier).setLocale(const Locale('en'));
    await tester.pumpAndSettle();

    expect(find.text('Send'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('Send'))),
      TextDirection.ltr,
    );
  });

  testWidgets('every route builds', (tester) async {
    final container = await _pumpApp(tester);
    final router = container.read(appRouterProvider);

    for (final route in [
      AppRoutes.filePicker,
      AppRoutes.discovery,
      AppRoutes.qrShow,
      AppRoutes.qrScan,
      AppRoutes.transfer,
      AppRoutes.done,
      AppRoutes.settings,
      AppRoutes.benchmark,
    ]) {
      router.go(route);
      // The discovery screen shows a spinner forever, so it never "settles".
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: route);
      expect(find.byType(Scaffold), findsOneWidget, reason: route);
    }
  });
}
