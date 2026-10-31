import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../discovery/multicast_discovery.dart';
import '../platform/platform_api.g.dart';
import 'pairing_payload.dart';

/// The ways to reach another device, fastest first (CLAUDE.md):
/// Wi-Fi Direct, then a hotspot joined through a QR code, then the same Wi-Fi.
enum TransportKind { wifiDirect, hotspotQr, sameLan }

/// Why a router-free transport could not be set up. Each one has its own clear
/// message in the UI (SPEC.md, Phase 3).
enum TransportFailure {
  permissionDenied,
  locationOff,
  wifiOff,
  unsupported,
  busy,
  timeout,
  failed;

  static TransportFailure fromCode(String? code) => switch (code) {
    'permission_denied' => permissionDenied,
    'location_off' => locationOff,
    'wifi_off' => wifiOff,
    'unsupported' => unsupported,
    'busy' => busy,
    'timeout' => timeout,
    _ => failed,
  };
}

class TransportException implements Exception {
  const TransportException(this.kind, this.reason, [this.detail]);

  final TransportKind kind;
  final TransportFailure reason;
  final String? detail;

  @override
  String toString() => 'TransportException(${kind.name}, ${reason.name}${detail == null ? '' : ': $detail'})';
}

/// Every route to a peer failed. [failures] says why, route by route.
class AllTransportsFailed implements Exception {
  const AllTransportsFailed(this.failures);

  final List<TransportException> failures;

  @override
  String toString() => 'AllTransportsFailed($failures)';
}

/// A device seen through Wi-Fi Direct service discovery.
class DirectPeer {
  const DirectPeer({
    required this.deviceAddress,
    required this.alias,
    required this.fingerprint,
    required this.port,
    this.networkName,
    this.passphrase,
  });

  final String deviceAddress;
  final String alias;
  final String fingerprint;
  final int port;
  final String? networkName;
  final String? passphrase;
}

class NetworkCredentials {
  const NetworkCredentials({required this.ssid, required this.passphrase});

  final String ssid;
  final String passphrase;
}

/// One way to reach a peer.
sealed class PeerRoute {
  const PeerRoute();

  TransportKind get kind;
  String get fingerprint;
  String get alias;
}

class LanRoute extends PeerRoute {
  const LanRoute(this.device);

  final DiscoveredDevice device;

  @override
  TransportKind get kind => TransportKind.sameLan;
  @override
  String get fingerprint => device.info.fingerprint;
  @override
  String get alias => device.info.alias;
}

class DirectRoute extends PeerRoute {
  const DirectRoute(this.peer);

  final DirectPeer peer;

  @override
  TransportKind get kind => TransportKind.wifiDirect;
  @override
  String get fingerprint => peer.fingerprint;
  @override
  String get alias => peer.alias;
}

class QrRoute extends PeerRoute {
  const QrRoute(this.payload);

  final PairingPayload payload;

  @override
  TransportKind get kind => TransportKind.hotspotQr;
  @override
  String get fingerprint => payload.fingerprint;
  @override
  String get alias => payload.alias;
}

/// Where to send, once a route has been set up. [pairToken] and [pin] are only
/// set for QR pairing.
class PeerEndpoint {
  const PeerEndpoint({
    required this.address,
    required this.port,
    required this.fingerprint,
    required this.alias,
    required this.via,
    this.pairToken,
    this.pin,
  });

  final InternetAddress address;
  final int port;
  final String fingerprint;
  final String alias;
  final TransportKind via;
  final String? pairToken;
  final String? pin;
}

/// The phone's side of the router-free transports. An interface so the logic
/// above it can be tested without a phone.
abstract class TransportBackend {
  Future<bool> requestPermissions();
  Future<bool> isLocationEnabled();
  Future<bool> isWifiEnabled();
  Future<bool> supports5GHz();
  Future<NetworkCredentials> startHotspot();
  Future<void> stopHotspot();
  Future<void> joinNetwork(String ssid, String passphrase);
  Future<void> leaveNetwork();
  Future<void> startDirectReceiver(String alias, String fingerprint, int port);
  Future<void> stopDirectReceiver();
  Future<List<DirectPeer>> discoverDirectPeers(Duration timeout);
  Future<String> connectDirect(DirectPeer peer);
  Future<void> disconnectDirect();
}

/// The real backend, over the Pigeon-generated Android API. Errors come back
/// as [TransportException] with the matching [TransportFailure].
class PigeonTransportBackend implements TransportBackend {
  PigeonTransportBackend([TransportApi? api]) : _api = api ?? TransportApi();

