import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/platform/platform_api.g.dart';
import '../../core/platform/platform_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/transfer/send_client.dart';
import '../../core/transfer/transfer_providers.dart';
import '../../core/widgets/zajel_widgets.dart';
import '../../l10n/l10n.dart';

enum _PickerTab { photos, videos, apps, files }

class FilePickerScreen extends ConsumerStatefulWidget {
  const FilePickerScreen({super.key});

  @override
  ConsumerState<FilePickerScreen> createState() => _FilePickerScreenState();
}

class _FilePickerScreenState extends ConsumerState<FilePickerScreen> {
  _PickerTab _tab = _PickerTab.photos;
  String _appQuery = '';

  /// Adds the picked paths to the selection, ignoring ones already there.
  Future<void> _add(Iterable<({String path, String name})> picked) async {
    final notifier = ref.read(selectedFilesProvider.notifier);
    final files = [...ref.read(selectedFilesProvider)];
    final known = files.map((f) => f.file.path).toSet();
    for (final item in picked) {
      if (!known.add(item.path)) continue;
      files.add(
        await SendFile.fromPath(
          item.path,
          id: '${DateTime.now().microsecondsSinceEpoch}-${files.length}',
          name: item.name,
        ),
      );
    }
    notifier.set(files);
  }

  Future<void> _pick(FileType type) async {
    final picked = await FilePicker.pickFiles(type: type);
    await _add([
      for (final f in picked)
        if (f.path != null) (path: f.path!, name: f.name),
    ]);
  }

  void _toggleApp(NativeAppInfo app, bool selected) {
    final notifier = ref.read(selectedFilesProvider.notifier);
    final files = ref.read(selectedFilesProvider);
    if (selected) {
      _add([(path: app.apkPath, name: '${app.name}.apk')]);
    } else {
      notifier.set([
        for (final f in files)
          if (f.file.path != app.apkPath) f,
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final files = ref.watch(selectedFilesProvider);
    final total = files.fold<int>(0, (sum, f) => sum + f.size);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.filePickerTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: SegmentedButton<_PickerTab>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: _PickerTab.photos, label: Text(l10n.tabPhotos)),
                  ButtonSegment(value: _PickerTab.videos, label: Text(l10n.tabVideos)),
                  ButtonSegment(value: _PickerTab.apps, label: Text(l10n.tabApps)),
                  ButtonSegment(value: _PickerTab.files, label: Text(l10n.tabFiles)),
                ],
                selected: {_tab},
                onSelectionChanged: (value) => setState(() => _tab = value.first),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                children: [
                  switch (_tab) {
                    _PickerTab.photos => _PickButton(
                      icon: Icons.image_outlined,
                      label: l10n.pickPhotos,
                      onPressed: () => _pick(FileType.image),
                    ),
                    _PickerTab.videos => _PickButton(
                      icon: Icons.movie_outlined,
                      label: l10n.pickVideos,
                      onPressed: () => _pick(FileType.video),
                    ),
                    _PickerTab.files => _PickButton(
                      icon: Icons.add,
                      label: l10n.chooseFiles,
                      onPressed: () => _pick(FileType.any),
                    ),
                    _PickerTab.apps => _AppsList(
                      query: _appQuery,
                      onQuery: (q) => setState(() => _appQuery = q),
                      selectedPaths: {for (final f in files) f.file.path},
                      onToggle: _toggleApp,
                    ),
                  },
                  if (files.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.selectedItems(files.length),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: ref.read(selectedFilesProvider.notifier).clear,
                          child: Text(l10n.clearSelection),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < files.length; i++) ...[
                      _SelectedTile(
                        file: files[i],
                        onRemove: () => ref
                            .read(selectedFilesProvider.notifier)
                            .set([...files]..removeAt(i)),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ],
              ),
            ),
            // The send bar stays put while the list scrolls.
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          files.isEmpty
                              ? l10n.noFilesSelected
                              : l10n.selectedItems(files.length),
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (files.isNotEmpty)
                          Text(
                            l10n.readyToSendSize(formatBytes(total)),
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(140, 52)),
                    onPressed: files.isEmpty ? null : () => context.push(AppRoutes.discovery),
                    child: Text(l10n.sendCount(files.length)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickButton extends StatelessWidget {
  const _PickButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(icon: Icon(icon), label: Text(label), onPressed: onPressed);
  }
}

class _SelectedTile extends StatelessWidget {
  const _SelectedTile({required this.file, required this.onRemove});

  final SendFile file;
  final VoidCallback onRemove;

  static const _imageTypes = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'};

  @override
  Widget build(BuildContext context) {
    final dot = file.name.lastIndexOf('.');
    final ext = dot < 0 ? '' : file.name.substring(dot + 1).toLowerCase();
    final isImage = _imageTypes.contains(ext) && !kIsWeb;

    return ZajelCard(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          if (isImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(file.file.path),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                cacheWidth: 96, // decode small: the original may be huge
                errorBuilder: (_, _, _) => IconBadge(icon: fileIconFor(file.name)),
              ),
            )
          else
            IconBadge(icon: fileIconFor(file.name)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(formatBytes(file.size), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: onRemove),
        ],
      ),
    );
  }
}

class _AppsList extends ConsumerWidget {
  const _AppsList({
    required this.query,
    required this.onQuery,
    required this.selectedPaths,
    required this.onToggle,
  });

  final String query;
  final ValueChanged<String> onQuery;
  final Set<String> selectedPaths;
  final void Function(NativeAppInfo app, bool selected) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final apps = ref.watch(installedAppsProvider);

    return apps.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(l10n.appsLoading)),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(l10n.appsUnsupported)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(!kIsWeb && Platform.isAndroid ? l10n.appsNone : l10n.appsUnsupported),
            ),
          );
        }
        final shown = [
          for (final app in list)
            if (app.name.toLowerCase().contains(query.toLowerCase())) app,
        ];
        return Column(
          children: [
            TextField(
              onChanged: onQuery,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search)),
            ),
            const SizedBox(height: 8),
            for (final app in shown)
              CheckboxListTile(
                value: selectedPaths.contains(app.apkPath),
                onChanged: (value) => onToggle(app, value ?? false),
                secondary: const IconBadge(icon: Icons.android, size: 40),
                title: Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(formatBytes(app.size)),
              ),
          ],
        );
      },
    );
  }
}
