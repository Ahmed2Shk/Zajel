import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../platform/platform_api.g.dart';
import '../platform/platform_providers.dart';
import '../format.dart';
import 'zajel_widgets.dart';

/// A small framed number with a label, used for speed, size and time left.
class StatTile extends StatelessWidget {
  const StatTile({required this.label, required this.value, super.key});

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
          Text(label, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// "5 GHz · 433 Mbps", from the phone's current Wi-Fi connection.
String describeWifi(NativeWifiInfo info) {
  final mhz = info.frequencyMhz;
  final band = mhz >= 5925
      ? '6 GHz'
      : mhz >= 4900
      ? '5 GHz'
      : '2.4 GHz';
  return '$band · ${info.linkSpeedMbps} Mbps';
}

/// This phone's Wi-Fi facts, or null away from Android or without Wi-Fi.
final wifiInfoProvider = FutureProvider.autoDispose<NativeWifiInfo?>((ref) async {
  try {
    return await ref.watch(platformApiProvider).getWifiInfo();
  } catch (_) {
    return null;
  }
});

/// Shown under the speed while a transfer is slow: says which Wi-Fi this phone
/// is on, and suggests a direct connection, which does not go through the
/// router (many routers cap each device's speed or share the air between both
/// phones).
class SlowLinkHint extends ConsumerWidget {
  const SlowLinkHint({
    required this.bytesPerSecond,
    required this.transferredBytes,
    super.key,
  });

  final double bytesPerSecond;
  final int transferredBytes;

  /// Below this a big transfer is slow enough to be worth a hint.
  static const slowBytesPerSecond = 3 * 1024 * 1024;

  /// Enough data has moved for the speed to mean something.
  static const minBytes = 16 * 1024 * 1024;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final wifi = ref.watch(wifiInfoProvider).value;
    final slow = bytesPerSecond > 0 && bytesPerSecond < slowBytesPerSecond && transferredBytes >= minBytes;

    if (wifi == null && !slow) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ZajelCard(
        accent: slow ? theme.colorScheme.secondary : null,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (wifi != null)
              Row(
                children: [
                  const Icon(Icons.wifi, size: 18),
                  const SizedBox(width: 8),
                  Text(l10n.wifiLine(describeWifi(wifi)), style: theme.textTheme.bodySmall),
                ],
              ),
            if (slow) ...[
              if (wifi != null) const SizedBox(height: 8),
              Text(l10n.slowLinkHint, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// One file in a transfer: icon, name, state text, and a bar while it moves.
class TransferFileTile extends StatelessWidget {
  const TransferFileTile({
    required this.name,
    required this.size,
    required this.statusText,
    required this.statusColor,
    required this.fraction,
    this.active = false,
    this.done = false,
    this.trailing,
    super.key,
  });

  final String name;
  final int size;
  final String statusText;
  final Color statusColor;
  final double fraction;
  final bool active;
  final bool done;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ZajelCard(
      accent: active ? scheme.primary : null,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              IconBadge(
                icon: fileIconFor(name),
                color: done ? statusColor : scheme.primary,
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
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '$statusText · ${formatBytes(size)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: statusColor),
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (active)
                Text(
                  '${(fraction * 100).round()}%',
                  style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
                ),
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
