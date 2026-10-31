import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/router/app_router.dart';
import '../../core/transfer/send_client.dart';
import '../../core/transfer/transfer_providers.dart';
import '../../l10n/l10n.dart';

class FilePickerScreen extends ConsumerWidget {
  const FilePickerScreen({super.key});

  Future<void> _pick(WidgetRef ref) async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return;

    final notifier = ref.read(selectedFilesProvider.notifier);
    final files = [...ref.read(selectedFilesProvider)];
    for (final item in picked) {
      final path = item.path;
      if (path == null) continue;
      files.add(
        await SendFile.fromPath(
          path,
          id: '${DateTime.now().microsecondsSinceEpoch}-${files.length}',
          name: item.name,
        ),
      );
    }
    notifier.set(files);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final files = ref.watch(selectedFilesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.filePickerTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: Text(l10n.chooseFiles),
                onPressed: () => _pick(ref),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: files.isEmpty
                    ? Center(child: Text(l10n.noFilesSelected))
                    : ListView.separated(
                        itemCount: files.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final file = files[index];
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.insert_drive_file),
                              title: Text(
                                file.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(formatBytes(file.size)),
                              trailing: IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => ref
                                    .read(selectedFilesProvider.notifier)
                                    .set([...files]..removeAt(index)),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: files.isEmpty
                    ? null
                    : () => context.push(AppRoutes.discovery),
                child: Text(l10n.sendCount(files.length)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
