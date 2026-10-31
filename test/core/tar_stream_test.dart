import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/transfer/tar_stream.dart';

TarEntry _entry(String name, List<int> data, {int? chunk}) => TarEntry(
  name: name,
  size: data.length,
  open: () async* {
    final step = chunk ?? data.length;
    for (var i = 0; i < data.length; i += step) {
      yield data.sublist(i, i + step > data.length ? data.length : i + step);
    }
  },
);

Future<Uint8List> _encode(List<TarEntry> entries) async {
  final out = BytesBuilder();
  await for (final chunk in tarEncode(entries)) {
    out.add(chunk);
  }
  return out.toBytes();
}

Future<Map<String, List<int>>> _decode(Stream<List<int>> input) async {
  final files = <String, List<int>>{};
  await TarReader(input).read((header, content) async {
    final data = <int>[];
    while (true) {
      final piece = await content.read();
      if (piece == null) break;
      data.addAll(piece);
    }
    files[header.name] = data;
  });
  return files;
}

Stream<List<int>> _split(Uint8List bytes, int size) async* {
  for (var i = 0; i < bytes.length; i += size) {
    yield bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size);
  }
}

void main() {
  trailingDataTests();
  test('round-trips files of awkward sizes', () async {
    final entries = [
      _entry('a', List.generate(0, (i) => i)),
      _entry('b', List.generate(1, (i) => 7)),
      _entry('c', List.generate(511, (i) => i % 251)),
      _entry('d', List.generate(512, (i) => i % 251)),
      _entry('e', List.generate(513, (i) => i % 251)),
      _entry('f', List.generate(100000, (i) => i % 253), chunk: 777),
    ];
    final bytes = await _encode(entries);
    expect(bytes.length, tarLength(entries));
    expect(bytes.length % tarBlockSize, 0);

    final files = await _decode(Stream.value(bytes));
    expect(files.keys, ['a', 'b', 'c', 'd', 'e', 'f']);
    for (final entry in entries) {
      final expected = await entry.open().expand((b) => b).toList();
      expect(files[entry.name], expected, reason: entry.name);
    }
  });

  test('reads the same archive delivered in tiny, odd-sized pieces', () async {
    final entries = [
      _entry('x', List.generate(1500, (i) => i % 200)),
      _entry('y', List.generate(30, (i) => i)),
    ];
    final bytes = await _encode(entries);
    for (final size in [1, 7, 511, 512, 513, 4096]) {
      final files = await _decode(_split(bytes, size));
      expect(files['x'], List.generate(1500, (i) => i % 200), reason: '$size');
      expect(files['y'], List.generate(30, (i) => i), reason: '$size');
    }
  });

  test('unicode names survive', () async {
    final files = await _decode(
      Stream.value(await _encode([_entry('ملف-1', [1, 2, 3])])),
    );
    expect(files['ملف-1'], [1, 2, 3]);
  });

  test('an unread entry is skipped, not misread', () async {
    final bytes = await _encode([
      _entry('skip', List.filled(2000, 5)),
      _entry('keep', [9, 9]),
    ]);
    final seen = <String>[];
    await TarReader(Stream.value(bytes)).read((header, content) async {
      seen.add(header.name);
      if (header.name == 'keep') {
        expect(await content.read(), [9, 9]);
      }
    });
    expect(seen, ['skip', 'keep']);
  });

  test('an empty archive is just the end marker', () async {
    expect(await _decode(Stream.value(await _encode([]))), isEmpty);
  });

  group('rejects malformed archives', () {
    late Uint8List good;

    setUp(() async {
      good = await _encode([_entry('f', List.filled(700, 1))]);
    });

    Future<void> expectBad(Uint8List bytes) =>
        expectLater(_decode(Stream.value(bytes)), throwsA(isA<TarFormatException>()));

    test('truncated in the header', () => expectBad(good.sublist(0, 300)));
    test('truncated in the content', () => expectBad(good.sublist(0, 800)));
    test('missing end marker', () => expectBad(good.sublist(0, good.length - 1024)));
    test('half an end marker', () => expectBad(good.sublist(0, good.length - 512)));

    test('corrupted checksum', () {
      final bad = Uint8List.fromList(good)..[10] ^= 0xff;
      return expectBad(bad);
    });

    test('a directory entry', () {
      final bad = Uint8List.fromList(good);
      bad[156] = 0x35; // '5'
      // Keep the checksum valid so the type check is what fails.
      var sum = 0;
      for (var i = 0; i < 512; i++) {
        sum += (i >= 148 && i < 156) ? 0x20 : bad[i];
      }
      bad.setRange(148, 154, ascii.encode(sum.toRadixString(8).padLeft(6, '0')));
      return expectBad(bad);
    });

    test('a symlink entry', () {
      final bad = Uint8List.fromList(good);
      bad[156] = 0x32; // '2'
      var sum = 0;
      for (var i = 0; i < 512; i++) {
        sum += (i >= 148 && i < 156) ? 0x20 : bad[i];
      }
      bad.setRange(148, 154, ascii.encode(sum.toRadixString(8).padLeft(6, '0')));
      return expectBad(bad);
    });

    test('empty input', () => expectBad(Uint8List(0)));
  });

  group('writer', () {
    test('refuses names over 100 bytes', () async {
      await expectLater(
        _encode([_entry('n' * 101, [1])]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('notices a file that changed size while being sent', () async {
      final lying = TarEntry(name: 'x', size: 10, open: () => Stream.value([1, 2, 3]));
      await expectLater(_encode([lying]), throwsA(isA<StateError>()));
    });

    test('reports per-entry progress', () async {
      final seen = <String, int>{};
      await tarEncode(
        [_entry('p', List.filled(1000, 1), chunk: 300)],
        onBytes: (name, bytes) => seen[name] = bytes,
      ).drain<void>();
      expect(seen['p'], 1000);
    });
  });
}

void trailingDataTests() {
  test('a little padding after the end marker is fine', () async {
    final bytes = BytesBuilder()
      ..add(await _encode([_entry('a', [1, 2, 3])]))
      ..add(Uint8List(4096));
    expect((await _decode(Stream.value(bytes.toBytes())))['a'], [1, 2, 3]);
  });

  test('a flood after the end marker is rejected', () async {
    final head = await _encode([_entry('a', [1, 2, 3])]);
    Stream<List<int>> flood() async* {
      yield head;
      for (var i = 0; i < 40; i++) {
        yield Uint8List(64 * 1024);
      }
    }

    await expectLater(_decode(flood()), throwsA(isA<TarFormatException>()));
  });
}
