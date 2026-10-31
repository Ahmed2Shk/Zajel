
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/media/media_library.dart';
import '../../core/transfer/send_client.dart';
import '../../core/transfer/transfer_providers.dart';
import '../../l10n/l10n.dart';

/// The id a selected media item gets in the send list, so the grid can tell
/// which tiles are selected.
String mediaSendId(MediaItem item) => 'media-${item.id}';

/// Photos or videos of the device as a grid of pictures, loaded as you scroll.
/// Tapping a tile selects it for sending.
class MediaGrid extends ConsumerStatefulWidget {
  const MediaGrid({required this.kind, super.key});

  final MediaKind kind;

  @override
  ConsumerState<MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends ConsumerState<MediaGrid> {
  static const _pageSize = 90;

  final _scroll = ScrollController();
  final _items = <MediaItem>[];
  MediaAccess? _access;
  bool _supported = true;
  bool _loading = false;
  bool _hasMore = true;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadMoreNearEnd);
    _start();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final library = ref.read(mediaLibraryProvider);
    if (library == null) {
      setState(() => _supported = false);
      return;
    }
    MediaAccess access;
    try {
      access = await library.requestAccess(widget.kind);
    } catch (_) {
      access = MediaAccess.denied;
    }
    if (!mounted) return;
    setState(() => _access = access);
    if (access != MediaAccess.denied) await _loadMore();
  }

  void _loadMoreNearEnd() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 600) _loadMore();
  }

  Future<void> _loadMore() async {
    final library = ref.read(mediaLibraryProvider);
    if (library == null || _loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final next = await library.page(widget.kind, page: _page, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _items.addAll(next);
        _page++;
        _hasMore = next.length == _pageSize;
      });
    } catch (_) {
      if (mounted) setState(() => _hasMore = false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(MediaItem item, bool selected) async {
    final notifier = ref.read(selectedFilesProvider.notifier);
    final id = mediaSendId(item);
    if (selected) {
      notifier.set([
        for (final f in ref.read(selectedFilesProvider))
          if (f.id != id) f,
      ]);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final unreadable = context.l10n.mediaUnreadable;
    final resolved = await item.resolve();
    if (resolved == null) {
      messenger.showSnackBar(SnackBar(content: Text(unreadable)));
      return;
    }
    final file = await SendFile.fromPath(resolved.path, id: id, name: resolved.name);
    notifier.set([...ref.read(selectedFilesProvider), file]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    if (!_supported) return _Message(icon: Icons.info_outline, text: l10n.mediaUnsupported);
    if (_access == null) return const Center(child: CircularProgressIndicator());
    if (_access == MediaAccess.denied) {
      final library = ref.read(mediaLibraryProvider)!;
      return _Message(
        icon: Icons.lock_outline,
        text: l10n.mediaDenied,
        actions: [
          FilledButton(onPressed: _start, child: Text(l10n.mediaAllow)),
          TextButton(onPressed: library.openSettings, child: Text(l10n.mediaOpenSettings)),
        ],
      );
    }
    if (_items.isEmpty && !_loading) return _Message(icon: Icons.photo_outlined, text: l10n.mediaEmpty);

    final selectedIds = ref.watch(
      selectedFilesProvider.select((files) => {for (final f in files) f.id}),
    );

    return Column(
      children: [
        if (_access == MediaAccess.limited)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(l10n.mediaLimited, style: theme.textTheme.bodySmall),
          ),
        Expanded(
          child: GridView.builder(
            controller: _scroll,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: _items.length + (_loading ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= _items.length) {
                return const Center(child: CircularProgressIndicator(strokeWidth: 2));
              }
              final item = _items[index];
              final selected = selectedIds.contains(mediaSendId(item));
              return _Tile(
                key: ValueKey(item.id),
                item: item,
                selected: selected,
                onTap: () => _toggle(item, selected),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({required this.item, required this.selected, required this.onTap, super.key});

  final MediaItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  // Asked once per tile, not on every rebuild.
  late final Future<Uint8List?> _picture = widget.item.thumbnail(256);

  String _duration(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = widget.item;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<Uint8List?>(
                future: _picture,
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes == null) {
                    return ColoredBox(color: scheme.surface);
                  }
                  return Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    cacheWidth: 256,
                  );
                },
              ),
              if (widget.selected)
                ColoredBox(color: scheme.primary.withValues(alpha: 0.25)),
              if (item.duration != null)
                PositionedDirectional(
                  start: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_arrow, size: 14),
                        Text(_duration(item.duration!), style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                  ),
                ),
              PositionedDirectional(
                top: 6,
                end: 6,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.selected ? scheme.primary : scheme.surface.withValues(alpha: 0.6),
                    border: Border.all(color: scheme.onSurface.withValues(alpha: 0.5)),
                  ),
                  child: widget.selected ? Icon(Icons.check, size: 16, color: scheme.onPrimary) : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.actions = const []});

  final IconData icon;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
            const SizedBox(height: 14),
            Text(text, textAlign: TextAlign.center),
            for (final action in actions) ...[const SizedBox(height: 10), action],
          ],
        ),
      ),
    );
  }
}
