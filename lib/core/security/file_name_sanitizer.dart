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
