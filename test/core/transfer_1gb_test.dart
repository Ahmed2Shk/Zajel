@Tags(['slow'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/transfer/receive_server.dart';
import 'package:zajel/core/transfer/send_client.dart';

import '../support/transfer_harness.dart';

const _oneGiB = 1024 * 1024 * 1024;

/// Takes minutes and needs about 2 GB of free disk. Run with:
///   ZAJEL_SLOW=1 flutter test test/core/transfer_1gb_test.dart
void main() {
  test(
    'transfers 1 GB over TLS with a matching SHA-256 and flat memory use',
    () async {
      final source = await createTestDir('zajel_1gb_src_');
      final harness = await TransferHarness.start();
      addTearDown(() async {
        await harness.dispose();
        await source.delete(recursive: true);
      });

      final file = await writeTestFile(source, 'big.bin', _oneGiB);
      final send = await SendFile.fromPath(file.path, id: 'big');
      final expected = await sha256OfFile(file);

      var peakRss = 0;
      final baselineRss = ProcessInfo.currentRss;
      final progress = harness.server.events.listen((event) {
        if (event is FileProgress && event.received % (64 << 20) < (1 << 16)) {
          if (ProcessInfo.currentRss > peakRss) peakRss = ProcessInfo.currentRss;
        }
      });

      final stopwatch = Stopwatch()..start();
      final session = await harness.prepare([send]);
      await harness.sender.upload(session: session, files: [send]);
      stopwatch.stop();
      await progress.cancel();

      final received = File('${harness.downloads.path}/big.bin');
      expect(await received.length(), _oneGiB);
      expect(await sha256OfFile(received), expected);

      final mbPerSecond = _oneGiB / (1 << 20) / (stopwatch.elapsedMilliseconds / 1000);
      // ignore: avoid_print
      print('1 GB loopback: ${mbPerSecond.toStringAsFixed(1)} MB/s, '
          'RSS grew ${((peakRss - baselineRss) / (1 << 20)).toStringAsFixed(0)} MB');

      // Streaming means memory must not scale with the file size.
      expect(peakRss - baselineRss, lessThan(300 * (1 << 20)));
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: Platform.environment['ZAJEL_SLOW'] == null
        ? 'slow: set ZAJEL_SLOW=1 to run'
        : null,
  );
}
