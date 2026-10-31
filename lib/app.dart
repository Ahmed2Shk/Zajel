import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/receive/incoming_transfer_host.dart';
import 'features/settings/app_settings.dart';
import 'l10n/l10n.dart';

class ZajelApp extends ConsumerWidget {
  const ZajelApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appName,
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) =>
          IncomingTransferHost(child: child ?? const SizedBox.shrink()),
      theme: AppTheme.light(settings.locale),
      darkTheme: AppTheme.dark(settings.locale),
      themeMode: settings.themeMode,
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