  final TransportApi _api;

  Future<T> _guard<T>(TransportKind kind, Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      throw TransportException(kind, TransportFailure.fromCode(e.code), e.message);
    }
  }

  @override
  Future<bool> requestPermissions() => _api.requestWifiPermissions();
  @override
  Future<bool> isLocationEnabled() => _api.isLocationEnabled();
  @override
  Future<bool> isWifiEnabled() => _api.isWifiEnabled();
  @override
  Future<bool> supports5GHz() => _api.supports5GHz();

  @override
  Future<NetworkCredentials> startHotspot() => _guard(TransportKind.hotspotQr, () async {
    final info = await _api.startHotspot();
    return NetworkCredentials(ssid: info.ssid, passphrase: info.passphrase);
  });

  @override
  Future<void> stopHotspot() => _api.stopHotspot();

  @override
  Future<void> joinNetwork(String ssid, String passphrase) =>
      _guard(TransportKind.hotspotQr, () => _api.joinNetwork(ssid, passphrase));

  @override
  Future<void> leaveNetwork() => _api.leaveNetwork();

  @override
  Future<void> startDirectReceiver(String alias, String fingerprint, int port) =>
      _guard(TransportKind.wifiDirect, () => _api.startDirectReceiver(alias, fingerprint, port));

  @override
  Future<void> stopDirectReceiver() => _api.stopDirectReceiver();

  @override
  Future<List<DirectPeer>> discoverDirectPeers(Duration timeout) =>
      _guard(TransportKind.wifiDirect, () async {
        final peers = await _api.discoverDirectPeers(timeout.inMilliseconds);
        return [
          for (final p in peers)
            DirectPeer(
              deviceAddress: p.deviceAddress,
              alias: p.alias,
              fingerprint: p.fingerprint,
              port: p.port,
              networkName: p.networkName,
              passphrase: p.passphrase,
            ),
        ];
      });

  @override
  Future<String> connectDirect(DirectPeer peer) => _guard(
    TransportKind.wifiDirect,
    () => _api.connectDirect(
      NativeDirectPeer(
        deviceAddress: peer.deviceAddress,
        alias: peer.alias,
        fingerprint: peer.fingerprint,
        port: peer.port,
        networkName: peer.networkName,
        passphrase: peer.passphrase,
      ),
    ),
  );

  @override
  Future<void> disconnectDirect() => _api.disconnectDirect();
}

/// A hotspot this device is hosting for a QR pairing.
class HostedHotspot {
  const HostedHotspot({required this.credentials, required this.address});

  final NetworkCredentials credentials;

  /// This device's address on the hotspot, where the receiver listens.
  final InternetAddress address;
}

/// Picks and sets up the way to reach a peer: Wi-Fi Direct, a hotspot joined
/// by QR, or the shared Wi-Fi, tried in that order with automatic fallback.
class TransportManager {
  TransportManager(
    this.backend, {
    Future<List<InternetAddress>> Function()? listAddresses,
    this.addressWait = const Duration(seconds: 6),
    this.addressPoll = const Duration(milliseconds: 300),
  }) : _listAddresses = listAddresses ?? _defaultAddresses;

  final TransportBackend backend;
  final Future<List<InternetAddress>> Function() _listAddresses;
  final Duration addressWait;
  final Duration addressPoll;

  static const _priority = [
    TransportKind.wifiDirect,
    TransportKind.hotspotQr,
    TransportKind.sameLan,
  ];

  static Future<List<InternetAddress>> _defaultAddresses() async => [
    for (final interface in await NetworkInterface.list(type: InternetAddressType.IPv4))
      ...interface.addresses.where((a) => !a.isLoopback && !a.isLinkLocal),
  ];

  /// Routes to the same device, ordered fastest first.
  static List<PeerRoute> prioritized(Iterable<PeerRoute> routes) =>
      [...routes]..sort((a, b) => _priority.indexOf(a.kind).compareTo(_priority.indexOf(b.kind)));

  /// Sets up the first route that works. A failure falls back to the next;
  /// if none works, [AllTransportsFailed] says why for each.
  Future<PeerEndpoint> establish(Iterable<PeerRoute> routes) async {
    final failures = <TransportException>[];
    for (final route in prioritized(routes)) {
      try {
        return await _connect(route);
      } on TransportException catch (e) {
        failures.add(e);
        await _cleanUp(route);
      }
    }
    throw AllTransportsFailed(failures);
  }

