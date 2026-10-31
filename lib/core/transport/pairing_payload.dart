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
  static const version = 2;

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

  /// `zajel://pair?d=<base64url json array>`
  ///
  /// A JSON array without key names and the fingerprint as base64 instead of
  /// hex: about 40% shorter than the first format, which makes a QR code with
  /// bigger squares that cameras read faster and from further away.
  String encode() {
    final json = jsonEncode([
      version,
      ssid,
      passphrase,
      ip,
      port,
      base64Url.encode(_hexToBytes(fingerprint)).replaceAll('=', ''),
      token,
      pin,
      alias,
    ]);
    final data = base64Url.encode(utf8.encode(json)).replaceAll('=', '');
    return '$scheme://pair?d=$data';
  }

  static List<int> _hexToBytes(String hex) => [
    for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
  ];

  static String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

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
    if (decoded is! List<dynamic> || decoded.length != 9) {
      throw const PairingFormatException('unexpected structure');
    }
    final list = decoded;
    if (list[0] != version) {
      throw const PairingFormatException('unsupported version');
    }

    String text(int index, String name, {required int min, required int max}) {
      final value = list[index];
      if (value is! String || value.length < min || value.length > max) {
        throw PairingFormatException('bad $name');
      }
      return value;
    }

    final ssid = text(1, 'ssid', min: 1, max: 32);
    final passphrase = text(2, 'pass', min: 8, max: 63); // WPA2 length limits
    final ip = text(3, 'ip', min: 7, max: 15);
    final fingerprintText = text(5, 'fp', min: 43, max: 43);
    final token = text(6, 'tok', min: 16, max: 64);
    final pin = text(7, 'pin', min: 4, max: 8);
    final alias = text(8, 'name', min: 1, max: 64);

    final String fingerprint;
    try {
      final bytes = base64Url.decode('$fingerprintText=');
      if (bytes.length != 32) throw const FormatException();
      fingerprint = _bytesToHex(bytes);
    } on FormatException {
      throw const PairingFormatException('bad fp');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(token)) {
      throw const PairingFormatException('bad tok');
    }
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      throw const PairingFormatException('bad pin');
    }
    final port = list[4];
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
