import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/discovery/multicast_discovery.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/transfer/transfer_providers.dart';
import '../../core/transport/transport_manager.dart';
import '../../core/widgets/zajel_widgets.dart';
import '../../l10n/l10n.dart';
import '../qr/transport_messages.dart';
import 'direct_controller.dart';
import 'radar_view.dart';

/// After this long with nobody found, the screen suggests a QR code, which
/// needs no network at all (SPEC.md, Phase 3).
const discoverySuggestQrAfter = Duration(seconds: 5);

final _noDevicesTimeoutProvider = FutureProvider.autoDispose<bool>((ref) {
  // A cancellable timer, so leaving the screen leaves nothing pending.
  final done = Completer<bool>();
  final timer = Timer(discoverySuggestQrAfter, () => done.complete(true));
  ref.onDispose(timer.cancel);
  return done.future;
});

class DiscoveryScreen extends ConsumerWidget {
  const DiscoveryScreen({super.key});

  void _send(BuildContext context, WidgetRef ref, List<PeerRoute> routes) {
    if (ref.read(selectedFilesProvider).isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.pickFilesFirst)));
      context.push(AppRoutes.filePicker);
      return;
    }
    // The routes are tried fastest first, falling back automatically.
    ref.read(sendJobProvider.notifier).sendVia(routes);
    context.push(AppRoutes.transfer);
  }

  /// One radar item per device, even when it can be reached more than one way.
  List<RadarItem> _items(
    BuildContext context,
    WidgetRef ref,
    List<DiscoveredDevice> lan,
    List<DirectPeer> direct,
  ) {
    final l10n = context.l10n;
    final byFingerprint = <String, List<PeerRoute>>{};
    final titles = <String, (String title, String subtitle, IconData icon, String? badge)>{};

    for (final device in lan) {
      final id = device.info.fingerprint;
      byFingerprint.putIfAbsent(id, () => []).add(LanRoute(device));
      titles[id] = (
        device.info.alias,
        device.info.deviceModel ?? device.address.address,
        deviceIconFor(device.info.deviceType),
        null,
      );
    }
    for (final peer in direct) {
      final id = peer.fingerprint;
      byFingerprint.putIfAbsent(id, () => []).add(DirectRoute(peer));
      titles.putIfAbsent(id, () => (peer.alias, l10n.wifiDirect, Icons.smartphone, l10n.directBadge));
    }

    return [
      for (final entry in byFingerprint.entries)
        RadarItem(
          id: entry.key,
          title: titles[entry.key]!.$1,
          subtitle: titles[entry.key]!.$2,
          icon: titles[entry.key]!.$3,
          badge: titles[entry.key]!.$4,
          onTap: () => _send(context, ref, entry.value),
        ),
    ];
  }

  Future<void> _showDirectSheet(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (_) => const _DirectSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lan = ref.watch(nearbyDevicesProvider).value ?? const [];
    final direct = ref.watch(directControllerProvider);
    final service = ref.watch(localSendServiceProvider).value;
    final selfName = service?.device.alias ?? l10n.appName;
    final hasDirect = ref.watch(transportManagerProvider) != null;
    final items = _items(context, ref, lan, direct.peers);
    final timedOut = ref.watch(_noDevicesTimeoutProvider).value ?? false;
    final suggestQr = items.isEmpty && timedOut;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.discoveryTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ZajelCard(
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 12, color: context.zajelColors.success),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            items.isEmpty ? l10n.searchingNearby : l10n.foundCount(items.length),
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            direct.visible ? l10n.directVisibleOn : l10n.readyToReceive(selfName),
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.refresh, color: scheme.primary),
                      tooltip: l10n.searchAgain,
                      onPressed: service?.rescan,
                    ),
                  ],
                ),
              ),
              if (suggestQr) ...[
                const SizedBox(height: 10),
                ZajelCard(
                  accent: scheme.secondary,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.qr_code_2, color: scheme.secondary),
                      const SizedBox(width: 12),
                      Expanded(child: Text(l10n.suggestQr)),
                    ],
                  ),
                ),
              ],
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: RadarView(selfName: selfName, items: items),
                ),
              ),
              if (direct.failure != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    transportMessage(l10n, direct.failure!),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: (suggestQr ? FilledButton.icon : FilledButton.tonalIcon)(
                      style: FilledButton.styleFrom(
                        backgroundColor: suggestQr ? scheme.secondary : scheme.secondary.withValues(alpha: 0.18),
                        foregroundColor: suggestQr ? scheme.onSecondary : scheme.secondary,
                      ),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text(l10n.scanQr),
                      onPressed: () => context.push(AppRoutes.qrScan),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.qr_code_2),
                      label: Text(l10n.showQr),
                      onPressed: () => context.push(AppRoutes.qrShow),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (hasDirect)
                    TextButton.icon(
                      icon: direct.searching
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.wifi_tethering),
                      label: Text(l10n.wifiDirect),
                      onPressed: () => _showDirectSheet(context, ref),
                    ),
                  TextButton.icon(
                    icon: const Icon(Icons.public),
                    label: Text(l10n.webShareTitle),
                    onPressed: () => context.push(AppRoutes.webShare),
                  ),
                ],
              ),
              ZajelCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: scheme.secondary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(l10n.discoveryTip, style: theme.textTheme.bodySmall)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectSheet extends ConsumerWidget {
  const _DirectSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final direct = ref.watch(directControllerProvider);
    final controller = ref.read(directControllerProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.search),
              title: Text(l10n.directSearch),
              subtitle: direct.searching
                  ? Text(l10n.searchingNearby)
                  : (direct.peers.isEmpty && !direct.searching && direct.failure == null
                        ? null
                        : Text(direct.peers.isEmpty ? l10n.directNone : l10n.foundCount(direct.peers.length))),
              onTap: direct.searching
                  ? null
                  : () async {
                      await controller.search();
                      if (context.mounted && ref.read(directControllerProvider).peers.isNotEmpty) {
                        Navigator.of(context).pop();
                      }
                    },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.visibility_outlined),
              title: Text(l10n.directVisible),
              value: direct.visible,
              onChanged: controller.setVisible,
            ),
          ],
        ),
      ),
    );
  }
}
