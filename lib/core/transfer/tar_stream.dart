import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Minimal streaming ustar writer and reader, used to send many small files as
/// one request (Zajel-to-Zajel only). Only regular files are supported.
///
/// Entry names are never used as paths. The sender puts file ids in them and
/// the receiver maps ids to its own sanitized destinations.

const tarBlockSize = 512;

class TarFormatException implements Exception {
  const TarFormatException(this.message);

  final String message;

  @override
  String toString() => 'TarFormatException: $message';
}

/// One file to put in an archive. [open] is called once, when the entry is
/// reached, so only one file is open at a time.
class TarEntry {
  const TarEntry({required this.name, required this.size, required this.open});

  final String name;
  final int size;
  final Stream<List<int>> Function() open;
}

/// Total archive length for [entries], so a request can announce its size.
int tarLength(Iterable<TarEntry> entries) {
  var total = 2 * tarBlockSize; // the end-of-archive marker
  for (final entry in entries) {
    total += tarBlockSize + _padded(entry.size);
  }
  return total;
}

int _padded(int size) => (size + tarBlockSize - 1) ~/ tarBlockSize * tarBlockSize;

/// Streams [entries] as a tar archive. [onBytes] reports (entryName,
/// bytesOfThatEntrySoFar) as content goes by.
Stream<List<int>> tarEncode(
  Iterable<TarEntry> entries, {
  void Function(String name, int bytes)? onBytes,
}) async* {
  for (final entry in entries) {
    yield _header(entry.name, entry.size);
    var sent = 0;
    await for (final chunk in entry.open()) {
      sent += chunk.length;
      if (sent > entry.size) {
        throw StateError('${entry.name} grew while being sent');
      }
      yield chunk;
      onBytes?.call(entry.name, sent);
    }
    if (sent != entry.size) {
      throw StateError('${entry.name} changed size while being sent');
    }
    onBytes?.call(entry.name, entry.size); // also covers empty files
    final padding = _padded(entry.size) - entry.size;
    if (padding > 0) yield Uint8List(padding);
  }
  yield Uint8List(2 * tarBlockSize);
}

Uint8List _header(String name, int size) {
  final nameBytes = utf8.encode(name);
  if (nameBytes.isEmpty || nameBytes.length > 100) {
    throw ArgumentError.value(name, 'name', 'must be 1-100 bytes');
  }
  final block = Uint8List(tarBlockSize);
  block.setRange(0, nameBytes.length, nameBytes);
  _putOctal(block, 100, 8, 420); // mode 0644
  _putOctal(block, 108, 8, 0); // uid
  _putOctal(block, 116, 8, 0); // gid
  _putOctal(block, 124, 12, size);
  _putOctal(block, 136, 12, 0); // mtime: receivers keep their own
  block[156] = 0x30; // '0', regular file
  block.setRange(257, 263, ascii.encode('ustar\x00'));
  block.setRange(263, 265, ascii.encode('00'));

  block.fillRange(148, 156, 0x20); // checksum is computed over spaces
  final sum = block.fold<int>(0, (a, b) => a + b);
  final text = sum.toRadixString(8).padLeft(6, '0');
  block.setRange(148, 154, ascii.encode(text));
  block[154] = 0;
  block[155] = 0x20;
  return block;
}

void _putOctal(Uint8List block, int offset, int length, int value) {
  final text = value.toRadixString(8).padLeft(length - 1, '0');
  if (text.length > length - 1) {
    throw ArgumentError.value(value, 'value', 'does not fit in $length bytes');
  }
  block.setRange(offset, offset + length - 1, ascii.encode(text));
  block[offset + length - 1] = 0;
}

/// A regular-file entry found while reading an archive.
class TarHeader {
  const TarHeader(this.name, this.size);

  final String name;
  final int size;
}

/// Reads an archive from [input]. [onEntry] is called for each file with a
/// reader for its content; it must consume exactly [TarHeader.size] bytes
/// through [TarContent.read], or none (the rest is skipped).
class TarReader {
  TarReader(Stream<List<int>> input) : _iterator = StreamIterator(input);

  final StreamIterator<List<int>> _iterator;
  Uint8List _buffer = Uint8List(0);
  int _offset = 0;

