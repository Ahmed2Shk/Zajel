import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/media/media_library.dart';
import '../../core/platform/platform_api.g.dart';
import '../../core/platform/platform_providers.dart';
import '../../core/router/app_router.dart';
import '../../core/transfer/send_client.dart';
import '../../core/transfer/transfer_providers.dart';
import '../../core/widgets/zajel_widgets.dart';
import '../../l10n/l10n.dart';
import 'media_grid.dart';

enum _PickerTab { photos, videos, apps, files }

class FilePickerScreen extends ConsumerStatefulWidget {
  const FilePickerScreen({super.key});

  @override
  ConsumerState<FilePickerScreen> createState() => _FilePickerScreenState();
}

class _FilePickerScreenState extends ConsumerState<FilePickerScreen> {
  _PickerTab _tab = _PickerTab.photos;

  // A tab is built the first time it is opened and then kept, so scrolling and
  // loaded pictures survive switching tabs, while permission prompts only
  // appear for the tabs the user actually opens.
  final _opened = <_PickerTab>{_PickerTab.photos};

  Future<void> _addPaths(Iterable<({String path, String name})> picked) async {
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

  Future<void> _pickAny() async {
    final picked = await FilePicker.pickFiles();
    await _addPaths([
      for (final f in picked)
        if (f.path != null) (path: f.path!, name: f.name),
    ]);
  }

  void _toggleApp(NativeAppInfo app, bool selected) {
    final notifier = ref.read(selectedFilesProvider.notifier);
    if (selected) {
      _addPaths([(path: app.apkPath, name: '${app.name}.apk')]);
    } else {
      notifier.set([
        for (final f in ref.read(selectedFilesProvider))
          if (f.file.path != app.apkPath) f,
      ]);
    }
  }

  void _review() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SelectionSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final files = ref.watch(selectedFilesProvider);
    final total = files.fold<int>(0, (sum, f) => sum + f.size);

    Widget tabBody(_PickerTab tab) {
      if (!_opened.contains(tab)) return const SizedBox.shrink();
      return switch (tab) {
        _PickerTab.photos => const MediaGrid(kind: MediaKind.image),
        _PickerTab.videos => const MediaGrid(kind: MediaKind.video),
        _PickerTab.apps => _AppsList(onToggle: _toggleApp),
        _PickerTab.files => _FilesTab(onPick: _pickAny),
      };
    }

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
                onSelectionChanged: (value) => setState(() {
                  _tab = value.first;
                  _opened.add(_tab);
                }),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: IndexedStack(
                  index: _PickerTab.values.indexOf(_tab),
                  children: [for (final tab in _PickerTab.values) tabBody(tab)],
                ),
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
                    child: InkWell(
                      onTap: files.isEmpty ? null : _review,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              files.isEmpty ? l10n.noFilesSelected : l10n.selectedItems(files.length),
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            if (files.isNotEmpty)
                              Text(
                                '${l10n.readyToSendSize(formatBytes(total))} · ${l10n.reviewSelection}',
                                style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary),
                              ),
                          ],
                        ),
                      ),
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

class _FilesTab extends ConsumerWidget {
  const _FilesTab({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final files = ref.watch(selectedFilesProvider);
    return ListView(
      children: [
        OutlinedButton.icon(icon: const Icon(Icons.add), label: Text(l10n.chooseFiles), onPressed: onPick),
        const SizedBox(height: 10),
        Text(l10n.filesAndroidNote, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        for (var i = 0; i < files.length; i++) ...[
          SelectedFileTile(
            file: files[i],
            onRemove: () => ref.read(selectedFilesProvider.notifier).set([...files]..removeAt(i)),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// A selected file with a small picture if it is an image, and a remove button.
class SelectedFileTile extends StatelessWidget {
  const SelectedFileTile({required this.file, required this.onRemove, super.key});

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

class _SelectionSheet extends ConsumerWidget {
  const _SelectionSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final files = ref.watch(selectedFilesProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.selectedItems(files.length),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ref.read(selectedFilesProvider.notifier).clear();
                      Navigator.of(context).pop();
                    },
                    child: Text(l10n.clearSelection),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: files.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => SelectedFileTile(
                    file: files[i],
                    onRemove: () => ref.read(selectedFilesProvider.notifier).set([...files]..removeAt(i)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppsList extends ConsumerStatefulWidget {
  const _AppsList({required this.onToggle});

  final void Function(NativeAppInfo app, bool selected) onToggle;

  @override
  ConsumerState<_AppsList> createState() => _AppsListState();
}

class _AppsListState extends ConsumerState<_AppsList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final apps = ref.watch(installedAppsProvider);
    final selectedPaths = ref.watch(
      selectedFilesProvider.select((files) => {for (final f in files) f.file.path}),
    );

    return apps.when(
      loading: () => Center(child: Text(l10n.appsLoading)),
      error: (_, _) => Center(child: Text(l10n.appsUnsupported)),
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Text(!kIsWeb && Platform.isAndroid ? l10n.appsNone : l10n.appsUnsupported),
          );
        }
        final shown = [
          for (final app in list)
            if (app.name.toLowerCase().contains(_query.toLowerCase())) app,
        ];
        return Column(
          children: [
            TextField(
              onChanged: (q) => setState(() => _query = q),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: shown.length,
                itemBuilder: (context, index) {
                  final app = shown[index];
                  return CheckboxListTile(
                    key: ValueKey(app.packageName),
                    value: selectedPaths.contains(app.apkPath),
                    onChanged: (value) => widget.onToggle(app, value ?? false),
                    secondary: _AppIcon(packageName: app.packageName),
                    title: Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(formatBytes(app.size)),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The app's real icon, drawn when the row scrolls into view.
class _AppIcon extends ConsumerWidget {
  const _AppIcon({required this.packageName});

  final String packageName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(appIconProvider(packageName)).value;
    if (bytes == null) return const IconBadge(icon: Icons.android, size: 44);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(bytes, width: 44, height: 44, gaplessPlayback: true),
    );
  }
}
