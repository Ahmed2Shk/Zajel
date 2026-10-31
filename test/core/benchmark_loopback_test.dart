@Tags(['slow'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/transfer/send_client.dart';

import '../support/transfer_harness.dart';

const _mib = 1024 * 1024;

/// Measures the transfer paths over loopback and prints a table for
/// docs/BENCHMARKS.md. Loopback has no Wi-Fi in the way, so this shows the
/// ceiling of the code, not what two phones will reach.
///
///   ZAJEL_SLOW=1 flutter test test/core/benchmark_loopback_test.dart
void main() {
  test(
    'loopback throughput: single stream vs parallel chunks',
    () async {
      const size = 1024 * _mib;
      final source = await createTestDir('zajel_bench_src_');
      final harness = await TransferHarness.start();
      addTearDown(() async {
        await harness.dispose();
        await source.delete(recursive: true);
      });

      final file = await SendFile.fromPath(
        (await writeTestFile(source, 'bench.bin', size)).path,
        id: 'bench',
      );

      Future<double> run(String label, {required bool chunked, UploadOptions? options}) async {
        harness.sender.offerExtensions = chunked;
        final session = await harness.prepare([file]);
        final watch = Stopwatch()..start();
        await harness.sender.upload(
          session: session,
          files: [file],
          options: options ?? const UploadOptions(),
        );
        watch.stop();
        final speed = size / _mib / (watch.elapsedMilliseconds / 1000);
        // ignore: avoid_print
        print('BENCH $label: ${speed.toStringAsFixed(1)} MB/s');
        // Free the disk before the next run.
        for (final entity in harness.downloads.listSync()) {
          entity.deleteSync(recursive: true);
        }
        return speed;
      }

      final network = await harness.sender.benchmark(
        address: InternetAddress.loopbackIPv4,
        port: harness.server.port,
        expectedFingerprint: receiverIdentity.fingerprint,
        bytes: size,
      );
      // ignore: avoid_print
      print('BENCH network only (no disk): '
          '${network.megabytesPerSecond.toStringAsFixed(1)} MB/s, '
          'connect ${network.connectMs} ms');

      final single = await run('single stream (LocalSend style)', chunked: false);
      for (final parallel in [1, 2, 3, 4]) {
        await run(
          '$parallel connection(s), 8 MB chunks',
          chunked: true,
          options: UploadOptions(parallel: parallel),
        );
      }
      expect(single, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 15)),
    skip: Platform.environment['ZAJEL_SLOW'] == null
        ? 'slow: set ZAJEL_SLOW=1 to run'
        : null,
  );
}
