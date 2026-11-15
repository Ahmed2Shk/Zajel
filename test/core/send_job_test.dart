import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/discovery/multicast_discovery.dart';
import 'package:zajel/core/transfer/localsend_service.dart';
import 'package:zajel/core/transfer/protocol_models.dart';
import 'package:zajel/core/transfer/receive_server.dart';
import 'package:zajel/core/transfer/send_client.dart';
import 'package:zajel/core/transfer/transfer_providers.dart';
import 'package:zajel/core/transport/transport_manager.dart';

import '../support/fake_transport_backend.dart';
import '../support/transfer_harness.dart';

/// The send job as the screens drive it: one send at a time, and a send that
/// was cancelled can never disturb the one that follows it (AUDIT.md, A1).
void main() {
  late LocalSendService sender;
  late Directory scratch;
  late FakeTransportBackend backend;
  late ProviderContainer container;
  final harnesses = <TransferHarness>[];

  setUp(() async {
    scratch = await createTestDir('zajel_job_');
    sender = await LocalSendService.start(
      identity: senderIdentity,
      alias: 'Sender',
      downloadDirectory: Directory('${scratch.path}/dl'),
      port: 53431,
    );
    backend = FakeTransportBackend();
    container = ProviderContainer(
      overrides: [
        localSendServiceProvider.overrideWith((ref) async => sender),
        transportManagerProvider.overrideWithValue(TransportManager(backend)),
      ],
    );
    final file = await writeTestFile(scratch, 'a.bin', 200 * 1024);
    container.read(selectedFilesProvider.notifier).set([await SendFile.fromPath(file.path, id: 'a.bin')]);
  });

  tearDown(() async {
    container.dispose();
    await sender.stop();
    for (final h in harnesses) {
      await h.dispose();
    }
    harnesses.clear();
    await deleteTestDir(scratch);
  });

  Future<TransferHarness> receiver({IncomingDecision? onIncoming}) async {
    final harness = await TransferHarness.start(onIncoming: onIncoming);
    harnesses.add(harness);
    return harness;
  }

  DiscoveredDevice deviceOf(TransferHarness harness) => DiscoveredDevice(
    DeviceInfo(alias: 'Receiver', fingerprint: receiverIdentity.fingerprint, port: harness.server.port),
    InternetAddress.loopbackIPv4,
  );

  PeerEndpoint hotspotEndpoint(TransferHarness harness) => PeerEndpoint(
    address: InternetAddress.loopbackIPv4,
    port: harness.server.port,
    fingerprint: receiverIdentity.fingerprint,
    alias: 'Receiver',
    via: TransportKind.hotspotQr,
  );

  SendJobNotifier notifier() => container.read(sendJobProvider.notifier);
  SendJob job() => container.read(sendJobProvider);

  test('a cancelled send that fails late does not touch the next send', () async {
    // Receiver A keeps the sender waiting at its accept dialog.
    final asked = Completer<void>();
    final decision = Completer<Set<String>?>();
    final a = await receiver(
      onIncoming: (_) {
        asked.complete();
        return decision.future;
      },
    );
    final b = await receiver();

    final first = notifier().send(deviceOf(a), endpoint: hotspotEndpoint(a));
    await asked.future;
    await notifier().cancel();
    expect(backend.calls.where((c) => c == 'leave'), hasLength(1), reason: 'cancel leaves the hotspot of send A');

    // Send B starts at once and finishes.
    await notifier().send(deviceOf(b), endpoint: hotspotEndpoint(b));
    expect(job().status, SendStatus.done);
    final leavesAfterB = backend.calls.where((c) => c == 'leave').length;

    // Only now does A get its answer (declined) and unwind.
    decision.complete(null);
    await first;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(job().status, SendStatus.done, reason: 'A must not write "failed" over B');
    expect(job().error, isNull);
    expect(
      backend.calls.where((c) => c == 'leave'),
      hasLength(leavesAfterB),
      reason: 'A must not leave a network again after it was cancelled',
    );
  });

  test('a second send does not start while one is running', () async {
    final asked = Completer<void>();
    final decision = Completer<Set<String>?>();
    final a = await receiver(
      onIncoming: (_) {
        asked.complete();
        return decision.future;
      },
    );
    var bAsked = false;
    final b = await receiver(
      onIncoming: (t) async {
        bAsked = true;
        return t.files.keys.toSet();
      },
    );

    final first = notifier().send(deviceOf(a));
    await asked.future;
    expect(notifier().isBusy, isTrue);

    await notifier().send(deviceOf(b));
    expect(bAsked, isFalse, reason: 'the second send was refused');
    expect(job().target!.info.port, a.server.port);

    decision.complete({'a.bin'});
    await first;
    expect(job().status, SendStatus.done);
    expect(notifier().isBusy, isFalse);
  });

  test('cancelling while the receiver is still deciding frees its session', () async {
    final asked = Completer<void>();
    final decision = Completer<Set<String>?>();
    final a = await receiver(
      onIncoming: (t) async {
        if (asked.isCompleted) return t.files.keys.toSet(); // a later sender
        asked.complete();
        return decision.future;
      },
    );

    final first = notifier().send(deviceOf(a));
    await asked.future;
    await notifier().cancel();
    decision.complete({'a.bin'}); // the receiver accepts a send that is gone
    await first;
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(job().status, SendStatus.idle);
    // The receiver is free for the next sender straight away.
    final session = await a.prepare([container.read(selectedFilesProvider).single]);
    expect(session.tokens, isNotEmpty);
  });
}
