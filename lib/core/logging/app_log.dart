import 'dart:io';

/// A small local log the user can export. Nothing here is sent anywhere.
///
/// It records lifecycle events and errors, never file names, file contents,
/// PINs or session tokens. Everything goes through [redact] first, because
/// exception messages often carry URLs with secrets in the query string.
class AppLog {
  AppLog(this.file, {this.maxBytes = 256 * 1024});

  /// Opens the log in [directory], creating it if needed.
  static Future<AppLog> open(Directory directory) async {
    await directory.create(recursive: true);
    return AppLog(File('${directory.path}/zajel.log'));
  }

  final File file;

  /// When the log grows past this it is moved to `zajel.log.1`, replacing the
  /// previous one, so it never takes much space.
  final int maxBytes;

  File get _rotated => File('${file.path}.1');

  void info(String tag, String message) => _write('INFO ', tag, message);

  void warn(String tag, String message) => _write('WARN ', tag, message);

  /// Logs the kind of error and its redacted message, plus a short stack.
  void error(String tag, Object error, [StackTrace? stack]) {
    final lines = (stack?.toString() ?? '').split('\n').take(6).join(' | ');
    _write(
      'ERROR',
      tag,
      '${error.runtimeType}: ${error.toString()}${lines.isEmpty ? '' : ' @ $lines'}',
    );
  }

  void _write(String level, String tag, String message) {
    try {
      if (file.existsSync() && file.lengthSync() > maxBytes) {
        if (_rotated.existsSync()) _rotated.deleteSync();
        file.renameSync(_rotated.path);
      }
      final line =
          '${DateTime.now().toIso8601String()} $level $tag ${redact(message).replaceAll('\n', ' ')}\n';
      file.writeAsStringSync(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // Logging must never be the thing that crashes the app.
    }
  }

  /// Older entries first.
  String readAll() {
    final parts = <String>[];
    for (final f in [_rotated, file]) {
      try {
        if (f.existsSync()) parts.add(f.readAsStringSync());
      } catch (_) {}
    }
    return parts.join();
  }

  void clear() {
    for (final f in [file, _rotated]) {
      try {
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  static final _secretParam = RegExp(
    // The name must start a word, so the `t` in `offset=0` is left alone.
    r'''(?<![A-Za-z0-9_])(token|pin|sessionid|fileid|t)(=|":\s*")[^&\s"',)]+''',
    caseSensitive: false,
  );

  /// Blanks the values of secrets that can appear in URLs or JSON. Only the
  /// names `token`, `pin`, `sessionId`, `fileId` and `t` are treated this way.
  static String redact(String text) => text.replaceAllMapped(
    _secretParam,
    (m) => '${m[1]}${m[2]}<redacted>',
  );

  /// A header with the facts that help when reading a log someone sends in.
  static String environmentSummary({required String locale}) => [
    'Zajel log',
    'platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    'dart: ${Platform.version.split(' ').first}',
    'locale: $locale',
    '',
  ].join('\n');
}
