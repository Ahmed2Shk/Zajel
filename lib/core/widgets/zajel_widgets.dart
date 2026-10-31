import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// A rounded surface block, the basic container of the design.
class ZajelCard extends StatelessWidget {
  const ZajelCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.accent,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// A colored strip on the leading edge, used to mark the active item.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: accent == null
              ? null
              : BoxDecoration(
                  border: BorderDirectional(
                    start: BorderSide(color: accent!, width: 4),
                  ),
                ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// A small icon in a tinted rounded square.
class IconBadge extends StatelessWidget {
  const IconBadge({
    required this.icon,
    this.color,
    this.size = 48,
    super.key,
  });

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(icon, color: tint, size: size * 0.5),
    );
  }
}

/// An icon that suggests a file's kind from its name.
IconData fileIconFor(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'heic' || 'bmp' => Icons.image_outlined,
    'mp4' || 'mkv' || 'mov' || 'avi' || 'webm' || '3gp' => Icons.movie_outlined,
    'mp3' || 'flac' || 'wav' || 'm4a' || 'ogg' || 'aac' => Icons.audiotrack_outlined,
    'apk' || 'aab' => Icons.android,
    'pdf' => Icons.picture_as_pdf_outlined,
    'zip' || 'rar' || '7z' || 'tar' || 'gz' => Icons.folder_zip_outlined,
    'doc' || 'docx' || 'txt' || 'odt' || 'rtf' => Icons.description_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

/// A round avatar with the first letter of a device name.
class DeviceAvatar extends StatelessWidget {
  const DeviceAvatar({required this.name, this.radius = 24, super.key});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final letter = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      child: Text(
        letter,
        style: TextStyle(fontSize: radius * 0.9, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// "12 s" or "3 min 5 s", from a number of seconds.
String formatEta(BuildContext context, int seconds) {
  final l10n = context.l10n;
  if (seconds < 60) return l10n.etaSeconds(seconds);
  return l10n.etaMinutes(seconds ~/ 60, seconds % 60);
}
