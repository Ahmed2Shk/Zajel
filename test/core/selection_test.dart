import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/transfer/send_client.dart';
import 'package:zajel/core/transfer/transfer_providers.dart';

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
}
