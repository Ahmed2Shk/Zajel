import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/logging/app_log.dart';
import '../../core/logging/log_providers.dart';
import '../../core/platform/platform_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/transfer/transfer_providers.dart';
import '../../l10n/l10n.dart';
import 'app_settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<String?> _askText(
    BuildContext context, {
    required String title,
    String? hint,
    String? initial,
    bool digitsOnly = false,
    String? clearLabel,
  }) {
    final controller = TextEditingController(text: initial);
    final l10n = context.l10n;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hint != null) ...[Text(hint), const SizedBox(height: 12)],
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: digitsOnly ? TextInputType.number : null,
              inputFormatters: [
                if (digitsOnly) FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(digitsOnly ? 8 : 32),
              ],
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
          ],
        ),
        actions: [
          if (clearLabel != null)
            TextButton(
              onPressed: () => Navigator.of(context).pop(''),
              child: Text(clearLabel),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  /// Saves the log where the user chooses. Nothing is uploaded.
  Future<void> _exportLogs(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final log = ref.read(appLogProvider);
    final body = log?.readAll() ?? '';
    if (body.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.logsEmpty)));
      return;
    }
    final text =
        '${AppLog.environmentSummary(locale: ref.read(appSettingsProvider).locale.languageCode)}\n$body';
    try {
      final saved = await FilePicker.saveFile(
        fileName: 'zajel-log.txt',
        bytes: Uint8List.fromList(utf8.encode(text)),
        mimeType: 'text/plain',
      );
      if (saved != null) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.logsSaved)));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.logsExportFailed)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final service = ref.watch(localSendServiceProvider).value;
    final deviceInfo = ref.watch(nativeDeviceInfoProvider);
    final titleStyle = Theme.of(context).textTheme.titleMedium;

    // Android keeps files in the app's own folder (no storage permission).
    final canPickFolder = !kIsWeb && !Platform.isAndroid && !Platform.isIOS;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(l10n.language, style: titleStyle),
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
            Text(l10n.theme, style: titleStyle),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: ThemeMode.dark, label: Text(l10n.themeDark)),
                ButtonSegment(value: ThemeMode.light, label: Text(l10n.themeLight)),
                ButtonSegment(value: ThemeMode.system, label: Text(l10n.themeSystem)),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (value) => notifier.setThemeMode(value.first),
            ),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(l10n.deviceName),
                subtitle: Text(
                  settings.deviceName ?? service?.device.alias ?? l10n.defaultValue,
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final name = await _askText(
                    context,
                    title: l10n.editDeviceName,
                    initial: settings.deviceName ?? service?.device.alias,
                    clearLabel: l10n.defaultValue,
                  );
                  if (name != null) notifier.setDeviceName(name);
                },
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(l10n.downloadFolder),
                subtitle: Text(
                  settings.downloadPath ??
                      service?.downloadDirectory.path ??
                      l10n.defaultValue,
                  textDirection: TextDirection.ltr,
                ),
                trailing: canPickFolder ? const Icon(Icons.edit_outlined) : null,
                onTap: canPickFolder
                    ? () async {
                        final path = await FilePicker.getDirectoryPath(
                          dialogTitle: l10n.chooseFolder,
                        );
                        if (path != null) notifier.setDownloadPath(path);
                      }
                    : () => ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.downloadFolderFixed)),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(l10n.securityPin),
                subtitle: Text(
                  settings.receivePin == null ? l10n.pinNotSet : '••••',
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final pin = await _askText(
                    context,
                    title: l10n.securityPin,
                    hint: l10n.pinDialogHint,
                    digitsOnly: true,
                    clearLabel: settings.receivePin == null ? null : l10n.clearPin,
                  );
                  if (pin != null) notifier.setReceivePin(pin);
                },
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(l10n.exportLogs),
                subtitle: Text(l10n.exportLogsSub),
                onTap: () => _exportLogs(context, ref),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l10n.clearLogs,
                  onPressed: () {
                    ref.read(appLogProvider)?.clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.logsEmpty)),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
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
