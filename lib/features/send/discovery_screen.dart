import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/discovery/multicast_discovery.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/transfer/transfer_providers.dart';
import '../../core/widgets/zajel_widgets.dart';
import '../../l10n/l10n.dart';
import 'radar_view.dart';

class DiscoveryScreen extends ConsumerWidget {
  const DiscoveryScreen({super.key});

  void _send(BuildContext context, WidgetRef ref, DiscoveredDevice device) {
    if (ref.read(selectedFilesProvider).isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.pickFilesFirst)));
      context.push(AppRoutes.filePicker);
      return;
    }
    ref.read(sendJobProvider.notifier).send(device);
    context.push(AppRoutes.transfer);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final devices = ref.watch(nearbyDevicesProvider).value ?? const [];
    final service = ref.watch(localSendServiceProvider).value;
    final selfName = service?.device.alias ?? l10n.appName;

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
                            devices.isEmpty ? l10n.searchingNearby : l10n.foundCount(devices.length),
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            l10n.readyToReceive(selfName),
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
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: RadarView(
                    selfName: selfName,
                    devices: devices,
                    onSelect: (device) => _send(context, ref, device),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.secondary.withValues(alpha: 0.18),
                        foregroundColor: scheme.secondary,
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
              TextButton.icon(
                icon: const Icon(Icons.public),
                label: Text(l10n.webShareTitle),
                onPressed: () => context.push(AppRoutes.webShare),
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
