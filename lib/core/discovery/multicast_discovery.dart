import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../security/device_identity.dart';
import '../transfer/protocol_models.dart';

class DiscoveredDevice {
  const DiscoveredDevice(this.info, this.address);

  final DeviceInfo info;
  final InternetAddress address;

  @override
  bool operator ==(Object other) =>
      other is DiscoveredDevice && other.info.fingerprint == info.fingerprint;

  @override
  int get hashCode => info.fingerprint.hashCode;
}

/// LocalSend multicast discovery on 224.0.0.167:53317.
///
/// On start (and shortly after, to survive packet loss) we announce ourselves.
/// When we hear an announcement we answer with `POST /register` to the sender
/// over HTTPS, and fall back to a UDP reply with `announce: false`.
class MulticastDiscovery {
  MulticastDiscovery({
    required this.self,
    this.port = localSendDefaultPort,
    this.groupAddress = localSendMulticastAddress,
  });

  final DeviceInfo self;
  final int port;
  final String groupAddress;

  final _devices = StreamController<DiscoveredDevice>.broadcast();
  RawDatagramSocket? _socket;
  final _timers = <Timer>[];

  Stream<DiscoveredDevice> get devices => _devices.stream;

  Future<void> start() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
      reusePort: !Platform.isWindows,
    );
    socket.multicastHops = 1;
    _socket = socket;
    await _joinGroup(socket);
    socket.listen(
      (event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) _onDatagram(datagram);
        }
      },
      // A failed send ("network is unreachable" while this app is bound to a
      // hotspot, or with Wi-Fi off) is also reported here. It is not a fault.
      onError: (Object _) {},
    );
    for (final delay in const [100, 500, 2000]) {
      _timers.add(Timer(Duration(milliseconds: delay), announce));
    }
  }

  /// Tells the network this device is here. Also joins the multicast group on
  /// any network that has appeared since (Wi-Fi connected later, a hotspot
  /// started), so discovery works without restarting the app.
  void announce() {
    final socket = _socket;
    if (socket != null) unawaited(_joinGroup(socket));
    _send(MulticastMessage(device: self, announce: true));
  }

  Future<void> stop() async {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    _socket?.close();
    _socket = null;
  }

  /// Joins the group on every network there is. Never throws: with no network
  /// at all (Wi-Fi off, not connected) there is nothing to join, and the app
  /// must still start, because a QR hotspot needs no network to begin with.
  Future<void> _joinGroup(RawDatagramSocket socket) async {
    final group = InternetAddress(groupAddress);
    var joined = false;
    try {
      for (final interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        try {
          socket.joinMulticast(group, interface);
          joined = true;
        } catch (_) {
          // Already joined, or the interface has no multicast (loopback, VPN).
        }
      }
      if (!joined) socket.joinMulticast(group);
    } catch (_) {
      // No usable network right now; announce() tries again later.
    }
  }

  void _send(MulticastMessage message) {
    try {
      _socket?.send(
        utf8.encode(jsonEncode(message.toJson())),
        InternetAddress(groupAddress),
        port,
      );
    } catch (_) {
      // "Network is unreachable": no Wi-Fi at the moment, or this app's
      // traffic is bound to a hotspot. Nothing to announce to.
    }
  }

  void _onDatagram(Datagram datagram) {
    final MulticastMessage message;
    try {
      final json = jsonDecode(utf8.decode(datagram.data));
      if (json is! Map<String, dynamic>) return;
      message = MulticastMessage.fromJson(json);
    } catch (_) {
      return; // Not a LocalSend packet.
    }
    final peer = message.device;
    if (peer.fingerprint == self.fingerprint) return; // Our own packet.

    _devices.add(DiscoveredDevice(peer, datagram.address));
    if (message.announce) unawaited(_reply(peer, datagram.address));
  }

  Future<void> _reply(DeviceInfo peer, InternetAddress address) async {
    if (peer.protocol != ProtocolScheme.https) {
      _send(MulticastMessage(device: self, announce: false));
      return;
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3)
      ..badCertificateCallback = (cert, host, port) =>
          DeviceIdentity.fingerprintOfDer(cert.der) ==
          peer.fingerprint.toLowerCase();
    try {
      final request = await client.postUrl(
        Uri(
          scheme: 'https',
          host: address.address,
          port: peer.port,
          path: '$localSendApiPrefix/register',
        ),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(self.toJson()));
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode != 200) {
        _send(MulticastMessage(device: self, announce: false));
      }
    } catch (_) {
      _send(MulticastMessage(device: self, announce: false));
    } finally {
      client.close(force: true);
    }
  }
}
