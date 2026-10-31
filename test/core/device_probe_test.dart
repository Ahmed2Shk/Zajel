import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/discovery/device_probe.dart';
import 'package:zajel/core/discovery/multicast_discovery.dart';
import 'package:zajel/core/transfer/protocol_models.dart';

import '../support/transfer_harness.dart';

DiscoveredDevice _deviceFor(TransferHarness harness, {String? fingerprint}) => DiscoveredDevice(
  DeviceInfo(
    alias: 'Receiver',
    fingerprint: fingerprint ?? receiverIdentity.fingerprint,
    port: harness.server.port,
  ),
  InternetAddress.loopbackIPv4,
);

void main() {
  test('a running device answers', () async {
    final harness = await TransferHarness.start();
    addTearDown(harness.dispose);
    expect(await probeDevice(_deviceFor(harness)), isTrue);
  });

  test('a device with another certificate is not the one that was listed', () async {
    final harness = await TransferHarness.start();
    addTearDown(harness.dispose);
    expect(await probeDevice(_deviceFor(harness, fingerprint: 'f' * 64)), isFalse);
  });

  test('a device whose app was closed does not answer', () async {
    final harness = await TransferHarness.start();
    final device = _deviceFor(harness);
    await harness.dispose();
    expect(await probeDevice(device, timeout: const Duration(milliseconds: 500)), isFalse);
  });
}
