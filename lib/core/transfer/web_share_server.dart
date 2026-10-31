import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'protocol_models.dart';
import 'receive_server.dart';
import 'send_client.dart';
import 'web_share_page.dart';

/// Lets a device with only a browser exchange files with this one.
///
/// Browsers refuse the self-signed certificates the rest of Zajel relies on, so
/// this is the one place that serves plain HTTP. To keep that acceptable:
///
/// - it only runs while the user has switched it on, and shows a warning;
/// - every request needs a random token that is only in the link and QR code;
/// - uploads from the browser go through the normal receive path: the user must
///   accept them, names are sanitized, and the PIN (if any) is asked for.
///
/// Browser uploads use the LocalSend `prepare-upload`/`upload` routes, and
/// downloads use its `prepare-download`/`download` routes.
class WebShareServer {
  WebShareServer({
    required this.device,
    required this.receiver,
    required this.strings,
    required this.rtl,
    this.files = const [],
  });

  final DeviceInfo device;

  /// Handles the upload routes. Never started on its own: this server owns the
  /// socket and forwards requests to it.
  final ReceiveServer receiver;
  final WebPageStrings strings;
  final bool rtl;

  /// Files offered for download.
  final List<SendFile> files;

  static const defaultPort = 53318;

  final _random = Random.secure();
  late final String token = _newToken();
  late final String _downloadSession = _newToken();
  HttpServer? _server;

  int get port => _server!.port;

  Future<void> start({
    InternetAddress? address,
    int port = defaultPort,
  }) async {
    final bindAddress = address ?? InternetAddress.anyIPv4;
    try {
      _server = await HttpServer.bind(bindAddress, port);
    } on SocketException {
      // The default port is taken (for example a second share): use any port.
      _server = await HttpServer.bind(bindAddress, 0);
    }
    _server!.listen(_handle);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// The link to show as text and QR code.
  Uri linkFor(InternetAddress host) =>
      Uri(scheme: 'http', host: host.address, port: port, queryParameters: {'t': token});

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (request.uri.queryParameters['t'] case final t? when _validToken(t)) {
        if (path == '/') return await _page(request);
        if (path.startsWith(localSendApiPrefix)) return await _api(request, path);
      }
      await _plain(request, path == '/' || path.startsWith(localSendApiPrefix) ? 403 : 404);
    } catch (_) {
      try {
        await _plain(request, 500);
      } catch (_) {
        // Connection already gone.
      }
    }
  }

  Future<void> _api(HttpRequest request, String path) async {
    switch ((request.method, path)) {
      case ('POST', '$localSendApiPrefix/prepare-download'):
        await _prepareDownload(request);
      case ('GET', '$localSendApiPrefix/download'):
        await _download(request);
      default:
        // info, register, prepare-upload, upload, cancel: the normal receiver.
        await receiver.handleRequest(request);
    }
  }

  Future<void> _page(HttpRequest request) async {
    final html = buildWebSharePage(
      strings: strings,
      deviceName: device.alias,
      rtl: rtl,
    );
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      // The page loads nothing from outside and sends nothing but to itself.
      ..headers.set(
        'content-security-policy',
        "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; "
            "connect-src 'self'; img-src 'none'; base-uri 'none'; form-action 'none'",
      )
      ..headers.set('referrer-policy', 'no-referrer')
      ..headers.set('cache-control', 'no-store')
      ..write(html);
    await request.response.close();
  }

  Future<void> _prepareDownload(HttpRequest request) async {
    await request.drain<void>();
    final pin = receiver.pin;
    if (pin != null && request.uri.queryParameters['pin'] != pin) {
      return _plain(request, 401);
    }
    final body = {
      'info': device.toInfoJson(),
      'sessionId': _downloadSession,
      'files': {
        for (final f in files)
          f.id: FileMetadata(
            id: f.id,
            fileName: f.name,
            size: f.size,
            fileType: f.toMetadata().fileType,
          ).toJson(),
      },
    };
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> _download(HttpRequest request) async {
    final query = request.uri.queryParameters;
    if (query['sessionId'] != _downloadSession) return _plain(request, 403);
    final file = files.where((f) => f.id == query['fileId']).firstOrNull;
    if (file == null) return _plain(request, 404);

    final response = request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.binary
      ..headers.contentLength = file.size
      ..headers.set(
        'content-disposition',
        "attachment; filename*=UTF-8''${Uri.encodeComponent(p.basename(file.name))}",
      )
      ..headers.set('x-content-type-options', 'nosniff');
    // Streams from disk; the file is never held in memory.
    await response.addStream(file.file.openRead());
    await response.close();
  }

  Future<void> _plain(HttpRequest request, int status) async {
    request.response.statusCode = status;
    await request.response.close();
  }

  bool _validToken(String candidate) {
    final a = utf8.encode(candidate);
    final b = utf8.encode(token);
    var diff = a.length ^ b.length;
    for (var i = 0; i < min(a.length, b.length); i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  String _newToken() =>
      base64Url.encode(List.generate(15, (_) => _random.nextInt(256)));
}

/// The device's addresses on private networks, most likely first. Used to build
/// the link people open in a browser.
Future<List<InternetAddress>> lanAddresses() async {
  bool isPrivate(InternetAddress a) {
    final b = a.rawAddress;
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168);
  }

  final all = [
    for (final interface in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    ))
      ...interface.addresses.where((a) => !a.isLoopback && !a.isLinkLocal),
  ];
  return [...all.where(isPrivate), ...all.where((a) => !isPrivate(a))];
}
