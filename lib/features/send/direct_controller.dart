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

/// Wi-Fi Direct on the discovery screen: look for receivers, or be one.
/// Nothing starts by itself, because both ask for permissions and use the radio.
class DirectController extends Notifier<DirectState> {
  // Kept outside the state: cleanup may not read providers or state once the
  // controller is being disposed.
  TransportManager? _advertisingManager;

  @override
  DirectState build() {
    ref.onDispose(() => _advertisingManager?.stopAdvertisingDirect());
    return const DirectState();
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
      _advertisingManager = visible ? manager : null;
      state = state.copyWith(visible: visible, clearFailure: true);
    } on TransportException catch (e) {
      state = state.copyWith(failure: e.reason);
    }
  }

  void clearFailure() => state = state.copyWith(clearFailure: true);
}

final directControllerProvider =
    NotifierProvider.autoDispose<DirectController, DirectState>(DirectController.new);
