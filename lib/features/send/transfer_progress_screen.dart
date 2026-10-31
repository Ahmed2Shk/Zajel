import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/router/app_router.dart';
import '../../core/transfer/transfer_providers.dart';
import '../../l10n/l10n.dart';

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
    final job = ref.watch(sendJobProvider);

    ref.listen(sendJobProvider.select((j) => j.status), (_, status) {
      if (status == SendStatus.done) context.go(AppRoutes.done);
      if (status == SendStatus.needsPin) _askPin();
    });

    final failed = job.status == SendStatus.failed;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.transferTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (job.target != null)
                Text(
                  l10n.sendingTo(job.target!.info.alias),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              const SizedBox(height: 24),
              if (failed) ...[
                Icon(Icons.error_outline, size: 64, color: scheme.error),
                const SizedBox(height: 16),
                Text(
                  job.error == 'declined'
                      ? l10n.declinedByReceiver
                      : '${l10n.sendFailed}\n${job.error ?? ''}',
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                Text(
                  (job.bytesPerSecond / (1024 * 1024)).toStringAsFixed(1),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Text('MB/s', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                LinearProgressIndicator(
                  value: job.status == SendStatus.connecting
                      ? null
                      : job.fraction,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(20),
                ),
                const SizedBox(height: 8),
                Text(
                  '${formatBytes(job.sentBytes)} / ${formatBytes(job.totalBytes)}',
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    for (final file in job.files)
                      ListTile(
                        title: Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: LinearProgressIndicator(
                          value: file.size == 0
                              ? 1
                              : (job.sentPerFile[file.id] ?? 0) / file.size,
                        ),
                      ),
                  ],
                ),
              ),
              FilledButton(
                style: failed
                    ? null
                    : FilledButton.styleFrom(
                        backgroundColor: scheme.error,
                        foregroundColor: scheme.onError,
                      ),
                onPressed: () async {
                  await ref.read(sendJobProvider.notifier).cancel();
                  if (context.mounted) context.go(AppRoutes.home);
                },
                child: Text(failed ? l10n.ok : l10n.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
