import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

/// A device's TLS identity: a self-signed certificate and its private key.
/// The device fingerprint is the SHA-256 hash of the certificate (DER).
class DeviceIdentity {
  const DeviceIdentity({
    required this.certificatePem,
    required this.privateKeyPem,
    required this.fingerprint,
  });

  final String certificatePem;
  final String privateKeyPem;
  final String fingerprint;

  /// Generates a fresh RSA-2048 key and a 10-year self-signed certificate.
  static DeviceIdentity generate({String commonName = 'Zajel'}) {
    final pair = CryptoUtils.generateRSAKeyPair();
    final privateKey = pair.privateKey as RSAPrivateKey;
    final publicKey = pair.publicKey as RSAPublicKey;
    final csr = X509Utils.generateRsaCsrPem({
      'CN': commonName,
      'O': 'Zajel',
    }, privateKey, publicKey);
    final certificatePem = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      3650,
    );
    return DeviceIdentity(
      certificatePem: certificatePem,
      privateKeyPem: CryptoUtils.encodeRSAPrivateKeyToPem(privateKey),
      fingerprint: fingerprintOfPem(certificatePem),
    );
  }

  /// Loads the identity stored in [directory], creating and saving it on first
  /// run so the fingerprint stays stable across launches.
  static Future<DeviceIdentity> loadOrCreate(Directory directory) async {
    final certFile = File('${directory.path}/zajel_cert.pem');
    final keyFile = File('${directory.path}/zajel_key.pem');
    if (await certFile.exists() && await keyFile.exists()) {
      final certPem = await certFile.readAsString();
      return DeviceIdentity(
        certificatePem: certPem,
        privateKeyPem: await keyFile.readAsString(),
        fingerprint: fingerprintOfPem(certPem),
      );
    }
    final identity = generate();
    await directory.create(recursive: true);
    await certFile.writeAsString(identity.certificatePem);
    await keyFile.writeAsString(identity.privateKeyPem);
    return identity;
  }

  /// SHA-256 of the DER certificate as lowercase hex, which is how LocalSend
  /// derives the fingerprint.
  static String fingerprintOfPem(String pem) =>
      fingerprintOfDer(_derFromPem(pem));

  static String fingerprintOfDer(List<int> der) =>
      sha256.convert(der).toString();

  SecurityContext toSecurityContext() => SecurityContext()
    ..useCertificateChainBytes(utf8.encode(certificatePem))
    ..usePrivateKeyBytes(utf8.encode(privateKeyPem));

  static Uint8List _derFromPem(String pem) {
    final body = const LineSplitter()
        .convert(pem)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('-----'))
        .join();
    return base64.decode(body);
  }
}
