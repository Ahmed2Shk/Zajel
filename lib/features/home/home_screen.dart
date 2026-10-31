import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../l10n/l10n.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appName),
        leading: IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: l10n.settingsTitle,
          onPressed: () => context.push(AppRoutes.settings),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: l10n.scanQr,
            onPressed: () => context.push(AppRoutes.qrScan),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 120,
                child: FilledButton.icon(
                  icon: const Icon(Icons.north_east, size: 32),
                  label: Text(l10n.send),
                  onPressed: () => context.push(AppRoutes.filePicker),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 120,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.secondary,
                    foregroundColor: scheme.onSecondary,
                  ),
                  icon: const Icon(Icons.south_west, size: 32),
                  label: Text(l10n.receive),
                  onPressed: () => context.push(AppRoutes.discovery),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                l10n.recentTransfers,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  child: Center(child: Text(l10n.noRecentTransfers)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
