import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/transfer/protocol_models.dart';
import '../../core/widgets/zajel_widgets.dart';

IconData deviceIconFor(DeviceType type) => switch (type) {
  DeviceType.mobile => Icons.smartphone,
  DeviceType.desktop => Icons.computer,
  DeviceType.web => Icons.language,
  DeviceType.headless => Icons.terminal,
  DeviceType.server => Icons.dns,
};

/// One device on the radar. It may be reachable more than one way; the screen
/// decides what tapping it does.
class RadarItem {
  const RadarItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.badge,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;

  /// Short label such as "Direct", for a device found over Wi-Fi Direct.
  final String? badge;
  final VoidCallback onTap;
}

/// A radar around this device with nearby devices as bubbles.
///
/// Bubbles keep a stable place (ordered by fingerprint) so they do not jump
/// around when another device appears.
class RadarView extends StatefulWidget {
  const RadarView({
    required this.selfName,
    required this.items,
    super.key,
  });

  final String selfName;
  final List<RadarItem> items;

  @override
  State<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<RadarView> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final devices = [...widget.items]
      ..sort((a, b) => a.id.compareTo(b.id));

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        final center = Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
        const bubbleWidth = 150.0;
        const bubbleHeight = 64.0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                animation: _sweep,
                builder: (context, _) => CustomPaint(
                  painter: _RadarPainter(
                    color: scheme.primary,
                    ringColor: scheme.secondary,
                    sweep: _sweep.value,
                    radius: side / 2,
                  ),
                ),
                ),
              ),
            ),
            Positioned(
              left: center.dx - 34,
              top: center.dy - 34,
              child: Column(
                children: [
                  DeviceAvatar(name: widget.selfName, radius: 34),
                ],
              ),
            ),
            for (var i = 0; i < devices.length; i++)
              _positioned(
                devices[i],
                index: i,
                count: devices.length,
                center: center,
                radius: side / 2,
                size: const Size(bubbleWidth, bubbleHeight),
                bounds: constraints.biggest,
              ),
          ],
        );
      },
    );
  }

  Widget _positioned(
    RadarItem item, {
    required int index,
    required int count,
    required Offset center,
    required double radius,
    required Size size,
    required Size bounds,
  }) {
    // Spread evenly around the circle; alternate two distances so neighbours
    // do not collide.
    final angle = -math.pi / 2 + 2 * math.pi * index / count + (count == 1 ? 0.6 : 0);
    final distance = radius * (index.isEven ? 0.66 : 0.86);
    final spot = center + Offset(math.cos(angle), math.sin(angle)) * distance;
    final left = (spot.dx - size.width / 2).clamp(0.0, math.max(0.0, bounds.width - size.width)).toDouble();
    final top = (spot.dy - size.height / 2).clamp(0.0, math.max(0.0, bounds.height - size.height)).toDouble();

    return Positioned(
      left: left,
      top: top,
      width: size.width,
      child: _Bubble(item: item),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.item});

  final RadarItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ZajelCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      onTap: item.onTap,
      child: Row(
        children: [
          IconBadge(icon: item.icon, color: scheme.primary, size: 36),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (item.badge != null)
            Container(
              margin: const EdgeInsetsDirectional.only(start: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.secondary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                item.badge!,
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.secondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.color,
    required this.ringColor,
    required this.sweep,
    required this.radius,
  });

  final Color color;
  final Color ringColor;
  final double sweep;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final (fraction, tint) in [(0.34, color), (0.66, ringColor), (0.98, ringColor)]) {
      ring.color = tint.withValues(alpha: 0.28);
      canvas.drawCircle(center, radius * fraction, ring);
    }

    // The rotating beam.
    final rect = Rect.fromCircle(center: center, radius: radius);
    final beam = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi / 2,
        colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.28)],
        transform: GradientRotation(sweep * 2 * math.pi - math.pi / 2),
      ).createShader(rect);
    canvas.drawCircle(center, radius, beam);
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.sweep != sweep || old.color != color;
}