  Future<PeerEndpoint> _connect(PeerRoute route) async {
    switch (route) {
      case LanRoute(:final device):
        // Already on the same network: nothing to set up.
        return PeerEndpoint(
          address: device.address,
          port: device.info.port,
          fingerprint: device.info.fingerprint,
          alias: device.info.alias,
          via: TransportKind.sameLan,
        );

      case DirectRoute(:final peer):
        await _ensureReady(TransportKind.wifiDirect);
        final host = await backend.connectDirect(peer);
        return PeerEndpoint(
          address: InternetAddress(host),
          port: peer.port,
          fingerprint: peer.fingerprint,
          alias: peer.alias,
          via: TransportKind.wifiDirect,
        );

      case QrRoute(:final payload):
        await _ensureReady(TransportKind.hotspotQr);
        await backend.joinNetwork(payload.ssid, payload.passphrase);
        return PeerEndpoint(
          address: InternetAddress(payload.ip),
          port: payload.port,
          fingerprint: payload.fingerprint,
          alias: payload.alias,
          via: TransportKind.hotspotQr,
          pairToken: payload.token,
          pin: payload.pin,
        );
    }
  }

  /// Permissions, location and Wi-Fi: the three things that must be right
  /// before any router-free transport can start, each with its own error.
  Future<void> _ensureReady(TransportKind kind) async {
    if (!await backend.requestPermissions()) {
      throw TransportException(kind, TransportFailure.permissionDenied);
    }
    if (!await backend.isLocationEnabled()) {
      throw TransportException(kind, TransportFailure.locationOff);
    }
    if (!await backend.isWifiEnabled()) {
      throw TransportException(kind, TransportFailure.wifiOff);
    }
  }

  Future<void> _cleanUp(PeerRoute route) async {
    try {
      switch (route) {
        case DirectRoute():
          await backend.disconnectDirect();
        case QrRoute():
          await backend.leaveNetwork();
        case LanRoute():
          break;
      }
    } catch (_) {
      // Cleaning up must not hide the original failure.
    }
  }

  /// Leaves whatever network [establish] joined.
  Future<void> release(PeerEndpoint endpoint) async {
    switch (endpoint.via) {
      case TransportKind.wifiDirect:
        await backend.disconnectDirect();
      case TransportKind.hotspotQr:
        await backend.leaveNetwork();
      case TransportKind.sameLan:
        break;
    }
  }

  /// Starts a hotspot for a QR pairing and finds this device's address on it.
  Future<HostedHotspot> startHotspot() async {
    await _ensureReady(TransportKind.hotspotQr);
    final before = (await _listAddresses()).map((a) => a.address).toSet();
    final credentials = await backend.startHotspot();
    try {
      return HostedHotspot(
        credentials: credentials,
        address: await _hotspotAddress(before),
      );
    } catch (_) {
      await backend.stopHotspot();
      rethrow;
    }
  }

  /// The hotspot's interface appears a moment after it starts: the address
  /// that was not there before is ours on it.
  Future<InternetAddress> _hotspotAddress(Set<String> before) async {
    final deadline = DateTime.now().add(addressWait);
    while (true) {
      final fresh = (await _listAddresses()).where((a) => !before.contains(a.address)).toList();
      if (fresh.isNotEmpty) return fresh.first;
      if (DateTime.now().isAfter(deadline)) {
        throw const TransportException(
          TransportKind.hotspotQr,
          TransportFailure.timeout,
          'the hotspot address did not appear',
        );
      }
      await Future<void>.delayed(addressPoll);
    }
  }

  Future<void> stopHotspot() => backend.stopHotspot();

  /// Makes this device findable over Wi-Fi Direct while it waits to receive.
  Future<void> advertiseDirect({
    required String alias,
    required String fingerprint,
    required int port,
  }) async {
    await _ensureReady(TransportKind.wifiDirect);
    await backend.startDirectReceiver(alias, fingerprint, port);
  }

  Future<void> stopAdvertisingDirect() => backend.stopDirectReceiver();

  Future<List<DirectPeer>> findDirectPeers({Duration timeout = const Duration(seconds: 6)}) async {
    await _ensureReady(TransportKind.wifiDirect);
    return backend.discoverDirectPeers(timeout);
  }
}

/// Stands in where there is no phone transport (anything but Android): only
/// routes that need no setup can succeed, so it is never actually called.
class NoTransportBackend implements TransportBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw const TransportException(TransportKind.sameLan, TransportFailure.unsupported);
}
