import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/discovery/multicast_discovery.dart';
import '../../core/logging/log_providers.dart';
import '../../core/transfer/send_client.dart';
import '../../core/transfer/transfer_providers.dart';
import '../../l10n/l10n.dart';

const _mib = 1024 * 1024;

class _Result {
  const _Result(this.benchmark, this.cpuPercent);

  final BenchmarkResult benchmark;

  /// Process CPU time over wall time, so it can pass 100 on multi-core phones.
  /// Null where the platform cannot report it.
  final double? cpuPercent;
}

class BenchmarkScreen extends ConsumerStatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  ConsumerState<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends ConsumerState<BenchmarkScreen> {
  DiscoveredDevice? _peer;
  int _megabytes = 64; // small by default: on a slow link 256 MB takes minutes
  bool _running = false;
  bool _failed = false;

  /// Why the test failed, shown under the general message.
  String? _error;
  _Result? _result;

  Future<void> _run() async {
    final peer = _peer;
    final service = await ref.read(localSendServiceProvider.future);
    if (peer == null || service == null) return;

    setState(() {
      _running = true;
      _failed = false;
      _error = null;
      _result = null;
    });
    try {
      if (!await service.isReachable(peer)) {
        throw const SocketException('The device did not answer');
      }
      final cpuBefore = await service.cpuTimeMs();
      final wall = Stopwatch()..start();
      final benchmark = await service.client.benchmark(
        address: peer.address,
        port: peer.info.port,
        expectedFingerprint: peer.info.fingerprint,
        bytes: _megabytes * _mib,
      );
      wall.stop();
      final cpuAfter = await service.cpuTimeMs();
      final cpu = cpuBefore == null || cpuAfter == null || wall.elapsedMilliseconds == 0
          ? null
          : (cpuAfter - cpuBefore) / wall.elapsedMilliseconds * 100;
      if (mounted) setState(() => _result = _Result(benchmark, cpu));
    } catch (e, stack) {
      ref.read(appLogProvider)?.error('benchmark', e, stack);
      if (mounted) {
        setState(() {
          _failed = true;
          _error = e is SendException ? '${e.message} (${e.statusCode ?? '-'})' : e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final devices = ref.watch(nearbyDevicesProvider).value ?? const [];
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.benchmarkTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(l10n.benchmarkIntro),
            const SizedBox(height: 24),
            if (devices.isEmpty)
              Text(l10n.benchmarkNoPeer, textAlign: TextAlign.center)
            else
              RadioGroup<DiscoveredDevice>(
                groupValue: _peer,
                onChanged: (value) => setState(() => _peer = value),
                child: Column(
                  children: [
                    for (final device in devices)
                      Card(
                        child: RadioListTile<DiscoveredDevice>(
                          value: device,
                          title: Text(device.info.alias),
                          subtitle: Text(device.address.address),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            Text(l10n.benchmarkSize, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 64, label: Text('64 MB')),
                ButtonSegment(value: 256, label: Text('256 MB')),
                ButtonSegment(value: 1024, label: Text('1 GB')),
              ],
              selected: {_megabytes},
              onSelectionChanged: _running
                  ? null
                  : (value) => setState(() => _megabytes = value.first),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _peer == null || _running ? null : _run,
              child: Text(_running ? l10n.benchmarkRunning : l10n.benchmarkRun),
            ),
            const SizedBox(height: 32),
            if (_running) const LinearProgressIndicator(),
            if (_failed) ...[
              Text(
                l10n.benchmarkFailed,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.error),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SelectableText(
                    _error!,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
            if (result != null) ...[
              Text(
                result.benchmark.megabytesPerSecond.toStringAsFixed(1),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Text('MB/s', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  title: Text(l10n.benchmarkConnect),
                  trailing: Text('${result.benchmark.connectMs} ms'),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  title: Text(l10n.benchmarkCpu),
                  trailing: Text(
                    result.cpuPercent == null
                        ? '—'
                        : '${result.cpuPercent!.toStringAsFixed(0)}%',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
