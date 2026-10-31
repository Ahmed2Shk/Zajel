import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/security/file_name_sanitizer.dart';

void main() {
  group('sanitizeReceivedFileName', () {
    test('accepts plain names and relative sub-folders', () {
      expect(sanitizeReceivedFileName('photo.jpg'), 'photo.jpg');
      expect(sanitizeReceivedFileName('my image.png'), 'my image.png');
      expect(sanitizeReceivedFileName('trip/day1/a.jpg'), 'trip/day1/a.jpg');
      expect(sanitizeReceivedFileName('ملف.pdf'), 'ملف.pdf');
    });

    for (final bad in [
      '',
      '..',
      '../evil.txt',
      '../../evil.txt',
      'a/../../evil.txt',
      'a/./b',
      '/etc/passwd',
      r'C:\Windows\evil.dll',
      'C:/Windows/evil.dll',
      r'..\evil.txt',
      r'a\b',
      'a//b',
      'trailing/',
      'name\x00.txt',
      'line\nbreak.txt',
      'tab\t.txt',
      'bell\x07.txt',
      'del\x7f.txt',
      ' leading.txt',
      'dot.',
    ]) {
      test('rejects ${bad.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '?')}', () {
        expect(
          () => sanitizeReceivedFileName(bad),
          throwsA(isA<UnsafeFileNameException>()),
        );
      });
    }
  });
}
