@Tags(['network'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/discovery/multicast_discovery.dart';
import 'package:zajel/core/transfer/protocol_models.dart';
import 'package:zajel/core/transfer/receive_server.dart';

import '../support/transfer_harness.dart';

/// Needs a network interface that allows multicast. Run with:
///   ZAJEL_NETWORK=1 flutter test test/core/multicast_discovery_test.dart
void main() {
  test('two instances discover each other over multicast', () async {
    const port = 53399; // not the default, so a real LocalSend app is left alone
    final downloads = await Directory.systemTemp.createTemp('zajel_disc_');
    addTearDown(() => downloads.delete(recursive: true));

    final aInfo = DeviceInfo(
      alias: 'A',
      fingerprint: receiverIdentity.fingerprint,
      port: port,
    );
    final bInfo = DeviceInfo(
      alias: 'B',
      fingerprint: senderIdentity.fingerprint,
      port: port + 1,
    );

    // A is a full receiver so B can answer an announcement with POST /register.
    final registered = Completer<DeviceInfo>();
    final aServer = ReceiveServer(
      identity: receiverIdentity,
      device: aInfo,
      downloadDirectory: downloads,
      onIncoming: (_) async => null,
      onDeviceRegistered: (device, _) {
        if (!registered.isCompleted) registered.complete(device);
      },
    );
    await aServer.start(port: port);
    addTearDown(aServer.stop);

    final a = MulticastDiscovery(self: aInfo, port: port);
    final b = MulticastDiscovery(self: bInfo, port: port);
    addTearDown(a.stop);
    addTearDown(b.stop);

    final aSeesB = a.devices.firstWhere((d) => d.info.alias == 'B');
    final bSeesA = b.devices.firstWhere((d) => d.info.alias == 'A');
    await a.start();
    await b.start();

    final foundByA = await aSeesB.timeout(const Duration(seconds: 8));
    final foundByB = await bSeesA.timeout(const Duration(seconds: 8));
    expect(foundByA.info.fingerprint, bInfo.fingerprint);
    expect(foundByB.info.fingerprint, aInfo.fingerprint);

    // A announced, so B answered with POST /register over HTTPS to A's server.
    final registeredDevice = await registered.future.timeout(
      const Duration(seconds: 8),
    );
    expect(registeredDevice.alias, 'B');
  }, skip: Platform.environment['ZAJEL_NETWORK'] == null
      ? 'needs multicast: set ZAJEL_NETWORK=1 to run'
      : null);
}
