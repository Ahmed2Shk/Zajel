/// Thrown when a received file name cannot be made safe.
class UnsafeFileNameException implements Exception {
  const UnsafeFileNameException(this.name);

  final String name;

  @override
  String toString() => 'Unsafe file name: $name';
}

final _controlChars = RegExp(r'[\x00-\x1f\x7f]');
final _windowsDrive = RegExp(r'^[a-zA-Z]:');

/// Validates a file name received from a peer and returns a relative path
/// that is safe to join onto the download folder.
///
/// LocalSend lets senders use `/` to keep folder structure, so sub-folders are
/// allowed. Rejected outright: `..` segments, absolute paths, drive letters,
/// backslashes and control characters. Nothing is silently rewritten, so a
/// hostile name fails instead of landing somewhere unexpected.
String sanitizeReceivedFileName(String name) {
  if (name.isEmpty ||
      _controlChars.hasMatch(name) ||
      name.contains(r'\') ||
      name.startsWith('/') ||
      _windowsDrive.hasMatch(name)) {
    throw UnsafeFileNameException(name);
  }

  final segments = name.split('/');
  for (final segment in segments) {
    if (segment.isEmpty ||
        segment == '.' ||
        segment == '..' ||
        segment.trim() != segment ||
        segment.endsWith('.')) {
      throw UnsafeFileNameException(name);
    }
  }
  return segments.join('/');
}

/// Makes a local file name acceptable to [sanitizeReceivedFileName] before it
/// is offered to a receiver, so one oddly named file ("notes .txt", "draft.")
/// cannot fail a whole batch. Used by the sender on its own files only: what
/// arrives from the network is never rewritten, it is checked.
String normalizeSentFileName(String name) {
  final cleaned = name
      .replaceAll(_controlChars, '_')
      .replaceAll(r'\', '/')
      .replaceFirst(_windowsDrive, '_');
  final segments = <String>[];
  for (final raw in cleaned.split('/')) {
    var segment = raw.trim();
    while (segment.endsWith('.') || segment.endsWith(' ')) {
      segment = segment.substring(0, segment.length - 1);
    }
    if (segment.isEmpty || segment == '..') continue;
    segments.add(segment);
  }
  return segments.isEmpty ? 'file' : segments.join('/');
}
