import 'dart:async';
import 'dart:io';

import '../security/device_identity.dart';
import '../transfer/protocol_models.dart';
import 'multicast_discovery.dart';

/// Asks a device "are you still there?" with `GET /info`, over the same
/// fingerprint-checked HTTPS as a transfer. A device that was heard once on the
/// network stays in the list forever otherwise, even after its app is closed.
Future<bool> probeDevice(
  DiscoveredDevice device, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  // Only HTTPS peers can be asked; Zajel never talks plain HTTP to a device.
  if (device.info.protocol != ProtocolScheme.https) return true;

  final client = HttpClient()
    ..connectionTimeout = timeout
    ..badCertificateCallback = (cert, host, port) =>
        DeviceIdentity.fingerprintOfDer(cert.der) == device.info.fingerprint.toLowerCase();
  try {
    final request = await client
        .getUrl(
          Uri(
            scheme: 'https',
            host: device.address.address,
            port: device.info.port,
            path: '$localSendApiPrefix/info',
          ),
        )
        .timeout(timeout);
    final response = await request.close().timeout(timeout);
    await response.drain<void>();
    return response.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}
