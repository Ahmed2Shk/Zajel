import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/transfer/transfer_providers.dart';
import '../../core/widgets/zajel_widgets.dart';
import '../../l10n/l10n.dart';
import '../history/history_store.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final service = ref.watch(localSendServiceProvider).value;
    final history = ref.watch(historyProvider);

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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            ZajelCard(
              child: Row(
                children: [
                  IconBadge(icon: Icons.wifi_tethering, color: scheme.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.homeReadyTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(l10n.homeReadySubtitle, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  if (service != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Icon(Icons.circle, size: 10, color: context.zajelColors.success),
                        const SizedBox(height: 4),
                        Text(service.device.alias, style: theme.textTheme.labelSmall),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _BigAction(
              color: scheme.primary,
              onColor: scheme.onPrimary,
              icon: Icons.north_east,
              title: l10n.send,
              subtitle: l10n.sendSubtitle,
              onTap: () {
                // Start from an empty selection, not what a cancelled send left.
                ref.read(selectedFilesProvider.notifier).clear();
                context.push(AppRoutes.filePicker);
              },
            ),
            const SizedBox(height: 14),
            _BigAction(
              color: scheme.secondary,
              onColor: scheme.onSecondary,
              icon: Icons.south_west,
              title: l10n.receive,
              subtitle: l10n.receiveSubtitle,
              onTap: () => context.push(AppRoutes.discovery),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _Tile(
                    icon: Icons.link,
                    title: l10n.directLink,
                    subtitle: l10n.directLinkSub,
                    onTap: () => context.push(AppRoutes.webShare),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _Tile(
                    icon: Icons.qr_code_2,
                    title: l10n.qrTile,
                    subtitle: l10n.qrTileSub,
                    onTap: () => context.push(AppRoutes.qrShow),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.recentTransfers,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (history.isNotEmpty)
                  TextButton(
                    onPressed: () => ref.read(historyProvider.notifier).clear(),
                    child: Text(l10n.historyClear),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (history.isEmpty)
              ZajelCard(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                child: Center(child: Text(l10n.noRecentTransfers)),
              )
            else
              for (final entry in history.take(8)) ...[
                _HistoryTile(entry: entry),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

/// A large colored button with a soft glow, as in the design.
class _BigAction extends StatelessWidget {
  const _BigAction({
    required this.color,
    required this.onColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Color color;
  final Color onColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: 28, spreadRadius: -4),
        ],
      ),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: onColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 30),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: onColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: onColor.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ZajelCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, color: theme.colorScheme.secondary, size: 40),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(subtitle, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sent = entry.direction == TransferDirection.sent;
    final color = sent ? scheme.primary : scheme.secondary;
    final when = DateFormat.yMd(Localizations.localeOf(context).toString())
        .add_Hm()
        .format(entry.at);

    return ZajelCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          IconBadge(icon: fileIconFor(entry.name), color: color, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${sent ? l10n.directionSent : l10n.directionReceived}'
                  '${entry.peer.isEmpty ? '' : ' · ${entry.peer}'} · $when',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(formatBytes(entry.size), style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}
