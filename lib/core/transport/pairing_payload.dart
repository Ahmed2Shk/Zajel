import 'dart:convert';
import 'dart:io';

/// Thrown when a scanned QR code is not a valid Zajel pairing code.
class PairingFormatException implements Exception {
  const PairingFormatException(this.message);

  final String message;

  @override
  String toString() => 'PairingFormatException: $message';
}

/// What the QR code carries so another device can join this one with no router
/// and no typing (SPEC.md, Security):
///
/// the network to join, where to connect, the certificate fingerprint to
/// verify, and a one-time token (plus a short PIN for people who type instead
/// of scanning). The same format is used by iOS later.
class PairingPayload {
  const PairingPayload({
    required this.ssid,
    required this.passphrase,
    required this.ip,
    required this.port,
    required this.fingerprint,
    required this.token,
    required this.pin,
    required this.alias,
  });

  static const scheme = 'zajel';
  static const version = 1;

  final String ssid;
  final String passphrase;
  final String ip;
  final int port;

  /// SHA-256 of the receiver's certificate, lowercase hex.
  final String fingerprint;

  /// Used once: the receiver stops accepting it after the first transfer.
  final String token;

  /// 4 digits shown under the QR code, for devices that cannot scan.
  final String pin;
  final String alias;

  /// `zajel://pair?d=<base64url json>`
  String encode() {
    final json = jsonEncode({
      'v': version,
      'ssid': ssid,
      'pass': passphrase,
      'ip': ip,
      'port': port,
      'fp': fingerprint,
      'tok': token,
      'pin': pin,
      'name': alias,
    });
    final data = base64Url.encode(utf8.encode(json)).replaceAll('=', '');
    return '$scheme://pair?d=$data';
  }

  /// Reads a scanned code. Anything unexpected throws
  /// [PairingFormatException]; a QR code is untrusted input.
  static PairingPayload parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != scheme || uri.host != 'pair') {
      throw const PairingFormatException('not a Zajel code');
    }
    final data = uri.queryParameters['d'];
    if (data == null || data.isEmpty || data.length > 2048) {
      throw const PairingFormatException('missing data');
    }

    final Object? decoded;
    try {
      final padded = data.padRight((data.length + 3) ~/ 4 * 4, '=');
      decoded = jsonDecode(utf8.decode(base64Url.decode(padded)));
    } on FormatException {
      throw const PairingFormatException('unreadable data');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const PairingFormatException('unexpected structure');
    }
    final map = decoded;
    if (map['v'] != version) {
      throw const PairingFormatException('unsupported version');
    }

    String text(String key, {required int min, required int max}) {
      final value = map[key];
      if (value is! String || value.length < min || value.length > max) {
        throw PairingFormatException('bad $key');
      }
      return value;
    }

    final ssid = text('ssid', min: 1, max: 32);
    final passphrase = text('pass', min: 8, max: 63); // WPA2 length limits
    final alias = text('name', min: 1, max: 64);
    final fingerprint = text('fp', min: 64, max: 64);
    final token = text('tok', min: 16, max: 64);
    final pin = text('pin', min: 4, max: 8);
    final ip = text('ip', min: 7, max: 15);

    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint)) {
      throw const PairingFormatException('bad fp');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(token)) {
      throw const PairingFormatException('bad tok');
    }
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      throw const PairingFormatException('bad pin');
    }
    final port = map['port'];
    if (port is! int || port < 1 || port > 65535) {
      throw const PairingFormatException('bad port');
    }
    final address = InternetAddress.tryParse(ip);
    if (address == null || address.type != InternetAddressType.IPv4 || !_isPrivate(address)) {
      // A pairing code must never send files to an address on the internet.
      throw const PairingFormatException('bad ip');
    }

    return PairingPayload(
      ssid: ssid,
      passphrase: passphrase,
      ip: ip,
      port: port,
      fingerprint: fingerprint,
      token: token,
      pin: pin,
      alias: alias,
    );
  }

  static bool _isPrivate(InternetAddress a) {
    final b = a.rawAddress;
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168);
  }
}
