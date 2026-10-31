import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/transfer/transfer_providers.dart';
import '../../l10n/l10n.dart';

/// Starts and stops the browser share and shows its link as text and QR code.
class WebShareScreen extends ConsumerStatefulWidget {
  const WebShareScreen({super.key});

  @override
  ConsumerState<WebShareScreen> createState() => _WebShareScreenState();
}

class _WebShareScreenState extends ConsumerState<WebShareScreen> {
  bool _busy = false;

  Future<void> _toggle(bool running) async {
    setState(() => _busy = true);
    try {
      final notifier = ref.read(webShareProvider.notifier);
      await (running ? notifier.stop() : notifier.start());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final status = ref.watch(webShareProvider);
    final running = status != null;

    return PopScope(
      // Leaving the screen must not leave an unencrypted server running.
      onPopInvokedWithResult: (_, _) {
        if (running) ref.read(webShareProvider.notifier).stop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.webShareTitle)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(l10n.webShareIntro),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: scheme.error),
                      const SizedBox(width: 12),
                      Expanded(child: Text(l10n.webShareWarning)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (running && status.url != null) ...[
                Center(
                  // QR codes scan best as black on white, whatever the theme.
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: QrImageView(
                      data: status.url.toString(),
                      size: 220,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    title: SelectableText(
                      status.url.toString(),
                      textDirection: TextDirection.ltr,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: status.url.toString()),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(l10n.webShareRunning, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  l10n.webShareFiles(status.fileCount),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
              ],
              FilledButton(
                style: running
                    ? FilledButton.styleFrom(
                        backgroundColor: scheme.error,
                        foregroundColor: scheme.onError,
                      )
                    : null,
                onPressed: _busy ? null : () => _toggle(running),
                child: Text(running ? l10n.webShareStop : l10n.webShareStart),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
