import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/transfer/transfer_providers.dart';
import '../../l10n/l10n.dart';

class DoneScreen extends ConsumerWidget {
  const DoneScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final job = ref.watch(sendJobProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.doneTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.check_circle,
                size: 96,
                color: context.zajelColors.success,
              ),
              const SizedBox(height: 16),
              Text(
                '${l10n.filesCount(job.files.length)} · '
                '${formatBytes(job.totalBytes)}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () {
                  ref.read(sendJobProvider.notifier).reset();
                  ref.read(selectedFilesProvider.notifier).clear();
                  context.go(AppRoutes.filePicker);
                },
                child: Text(l10n.sendMore),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  ref.read(sendJobProvider.notifier).reset();
                  ref.read(selectedFilesProvider.notifier).clear();
                  context.go(AppRoutes.home);
                },
                child: Text(l10n.appName),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
