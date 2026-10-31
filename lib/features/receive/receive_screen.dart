import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/transfer/receive_tracker.dart';
import '../../core/transfer/transfer_providers.dart';
import '../../core/widgets/transfer_widgets.dart';
import '../../core/widgets/zajel_widgets.dart';
import '../../l10n/l10n.dart';

/// The receiving side of a transfer: who is sending, how fast, which files are
/// done, and where they were saved.
class ReceiveScreen extends ConsumerWidget {
  const ReceiveScreen({super.key});

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    ref.read(localSendServiceProvider).value?.receive.dismiss();
    if (context.mounted) context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final success = context.zajelColors.success;
    final service = ref.watch(localSendServiceProvider).value;
    final snapshot = ref.watch(receiveSnapshotProvider).value;

    if (snapshot == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.receivingTitle)),
        body: SafeArea(
          child: Center(
            child: FilledButton(
              onPressed: () => context.go(AppRoutes.home),
              child: Text(l10n.ok),
            ),
          ),
        ),
      );
    }

    final over = snapshot.isOver;
    final cancelled = snapshot.cancelled;
    final remaining = snapshot.totalBytes - snapshot.receivedBytes;
    final etaSeconds = snapshot.bytesPerSecond > 0 ? (remaining / snapshot.bytesPerSecond).ceil() : null;
    final savedInAppFolder = over && snapshot.files.any((f) => f.status == ReceiveFileStatus.saved && !f.published);
    final anyPublished = snapshot.files.any((f) => f.published);

    return PopScope(
      canPop: false, // leaving mid-transfer is done with the buttons
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && over) _leave(context, ref);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(over ? (cancelled ? l10n.receiveCancelled : l10n.receivedTitle) : l10n.receivingTitle),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  children: [
                    ZajelCard(
                      child: Row(
                        children: [
                          IconBadge(icon: Icons.south_west, color: scheme.secondary),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l10n.receivingFrom, style: theme.textTheme.bodySmall),
                                Text(
                                  snapshot.senderAlias,
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(snapshot.senderAddress, style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (over && !cancelled)
                      ZajelCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(Icons.check_circle, size: 64, color: success),
                            const SizedBox(height: 10),
                            Text(
                              '${l10n.filesCount(snapshot.files.length)} · ${formatBytes(snapshot.totalBytes)}',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            if (anyPublished) ...[
                              const SizedBox(height: 10),
                              Text(l10n.savedWhere, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                            ],
                            if (savedInAppFolder && !anyPublished) ...[
                              const SizedBox(height: 10),
                              Text(l10n.savedInAppFolder, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                            ],
                          ],
                        ),
                      )
                    else if (over && cancelled)
                      ZajelCard(
                        child: Column(
                          children: [
                            Icon(Icons.cancel_outlined, size: 56, color: scheme.error),
                            const SizedBox(height: 10),
                            Text(l10n.receiveCancelled, textAlign: TextAlign.center),
                          ],
                        ),
                      )
                    else ...[
                      ZajelCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  (snapshot.bytesPerSecond / (1024 * 1024)).toStringAsFixed(1),
                                  style: theme.textTheme.displayLarge?.copyWith(
                                    color: scheme.secondary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('MB/s', style: theme.textTheme.titleMedium),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: StatTile(
                                    label: l10n.transferredSoFar,
                                    value: '${formatBytes(snapshot.receivedBytes)} / ${formatBytes(snapshot.totalBytes)}',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: StatTile(
                                    label: l10n.etaLabel,
                                    value: etaSeconds == null ? '—' : formatEta(context, etaSeconds),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(child: Text(l10n.overallProgress, style: theme.textTheme.bodySmall)),
                                Text(
                                  '${(snapshot.fraction * 100).round()}%',
                                  style: theme.textTheme.labelLarge?.copyWith(color: scheme.secondary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: snapshot.fraction,
                              minHeight: 10,
                              color: scheme.secondary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ],
                        ),
                      ),
                      SlowLinkHint(
                        bytesPerSecond: snapshot.bytesPerSecond,
                        transferredBytes: snapshot.receivedBytes,
                      ),
                    ],
                    const SizedBox(height: 22),
                    Text(
                      l10n.fileListTitle(snapshot.files.length),
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    for (final file in snapshot.files) ...[
                      _ReceiveFileTile(file: file, service: service),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: over
                    ? FilledButton.icon(
                        icon: const Icon(Icons.check),
                        onPressed: () => _leave(context, ref),
                        label: Text(l10n.ok),
                      )
                    : FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.error,
                          foregroundColor: scheme.onError,
                        ),
                        icon: const Icon(Icons.close),
                        onPressed: () => service?.cancelReceive(),
                        label: Text(l10n.cancel),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiveFileTile extends StatelessWidget {
  const _ReceiveFileTile({required this.file, required this.service});

  final ReceiveFile file;
  final dynamic service;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final success = context.zajelColors.success;

    final (label, color) = switch (file.status) {
      ReceiveFileStatus.waiting => (l10n.fileWaiting, scheme.onSurface.withValues(alpha: 0.6)),
      ReceiveFileStatus.receiving => (l10n.fileSending.replaceAll('الإرسال', 'الاستقبال'), scheme.secondary),
      ReceiveFileStatus.saving => (l10n.fileSaving, scheme.secondary),
      ReceiveFileStatus.saved => (l10n.fileSaved, success),
      ReceiveFileStatus.failed => (l10n.sendFailed, scheme.error),
    };
    final saved = file.status == ReceiveFileStatus.saved;
    final canOpen = saved && file.published && file.location != null;

    return TransferFileTile(
      name: file.name,
      size: file.size,
      statusText: label,
      statusColor: color,
      fraction: file.fraction,
      active: file.status == ReceiveFileStatus.receiving,
      done: saved,
      trailing: canOpen
          ? TextButton(
              onPressed: () => service?.openReceived(file.location!, file.mimeType),
              child: Text(l10n.openFile),
            )
          : saved
          ? Icon(Icons.check_circle, color: success)
          : file.status == ReceiveFileStatus.saving
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : null,
    );
  }
}
