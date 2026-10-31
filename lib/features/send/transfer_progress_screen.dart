import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/transfer/transfer_providers.dart';
import '../../core/widgets/zajel_widgets.dart';
import '../../l10n/l10n.dart';
import '../history/history_store.dart';
import 'radar_view.dart';

class TransferProgressScreen extends ConsumerStatefulWidget {
  const TransferProgressScreen({super.key});

  @override
  ConsumerState<TransferProgressScreen> createState() =>
      _TransferProgressScreenState();
}

class _TransferProgressScreenState
    extends ConsumerState<TransferProgressScreen> {
  Future<void> _askPin() async {
    final controller = TextEditingController();
    final l10n = context.l10n;
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.enterPin),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.pinRequiredHint),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted) return;

    final job = ref.read(sendJobProvider);
    if (pin == null || pin.isEmpty || job.target == null) {
      ref.read(sendJobProvider.notifier).reset();
      context.go(AppRoutes.home);
      return;
    }
    await ref.read(sendJobProvider.notifier).send(job.target!, pin: pin);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final job = ref.watch(sendJobProvider);

    ref.listen(sendJobProvider.select((j) => j.status), (_, status) {
      if (status == SendStatus.done) {
        final finishedJob = ref.read(sendJobProvider);
        ref.read(historyProvider.notifier).add([
          for (final file in finishedJob.files)
            HistoryEntry(
              name: file.name,
              size: file.size,
              peer: finishedJob.target?.info.alias ?? '',
              direction: TransferDirection.sent,
              at: DateTime.now(),
            ),
        ]);
        context.go(AppRoutes.done);
      }
      if (status == SendStatus.needsPin) _askPin();
    });

    final failed = job.status == SendStatus.failed;
    final remaining = job.totalBytes - job.sentBytes;
    final etaSeconds = job.bytesPerSecond > 0
        ? (remaining / job.bytesPerSecond).ceil()
        : null;
    final finished = job.files
        .where(
          (f) =>
              job.sentPerFile.containsKey(f.id) &&
              job.sentPerFile[f.id]! >= f.size,
        )
        .length;
    final target = job.target;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.transferTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                children: [
                  if (target != null)
                    ZajelCard(
                      child: Row(
                        children: [
                          IconBadge(
                            icon: deviceIconFor(target.info.deviceType),
                            color: scheme.secondary,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.connectedTo,
                                  style: theme.textTheme.bodySmall,
                                ),
                                Text(
                                  target.info.alias,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  target.address.address,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  if (failed)
                    ZajelCard(
                      child: Column(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 56,
                            color: scheme.error,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            job.error == 'declined'
                                ? l10n.declinedByReceiver
                                : '${l10n.sendFailed}\n${job.error ?? ''}',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
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
                                (job.bytesPerSecond / (1024 * 1024))
                                    .toStringAsFixed(1),
                                style: theme.textTheme.displayLarge?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w800,
                                  shadows: [
                                    Shadow(
                                      color: scheme.primary.withValues(
                                        alpha: 0.5,
                                      ),
                                      blurRadius: 24,
                                    ),
                                  ],
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
                                child: _Stat(
                                  label: l10n.transferredSoFar,
                                  value:
                                      '${formatBytes(job.sentBytes)} / ${formatBytes(job.totalBytes)}',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _Stat(
                                  label: l10n.etaLabel,
                                  value: etaSeconds == null
                                      ? '—'
                                      : formatEta(context, etaSeconds),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.overallProgress,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                              Text(
                                '${(job.fraction * 100).round()}%',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: scheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: job.status == SendStatus.connecting
                                ? null
                                : job.fraction,
                            minHeight: 10,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.fileListTitle(job.files.length),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '$finished / ${job.files.length}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final file in job.files) ...[
                    _FileRow(
                      name: file.name,
                      size: file.size,
                      sent: job.sentPerFile[file.id] ?? 0,
                      started: job.sentPerFile.containsKey(file.id),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: FilledButton.icon(
                style: failed
                    ? null
                    : FilledButton.styleFrom(
                        backgroundColor: scheme.error,
                        foregroundColor: scheme.onError,
                      ),
                icon: Icon(failed ? Icons.check : Icons.close),
                onPressed: () async {
                  await ref.read(sendJobProvider.notifier).cancel();
                  if (context.mounted) context.go(AppRoutes.home);
                },
                label: Text(failed ? l10n.ok : l10n.cancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.name,
    required this.size,
    required this.sent,
    required this.started,
  });

  final String name;
  final int size;
  final int sent;
  final bool started;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = started && sent >= size;
    final active = started && !done;
    final fraction = size == 0 ? 1.0 : (sent / size).clamp(0.0, 1.0);
    final success = context.zajelColors.success;

    final (label, color) = done
        ? (l10n.fileDone, success)
        : active
        ? (l10n.fileSending, scheme.primary)
        : (l10n.fileWaiting, scheme.onSurface.withValues(alpha: 0.6));

    return ZajelCard(
      accent: active ? scheme.primary : null,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              IconBadge(
                icon: fileIconFor(name),
                color: done ? success : scheme.primary,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$label · ${formatBytes(size)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: color),
                    ),
                  ],
                ),
              ),
              if (done)
                Icon(Icons.check_circle, color: success)
              else if (active)
                Text(
                  '${(fraction * 100).round()}%',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                  ),
                )
              else
                Icon(Icons.hourglass_empty, color: color),
            ],
          ),
          if (active) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              borderRadius: BorderRadius.circular(20),
            ),
          ],
        ],
      ),
    );
  }
}
