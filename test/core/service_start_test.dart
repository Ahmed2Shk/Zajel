import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/discovery/device_probe.dart';
import 'package:zajel/core/discovery/multicast_discovery.dart';
import 'package:zajel/core/transfer/localsend_service.dart';

import '../support/transfer_harness.dart';

/// The service must come up even when its usual port is taken, for example
/// by the LocalSend app running on the same phone (AUDIT.md, A7).
void main() {
  late Directory downloads;
  LocalSendService? service;
  ServerSocket? squatter;

  setUp(() async {
    downloads = await createTestDir('zajel_start_');
  });

  tearDown(() async {
    await service?.stop();
    service = null;
    await squatter?.close();
    squatter = null;
    await deleteTestDir(downloads);
  });

  test('with its port taken the service listens on the next one and says so', () async {
    const port = 53441;
    squatter = await ServerSocket.bind(InternetAddress.anyIPv4, port);

    service = await LocalSendService.start(
      identity: receiverIdentity,
      alias: 'Receiver',
      downloadDirectory: downloads,
      port: port,
    );

    expect(service!.device.port, port + 1, reason: 'announced, so senders connect to the right port');
    final reachable = await probeDevice(DiscoveredDevice(service!.device, InternetAddress.loopbackIPv4));
    expect(reachable, isTrue);
  });

  test('with its port free the service uses it', () async {
    service = await LocalSendService.start(
      identity: receiverIdentity,
      alias: 'Receiver',
      downloadDirectory: downloads,
      port: 53451,
    );
    expect(service!.device.port, 53451);
  });
}
