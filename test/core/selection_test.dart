import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/transfer/send_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zajel/core/transfer/transfer_providers.dart';
import 'package:zajel/features/settings/app_settings.dart';

import '../support/transfer_harness.dart';

/// The selection never holds a file twice and never loses an addition that
/// arrived while another one was being prepared (AUDIT.md, C3 and C4).
void main() {
  late ProviderContainer container;

  SendFile file(String id, String path, {int size = 1}) =>
      SendFile(id: id, file: File(path), size: size, name: path.split('/').last);

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  SelectedFilesNotifier notifier() => container.read(selectedFilesProvider.notifier);
  List<String> ids() => [for (final f in container.read(selectedFilesProvider)) f.id];

  test('the same id is added once (a double tap on a photo)', () {
    notifier()
      ..add(file('media-1', '/a.jpg'))
      ..add(file('media-1', '/a.jpg'));
    expect(ids(), ['media-1']);
  });

  test('the same path is added once, whatever the id', () {
    notifier()
      ..add(file('file-1-0', '/doc.pdf'))
      ..add(file('file-2-0', '/doc.pdf'));
    expect(ids(), ['file-1-0']);
  });

  test('an addition made during a slow one is kept', () async {
    // Two lookups run at the same time and finish in the other order.
    Future<void> addLater(String id, Duration delay) async {
      await Future<void>.delayed(delay);
      notifier().add(file(id, '/$id'));
    }

    await Future.wait([
      addLater('slow', const Duration(milliseconds: 30)),
      addLater('fast', const Duration(milliseconds: 5)),
    ]);
    expect(ids(), unorderedEquals(['slow', 'fast']));
  });

  test('remove and removeWhere take out only what they name', () {
    notifier().addAll([file('a', '/a'), file('b', '/b'), file('c', '/c.apk')]);
    notifier().remove('a');
    expect(ids(), ['b', 'c']);
    notifier().removeWhere((f) => f.file.path.endsWith('.apk'));
    expect(ids(), ['b']);
  });

  group('surviving a restart (AUDIT.md, C5)', () {
    late Directory dir;
    late SharedPreferences prefs;

    setUp(() async {
      dir = await createTestDir('zajel_selection_');
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    tearDown(() => deleteTestDir(dir));

    ProviderContainer started() {
      final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      return c;
    }

    Future<List<String>> idsAfterStart(ProviderContainer c) async {
      c.read(selectedFilesProvider);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return [for (final f in c.read(selectedFilesProvider)) f.id];
    }

    test('a selection made a moment ago comes back, without files that are gone', () async {
      final kept = await writeTestFile(dir, 'kept.bin', 300);
      final gone = await writeTestFile(dir, 'gone.bin', 100);
      final first = started();
      first.read(selectedFilesProvider.notifier).addAll([
        await SendFile.fromPath(kept.path, id: 'file-1-0'),
        await SendFile.fromPath(gone.path, id: 'file-1-1'),
      ]);
      await gone.delete();

      // Android closed the app while the system picker was open; it starts again.
      final second = started();
      expect(await idsAfterStart(second), ['file-1-0']);
      expect(second.read(selectedFilesProvider).single.size, 300);
    });

    test('an old selection does not come back', () async {
      final file = await writeTestFile(dir, 'old.bin', 10);
      final old = DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch;
      await prefs.setString(
        'pendingSelection',
        jsonEncode({
          'at': old,
          'files': [
            {'id': 'file-1-0', 'path': file.path, 'name': 'old.bin'},
          ],
        }),
      );
      expect(await idsAfterStart(started()), isEmpty);
      expect(prefs.getString('pendingSelection'), isNull);
    });

    test('clearing the selection forgets it', () async {
      final file = await writeTestFile(dir, 'a.bin', 10);
      final c = started();
      c.read(selectedFilesProvider.notifier).add(await SendFile.fromPath(file.path, id: 'file-1-0'));
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getString('pendingSelection'), isNotNull);

      c.read(selectedFilesProvider.notifier).clear();
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getString('pendingSelection'), isNull);
      expect(await idsAfterStart(started()), isEmpty);
    });

    test('unreadable saved data is ignored', () async {
      await prefs.setString('pendingSelection', 'not json');
      expect(await idsAfterStart(started()), isEmpty);
    });
  });
}