  /// Walks the archive. Throws [TarFormatException] on anything malformed:
  /// bad checksum, non-regular entries, truncation, or a missing end marker.
  Future<void> read(
    Future<void> Function(TarHeader header, TarContent content) onEntry,
  ) async {
    try {
      while (true) {
        final block = await _readExact(tarBlockSize);
        if (block == null) {
          throw const TarFormatException('archive ended without an end marker');
        }
        if (block.every((b) => b == 0)) {
          // Second zero block of the end marker.
          final second = await _readExact(tarBlockSize);
          if (second == null || second.any((b) => b != 0)) {
            throw const TarFormatException('bad end marker');
          }
          await _consumeRest();
          return;
        }
        final header = _parseHeader(block);
        final content = TarContent._(this, header.size);
        await onEntry(header, content);
        await content._finish();
        await _skip(_padded(header.size) - header.size);
      }
    } finally {
      await _iterator.cancel();
    }
  }

  /// Reads the input to its end. An HTTP server treats a body that is left
  /// unread as an aborted request and drops the connection, so the reply could
  /// not be sent. Padding after the end marker is normal; a lot of it is not.
  Future<void> _consumeRest() async {
    var extra = _buffer.length - _offset;
    _offset = _buffer.length;
    while (await _iterator.moveNext()) {
      extra += _iterator.current.length;
      if (extra > _maxTrailingBytes) {
        throw const TarFormatException('data after the end marker');
      }
    }
  }

  static const _maxTrailingBytes = 1024 * 1024;

  TarHeader _parseHeader(Uint8List block) {
    final stored = _parseOctal(block, 148, 8);
    var sum = 0;
    for (var i = 0; i < tarBlockSize; i++) {
      sum += (i >= 148 && i < 156) ? 0x20 : block[i];
    }
    if (stored != sum) throw const TarFormatException('bad header checksum');

    final type = block[156];
    if (type != 0x30 && type != 0) {
      throw const TarFormatException('only regular files are accepted');
    }
    var end = 0;
    while (end < 100 && block[end] != 0) {
      end++;
    }
    if (end == 0) throw const TarFormatException('empty entry name');
    final String name;
    try {
      name = utf8.decode(block.sublist(0, end));
    } on FormatException {
      throw const TarFormatException('entry name is not UTF-8');
    }
    final size = _parseOctal(block, 124, 12);
    return TarHeader(name, size);
  }

  int _parseOctal(Uint8List block, int offset, int length) {
    final text = ascii
        .decode(block.sublist(offset, offset + length), allowInvalid: true)
        .replaceAll('\x00', '')
        .trim();
    final value = int.tryParse(text, radix: 8);
    if (value == null || value < 0) {
      throw const TarFormatException('bad number in header');
    }
    return value;
  }

  /// Pulls the next piece of input into the buffer. False at end of input.
  Future<bool> _fill() async {
    if (_offset < _buffer.length) return true;
    if (!await _iterator.moveNext()) return false;
    final next = _iterator.current;
    _buffer = next is Uint8List ? next : Uint8List.fromList(next);
    _offset = 0;
    return true;
  }

  /// Exactly [count] bytes, or null if the input ended before the first one.
  Future<Uint8List?> _readExact(int count) async {
    final out = Uint8List(count);
    var filled = 0;
    while (filled < count) {
      if (!await _fill()) {
        if (filled == 0) return null;
        throw const TarFormatException('archive is truncated');
      }
      final n = _min(count - filled, _buffer.length - _offset);
      out.setRange(filled, filled + n, _buffer, _offset);
      filled += n;
      _offset += n;
    }
    return out;
  }

  Future<void> _skip(int count) async {
    var left = count;
    while (left > 0) {
      if (!await _fill()) throw const TarFormatException('archive is truncated');
      final n = _min(left, _buffer.length - _offset);
      _offset += n;
      left -= n;
    }
  }

  /// Up to [max] bytes without copying, or null at the end of input.
  Future<Uint8List?> _readSome(int max) async {
    if (!await _fill()) return null;
    final n = _min(max, _buffer.length - _offset);
    final view = Uint8List.sublistView(_buffer, _offset, _offset + n);
    _offset += n;
    return view;
  }

  static int _min(int a, int b) => a < b ? a : b;
}

/// The content of one archive entry, read piece by piece.
class TarContent {
  TarContent._(this._reader, this.size) : _left = size;

  final TarReader _reader;
  final int size;
  int _left;

  int get remaining => _left;

  /// The next piece of the file, or null when all [size] bytes were read.
  /// The returned view is only valid until the next call.
  Future<Uint8List?> read() async {
    if (_left == 0) return null;
    final piece = await _reader._readSome(_left);
    if (piece == null) throw const TarFormatException('archive is truncated');
    _left -= piece.length;
    return piece;
  }

  Future<void> _finish() => _reader._skip(_left).then((_) => _left = 0);
}
