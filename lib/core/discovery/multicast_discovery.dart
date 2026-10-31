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
    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram != null) _onDatagram(datagram);
      }
    });
    for (final delay in const [100, 500, 2000]) {
      _timers.add(Timer(Duration(milliseconds: delay), announce));
    }
  }

  void announce() => _send(MulticastMessage(device: self, announce: true));

  Future<void> stop() async {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    _socket?.close();
    _socket = null;
  }

  Future<void> _joinGroup(RawDatagramSocket socket) async {
    final group = InternetAddress(groupAddress);
    var joined = false;
    for (final interface in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    )) {
      try {
        socket.joinMulticast(group, interface);
        joined = true;
      } on SocketException {
        // Interface does not support multicast (loopback, VPN...).
      }
    }
    if (!joined) socket.joinMulticast(group);
  }

  void _send(MulticastMessage message) {
    _socket?.send(
      utf8.encode(jsonEncode(message.toJson())),
      InternetAddress(groupAddress),
      port,
    );
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
