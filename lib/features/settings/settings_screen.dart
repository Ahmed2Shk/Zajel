import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/platform_providers.dart';
import '../../core/router/app_router.dart';
import '../../l10n/l10n.dart';
import 'app_settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final deviceInfo = ref.watch(nativeDeviceInfoProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(l10n.language, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'ar', label: Text(l10n.languageArabic)),
                ButtonSegment(value: 'en', label: Text(l10n.languageEnglish)),
              ],
              selected: {settings.locale.languageCode},
              onSelectionChanged: (value) =>
                  notifier.setLocale(Locale(value.first)),
            ),
            const SizedBox(height: 24),
            Text(l10n.theme, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text(l10n.themeDark),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text(l10n.themeLight),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text(l10n.themeSystem),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (value) =>
                  notifier.setThemeMode(value.first),
            ),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: const Icon(Icons.speed),
                title: Text(l10n.benchmarkTitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.benchmark),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                title: Text(l10n.device),
                subtitle: Text(
                  deviceInfo.when(
                    data: (info) => '${info.model} (API ${info.sdkInt})',
                    loading: () => '…',
                    error: (_, _) => l10n.unavailable,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
