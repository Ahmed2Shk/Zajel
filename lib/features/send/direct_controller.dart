import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/transfer/transfer_providers.dart';
import '../../core/transport/transport_manager.dart';

class DirectState {
  const DirectState({
    this.peers = const [],
    this.searching = false,
    this.visible = false,
    this.failure,
  });

  final List<DirectPeer> peers;
  final bool searching;

  /// This device is advertising itself over Wi-Fi Direct.
  final bool visible;
  final TransportFailure? failure;

  DirectState copyWith({
    List<DirectPeer>? peers,
    bool? searching,
    bool? visible,
    TransportFailure? failure,
    bool clearFailure = false,
  }) => DirectState(
    peers: peers ?? this.peers,
    searching: searching ?? this.searching,
    visible: visible ?? this.visible,
    failure: clearFailure ? null : (failure ?? this.failure),
  );
}

/// Wi-Fi Direct: advertise this device so senders can reach it directly (no
/// router), or look for receivers. The device advertises by itself once the
/// service is ready; searching starts from the discovery screen.
class DirectController extends Notifier<DirectState> {
  // Kept outside the state: cleanup may not read providers or state once the
  // controller is being disposed.
  TransportManager? _advertisingManager;

  @override
  DirectState build() {
    // Advertise over Wi-Fi Direct as soon as the service is ready, so a nearby
    // Zajel sender connects device-to-device (the fast 5 GHz path) instead of
    // relaying through the router. Best-effort: a failure just leaves the LAN
    // path working.
    ref.onDispose(() => _advertisingManager?.stopAdvertisingDirect());
    unawaited(_autoAdvertise());
    return const DirectState();
  }

  Future<void> _autoAdvertise() async {
    final manager = ref.read(transportManagerProvider);
    if (manager == null) return; // not Android
    final service = await ref.read(localSendServiceProvider.future);
    if (service == null || !ref.mounted) return;
    try {
      await manager.advertiseDirect(
        alias: service.device.alias,
        fingerprint: service.device.fingerprint,
        port: service.device.port,
      );
      _advertisingManager = manager;
      if (ref.mounted) state = state.copyWith(visible: true);
    } on TransportException {
      // Permissions not granted or Wi-Fi Direct unavailable: stay on LAN.
    }
  }

  Future<void> search() async {
    final manager = ref.read(transportManagerProvider);
    if (manager == null) {
      state = state.copyWith(failure: TransportFailure.unsupported);
      return;
    }
    state = state.copyWith(searching: true, clearFailure: true);
    try {
      final peers = await manager.findDirectPeers();
      // The sheet or screen may have closed during the search.
      if (!ref.mounted) return;
      // Our own advertisement can show up too.
      final self = ref.read(localSendServiceProvider).value?.device.fingerprint;
      state = state.copyWith(
        searching: false,
        peers: [
          for (final p in peers)
            if (p.fingerprint != self) p,
        ],
      );
    } on TransportException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(searching: false, failure: e.reason);
    }
  }

  Future<void> setVisible(bool visible) async {
    final manager = ref.read(transportManagerProvider);
    final service = await ref.read(localSendServiceProvider.future);
    if (manager == null || service == null) {
      state = state.copyWith(failure: TransportFailure.unsupported);
      return;
    }
    try {
      if (visible) {
        await manager.advertiseDirect(
          alias: service.device.alias,
          fingerprint: service.device.fingerprint,
          port: service.device.port,
        );
      } else {
        await manager.stopAdvertisingDirect();
      }
      if (!ref.mounted) {
        // The screen closed while the group was being created: nobody is left
        // to stop it later, so stop it now.
        if (visible) await manager.stopAdvertisingDirect();
        return;
      }
      _advertisingManager = visible ? manager : null;
      state = state.copyWith(visible: visible, clearFailure: true);
    } on TransportException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(failure: e.reason);
    }
  }

  void clearFailure() => state = state.copyWith(clearFailure: true);
}

final directControllerProvider =
    NotifierProvider<DirectController, DirectState>(DirectController.new);
