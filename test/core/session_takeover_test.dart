import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/transfer/receive_server.dart';
import 'package:zajel/core/transfer/send_client.dart';

import '../support/transfer_harness.dart';

/// A transfer that broke without a cancel must not block the receiver for the
/// whole idle timeout when the same sender tries again (AUDIT.md, A3).
void main() {
  TransferHarness? harness;
  late Directory source;

  TransferHarness h() => harness!;

  setUp(() async {
    source = await createTestDir('zajel_takeover_src_');
  });

  tearDown(() async {
    await harness?.dispose();
    harness = null;
    await deleteTestDir(source);
  });

  Future<SendFile> sourceFile(String name, int size) async =>
      SendFile.fromPath((await writeTestFile(source, name, size)).path, id: name);

  List<String> parts() => h().downloads
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.zajel-part'))
      .toList();

  test('a sender that comes back after its session went silent takes its place', () async {
    harness = await TransferHarness.start(takeoverAfter: const Duration(milliseconds: 200));
    final file = await sourceFile('a.bin', 64 * 1024);
    final events = <ReceiveEvent>[];
    h().server.events.listen(events.add);

    final broken = await h().prepare([file]); // ...and then the sender's app dies
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final again = await h().prepare([file]);
    expect(again.sessionId, isNot(broken.sessionId));
    expect(events.whereType<SessionEnded>().single.cancelled, isTrue);

    await h().sender.upload(session: again, files: [file]);
    expect(await File('${h().downloads.path}/a.bin').length(), file.size);
    expect(parts(), isEmpty);
  });

  test('while its session is still active the same sender is told "busy"', () async {
    harness = await TransferHarness.start(); // 10 s before a takeover
    final file = await sourceFile('a.bin', 1024);
    await h().prepare([file]);

    await expectLater(
      h().prepare([file]),
      throwsA(isA<SendException>().having((e) => e.busy, 'busy', isTrue)),
    );
  });

  test('data keeps a session alive against a takeover', () async {
    harness = await TransferHarness.start(takeoverAfter: const Duration(milliseconds: 400));
    final a = await sourceFile('a.bin', 64 * 1024);
    final b = await sourceFile('b.bin', 1024);
    final session = await h().prepare([a, b]);

    await Future<void>.delayed(const Duration(milliseconds: 300));
    await h().sender.upload(session: session, files: [a]); // activity resets the clock
    await Future<void>.delayed(const Duration(milliseconds: 200));

    await expectLater(
      h().prepare([b]),
      throwsA(isA<SendException>().having((e) => e.busy, 'busy', isTrue)),
    );
  });
}
