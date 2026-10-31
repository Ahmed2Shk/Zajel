import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/transfer/localsend_service.dart';
import '../../core/transfer/transfer_providers.dart';
import '../../core/transport/pairing_payload.dart';
import '../../core/transport/transport_manager.dart';

sealed class QrHostState {
  const QrHostState();
}

class QrHostStarting extends QrHostState {
  const QrHostStarting();
}

class QrHostReady extends QrHostState {
  const QrHostReady(this.payload);

  final PairingPayload payload;
}

class QrHostFailed extends QrHostState {
  const QrHostFailed(this.reason);

  final TransportFailure reason;
}

/// Hosts a hotspot and shows its QR code, while accepting one pairing.
///
/// The receiver arms a one-time token and PIN; the hotspot and the arming are
/// undone when the screen goes away, so a QR code never outlives its screen.
class QrHostNotifier extends Notifier<QrHostState> {
  final _random = Random.secure();
  bool _started = false;

  // Kept so that cleanup does not need `ref`, which is gone once disposed.
  LocalSendService? _service;
  TransportManager? _manager;

  @override
  QrHostState build() {
    ref.onDispose(() {
      if (_started) _undo();
    });
    return const QrHostStarting();
  }

  Future<void> start() async {
    if (_started) await _undo();
    state = const QrHostStarting();

    final manager = ref.read(transportManagerProvider);
    final service = await ref.read(localSendServiceProvider.future);
    if (manager == null || service == null) {
      state = const QrHostFailed(TransportFailure.unsupported);
      return;
    }
    try {
      final hotspot = await manager.startHotspot();
      _started = true;
      _service = service;
      _manager = manager;
      final token = base64Url.encode(List.generate(18, (_) => _random.nextInt(256))).replaceAll('=', '');
      final pin = (1000 + _random.nextInt(9000)).toString();
      service.armPairing(token: token, pin: pin);
      state = QrHostReady(
        PairingPayload(
          ssid: hotspot.credentials.ssid,
          passphrase: hotspot.credentials.passphrase,
          ip: hotspot.address.address,
          port: service.device.port,
          fingerprint: service.device.fingerprint,
          token: token,
          pin: pin,
          alias: service.device.alias,
        ),
      );
    } on TransportException catch (e) {
      state = QrHostFailed(e.reason);
    }
  }

  Future<void> _undo() async {
    _started = false;
    _service?.disarmPairing();
    try {
      await _manager?.stopHotspot();
    } catch (_) {}
    _service = null;
    _manager = null;
  }
}

final qrHostProvider = NotifierProvider.autoDispose<QrHostNotifier, QrHostState>(
  QrHostNotifier.new,
);
