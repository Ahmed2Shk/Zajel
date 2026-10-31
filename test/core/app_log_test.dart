import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/logging/app_log.dart';

void main() {
  late Directory dir;
  late AppLog log;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('zajel_log_');
    log = await AppLog.open(dir);
  });

  tearDown(() => dir.delete(recursive: true));

  group('redact', () {
    test('blanks secrets in URLs', () {
      final text = AppLog.redact(
        'POST /api/localsend/v2/upload?sessionId=abc123&fileId=f9&token=SeCrEt&offset=0',
      );
      expect(text, isNot(contains('abc123')));
      expect(text, isNot(contains('SeCrEt')));
      expect(text, isNot(contains('f9')));
      expect(text, contains('offset=0'));
      expect(text, contains('token=<redacted>'));
    });

    test('blanks the PIN and the web share token', () {
      expect(AppLog.redact('?pin=123456'), '?pin=<redacted>');
      expect(AppLog.redact('http://192.168.1.5:53318/?t=AbCdEf'), contains('t=<redacted>'));
      expect(AppLog.redact('http://192.168.1.5:53318/?t=AbCdEf'), isNot(contains('AbCdEf')));
    });

    test('blanks secrets in JSON', () {
      final text = AppLog.redact('{"token": "abc", "sessionId":"xyz", "size": 5}');
      expect(text, isNot(contains('abc')));
      expect(text, isNot(contains('xyz')));
      expect(text, contains('"size": 5'));
    });

    test('leaves ordinary text alone', () {
      expect(AppLog.redact('service started on port 53317'), 'service started on port 53317');
    });
  });

  group('writing', () {
    test('lines carry a time, level and tag', () {
      log.info('service', 'started');
      log.warn('net', 'slow');
      final lines = log.readAll().trim().split('\n');
      expect(lines, hasLength(2));
      expect(lines[0], matches(RegExp(r'^\d{4}-\d\d-\d\dT.* INFO  service started$')));
      expect(lines[1], contains('WARN  net slow'));
    });

    test('errors record the type, a redacted message and a short stack', () {
      try {
        throw HttpException('failed', uri: Uri.parse('https://10.0.0.2/x?token=SeCrEt'));
      } catch (e, st) {
        log.error('send', e, st);
      }
      final text = log.readAll();
      expect(text, contains('ERROR send HttpException'));
      expect(text, isNot(contains('SeCrEt')));
      expect(text.trim().split('\n'), hasLength(1), reason: 'one line per entry');
    });

    test('messages cannot forge extra lines', () {
      log.info('x', 'one\nfake line');
      expect(log.readAll().trim().split('\n'), hasLength(1));
    });

    test('a log that grows too large rotates and keeps the newest', () {
      final small = AppLog(File('${dir.path}/small.log'), maxBytes: 500);
      for (var i = 0; i < 50; i++) {
        small.info('t', 'entry number $i with some padding to take space');
      }
      expect(File('${dir.path}/small.log.1').existsSync(), isTrue);
      final all = small.readAll();
      expect(all, contains('entry number 49'));
      expect(all, isNot(contains('entry number 0 ')));
      expect(File('${dir.path}/small.log').lengthSync(), lessThan(1500));
    });

    test('clear removes everything', () {
      log.info('a', 'b');
      log.clear();
      expect(log.readAll(), isEmpty);
    });

    test('an unwritable log does not throw', () {
      final broken = AppLog(File('${dir.path}/missing-dir/zajel.log'));
      expect(() => broken.info('a', 'b'), returnsNormally);
      expect(broken.readAll(), isEmpty);
    });
  });

  test('the environment summary has no personal data', () {
    final text = AppLog.environmentSummary(locale: 'ar');
    expect(text, contains('Zajel log'));
    expect(text, contains('locale: ar'));
  });
}
