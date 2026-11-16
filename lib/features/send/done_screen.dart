import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/transfer/transfer_providers.dart';
import '../../core/widgets/zajel_widgets.dart';
import '../../l10n/l10n.dart';

class DoneScreen extends ConsumerWidget {
  const DoneScreen({super.key});

  void _finish(WidgetRef ref) {
    ref.read(sendJobProvider.notifier).reset();
    ref.read(selectedFilesProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final success = context.zajelColors.success;
    final job = ref.watch(sendJobProvider);

    // This screen is alone on the stack, so a plain Back would close the app.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _finish(ref);
        context.go(AppRoutes.home);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.doneTitle),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 132,
                          height: 132,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: success.withValues(alpha: 0.14),
                            boxShadow: [
                              BoxShadow(
                                color: success.withValues(alpha: 0.35),
                                blurRadius: 40,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.check_circle,
                            size: 84,
                            color: success,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          l10n.doneTitle,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ZajelCard(
                          child: Row(
                            children: [
                              IconBadge(
                                icon: Icons.folder_outlined,
                                color: success,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${l10n.filesCount(job.files.length)} · ${formatBytes(job.totalBytes)}',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    if (job.target != null)
                                      Text(
                                        job.target!.info.alias,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    _finish(ref);
                    // Home stays underneath, so Back from the picker goes there.
                    context.go(AppRoutes.home);
                    context.push(AppRoutes.filePicker);
                  },
                  child: Text(l10n.sendMore),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    _finish(ref);
                    context.go(AppRoutes.home);
                  },
                  child: Text(l10n.appName),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
