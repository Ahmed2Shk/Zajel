import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/discovery/multicast_discovery.dart';
import '../../core/router/app_router.dart';
import '../../core/transfer/protocol_models.dart';
import '../../core/transfer/transfer_providers.dart';
import '../../l10n/l10n.dart';

IconData _iconFor(DeviceType type) => switch (type) {
  DeviceType.mobile => Icons.smartphone,
  DeviceType.desktop => Icons.computer,
  DeviceType.web => Icons.language,
  DeviceType.headless => Icons.terminal,
  DeviceType.server => Icons.dns,
};

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
    final devices = ref.watch(nearbyDevicesProvider).value ?? const [];
    final service = ref.watch(localSendServiceProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.discoveryTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (service != null)
                Text(
                  l10n.readyToReceive(service.device.alias),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              const SizedBox(height: 16),
              Expanded(
                child: devices.isEmpty
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 24),
                          Text(
                            l10n.searchingDevices,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.noDevicesFound,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      )
                    : ListView.separated(
                        itemCount: devices.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final device = devices[index];
                          return Card(
                            child: ListTile(
                              leading: Icon(_iconFor(device.info.deviceType)),
                              title: Text(device.info.alias),
                              subtitle: Text(
                                [
                                  if (device.info.deviceModel != null)
                                    device.info.deviceModel!,
                                  device.address.address,
                                ].join(' · '),
                              ),
                              onTap: () => _send(context, ref, device),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                icon: const Icon(Icons.refresh),
                label: Text(l10n.searchAgain),
                onPressed: service?.rescan,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.push(AppRoutes.qrShow),
                      child: Text(l10n.showQr),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.push(AppRoutes.qrScan),
                      child: Text(l10n.scanQr),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
