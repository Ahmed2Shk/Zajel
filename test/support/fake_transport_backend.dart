import 'package:zajel/core/transport/transport_manager.dart';

/// A phone transport for tests: every step succeeds unless told otherwise, and
/// every call is recorded in [calls].
class FakeTransportBackend implements TransportBackend {
  bool permissions = true;
  bool location = true;
  bool wifi = true;
  TransportException? joinError;
  TransportException? directError;
  TransportException? hotspotError;
  final calls = <String>[];

  @override
  Future<bool> requestPermissions() async {
    calls.add('permissions');
    return permissions;
  }

  @override
  Future<bool> isLocationEnabled() async => location;
  @override
  Future<bool> isWifiEnabled() async => wifi;
  @override
  Future<bool> supports5GHz() async => true;

  @override
  Future<NetworkCredentials> startHotspot() async {
    calls.add('startHotspot');
    if (hotspotError != null) throw hotspotError!;
    return const NetworkCredentials(ssid: 'AndroidShare_1', passphrase: 'password123');
  }

  @override
  Future<void> stopHotspot() async => calls.add('stopHotspot');

  @override
  Future<void> joinNetwork(String ssid, String passphrase) async {
    calls.add('join:$ssid');
    if (joinError != null) throw joinError!;
  }

  @override
  Future<void> leaveNetwork() async => calls.add('leave');

  @override
  Future<void> startDirectReceiver(String alias, String fingerprint, int port) async =>
      calls.add('startDirect:$alias');

  @override
  Future<void> stopDirectReceiver() async => calls.add('stopDirect');

  @override
  Future<List<DirectPeer>> discoverDirectPeers(Duration timeout) async => [fakeDirectPeer()];

  @override
  Future<String> connectDirect(DirectPeer peer) async {
    calls.add('connectDirect:${peer.alias}');
    if (directError != null) throw directError!;
    return '192.168.49.1';
  }

  @override
  Future<void> disconnectDirect() async => calls.add('disconnectDirect');
}


/// A Wi-Fi Direct receiver called Sara.
DirectPeer fakeDirectPeer() => const DirectPeer(
  deviceAddress: 'aa:bb:cc:dd:ee:ff',
  alias: 'Sara',
  fingerprint: 'f',
  port: 53317,
);
