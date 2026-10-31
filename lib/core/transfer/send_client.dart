import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../security/device_identity.dart';
import 'protocol_models.dart';
import 'range_set.dart';
import 'tar_stream.dart';

/// A local file queued for sending.
class SendFile {
  SendFile({required this.id, required this.file, required this.size, String? name})
    : name = name ?? p.basename(file.path);

  static Future<SendFile> fromPath(String path, {required String id, String? name}) async {
    final file = File(path);
    return SendFile(id: id, file: file, size: await file.length(), name: name);
  }

  final String id;
  final File file;
  final int size;
  final String name;

  FileMetadata toMetadata() => FileMetadata(
    id: id,
    fileName: name,
    size: size,
    fileType: lookupMimeType(file.path) ?? 'application/octet-stream',
  );
}

class SendException implements Exception {
  const SendException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get declined => statusCode == 403;
  bool get pinRequired => statusCode == 401;
  bool get busy => statusCode == 409;
  bool get tooManyRequests => statusCode == 429;

  @override
  String toString() => 'SendException($statusCode): $message';
}

class SendSession {
  const SendSession({
    required this.sessionId,
    required this.tokens,
    required this.target,
    this.chunked = false,
    this.dataPort,
    this.tarToken,
  });

  final String sessionId;
  final Map<String, String> tokens;
  final SendPeer target;

  /// The receiver is a Zajel that accepts chunked, parallel uploads.
  final bool chunked;

  /// Where an Android receiver's native data server listens, if it has one.
  final int? dataPort;

  /// Authorizes the tar upload of small files, when the receiver offers it.
  final String? tarToken;
}

/// Tuning for chunked uploads (Zajel-to-Zajel only).
class UploadOptions {
  const UploadOptions({
    this.chunkSize = 8 * 1024 * 1024,
    this.parallel = 4,
    this.retries = 3,
    this.tarMaxFileSize = 256 * 1024,
    this.tarMinFiles = 4,
  });

  /// Chunks are 4-8 MB: big enough to keep the link busy, small enough that a
  /// dropped connection loses little work.
  final int chunkSize;

  /// Simultaneous TCP connections.
  final int parallel;

  /// Extra attempts for a failed chunk before the transfer fails.
  final int retries;

  /// Files smaller than this are bundled into one tar request...
  final int tarMaxFileSize;

  /// ...when there are at least this many of them.
  final int tarMinFiles;
}

class BenchmarkResult {
  const BenchmarkResult({
    required this.bytes,
    required this.connectMs,
    required this.transferMs,
  });

  final int bytes;

  /// Time to open the TLS connection and send the first byte.
  final int connectMs;
  final int transferMs;

  double get megabytesPerSecond =>
      transferMs == 0 ? 0 : bytes / (1024 * 1024) / (transferMs / 1000);
}

class SendPeer {
  const SendPeer(this.address, this.port, this.fingerprint);

  final InternetAddress address;
  final int port;
  final String? fingerprint;
}

/// Sender side of LocalSend v2. All traffic is HTTPS; peers that only offer
/// plain HTTP are refused.
class SendClient {
  SendClient({required this.self});

  final DeviceInfo self;

  /// Skips the Zajel extension header, to behave like a stock LocalSend
  /// sender. Used by interop tests.
  bool offerExtensions = true;

  Future<SendSession> prepareUpload({
    required InternetAddress address,
    required int port,
    required List<SendFile> files,
    String? expectedFingerprint,
    String? pin,
    String? pairToken,
  }) async {
    final peer = SendPeer(address, port, expectedFingerprint);
    final request = PrepareUploadRequest(
      info: self,
      files: {for (final f in files) f.id: f.toMetadata()},
    );
    final response = await _post(
      peer,
      '/prepare-upload',
      query: {'pin': ?pin, 'pair': ?pairToken},
      body: jsonEncode(request.toJson()),
      headers: {if (offerExtensions) zajelExtensionHeader: zajelExtensionVersion},
    );
    if (response.status == 204) {
      return SendSession(sessionId: '', tokens: const {}, target: peer);
    }
    _expect(response, 200);
    final chunked =
        offerExtensions && response.extension == zajelExtensionVersion;
    final parsed = PrepareUploadResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    return SendSession(
      sessionId: parsed.sessionId,
      tokens: parsed.files,
      target: peer,
      chunked: chunked,
      dataPort: chunked ? int.tryParse(response.dataPort ?? '') : null,
      tarToken: chunked ? response.tarToken : null,
    );
  }

  /// Uploads every accepted file in [files], one after another. Each file is
  /// streamed from disk. Against a Zajel receiver, big files go as parallel
  /// chunks; against anything else, as one plain LocalSend upload.
  ///
  /// Calling this again on the same [session] after a failure resumes: the
  /// receiver is asked what it already has and only the rest is sent.
  /// [onProgress] gets (fileId, bytesSent).
  Future<void> upload({
    required SendSession session,
    required List<SendFile> files,
    void Function(String fileId, int sent)? onProgress,
    bool Function()? isCancelled,
    UploadOptions options = const UploadOptions(),
  }) async {
    // Many small files go as one tar request, which saves a round trip each.
    final bundled = <String>{};
    final tarToken = session.tarToken;
    if (tarToken != null) {
      final small = [
        for (final file in files)
          if (session.tokens.containsKey(file.id) &&
              file.size < options.tarMaxFileSize &&
              utf8.encode(file.id).length <= 100)
            file,
      ];
      if (small.length >= options.tarMinFiles) {
        await _uploadTar(session, tarToken, small, onProgress, isCancelled);
        bundled.addAll(small.map((f) => f.id));
      }
    }

    for (final file in files) {
      final token = session.tokens[file.id];
      if (token == null) continue; // declined by the receiver
      if (bundled.contains(file.id)) continue;
      if (isCancelled?.call() ?? false) return;
      if (session.chunked && file.size >= options.chunkSize) {
        await _uploadChunked(session, file, token, options, onProgress, isCancelled);
      } else {
        await _uploadOne(session, file, token, onProgress, isCancelled);
      }
    }
  }

  /// Sends [files] as one tar archive. Entry names are the file ids. After a
  /// dropped connection, calling this again sends only the files the receiver
  /// has not finished.
  Future<void> _uploadTar(
    SendSession session,
    String tarToken,
    List<SendFile> files,
    void Function(String fileId, int sent)? onProgress,
    bool Function()? isCancelled,
  ) async {
    final client = _newClient(session.target);
    try {
      final query = {'sessionId': session.sessionId, 'token': tarToken};

      final statusRequest = await client.getUrl(
        _uri(session.target, '/zajel/tar-status', query),
      );
      final statusResponse = await statusRequest.close();
      final statusBody = await utf8.decodeStream(statusResponse);
      final done = statusResponse.statusCode == 200
          ? ((jsonDecode(statusBody) as Map<String, dynamic>)['done'] as List)
                .cast<String>()
                .toSet()
          : <String>{};
      for (final file in files.where((f) => done.contains(f.id))) {
        onProgress?.call(file.id, file.size);
      }
      final remaining = [
        for (final file in files)
          if (!done.contains(file.id)) file,
      ];
      if (remaining.isEmpty) return;

      final entries = [
        for (final file in remaining)
          TarEntry(
            name: file.id,
            size: file.size,
            open: () => file.file.openRead(),
          ),
      ];
      final request = await client.postUrl(
        _uri(session.target, '/zajel/tar', query),
      );
      request.headers
        ..contentType = ContentType.binary
        ..contentLength = tarLength(entries);
      await request.addStream(
        tarEncode(
          entries,
          onBytes: (name, bytes) => onProgress?.call(name, bytes),
        ).map((chunk) {
          if (isCancelled?.call() ?? false) {
            throw const SendException('Cancelled');
          }
          return chunk;
        }),
      );
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      if (response.statusCode != 200) {
        throw SendException(
          _messageOf(body) ?? 'Archive upload failed',
          statusCode: response.statusCode,
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _uploadChunked(
    SendSession session,
    SendFile file,
    String token,
    UploadOptions options,
    void Function(String fileId, int sent)? onProgress,
    bool Function()? isCancelled,
  ) async {
    // Resume: skip whatever the receiver already holds.
    final have = await _receivedRanges(session, file, token);
    if (have.isComplete(file.size)) {
      onProgress?.call(file.id, file.size);
      return;
    }
    final pending = Queue<(int, int)>.of(
      have.missing(file.size, options.chunkSize),
    );
    var sent = have.covered;
    onProgress?.call(file.id, sent);

    // Android receivers run a native data server and advertise its port. Chunks
    // go there. If it cannot be reached before any chunk got through, fall back
    // to the main port, which accepts the same chunks.
    var useDataPort = session.dataPort != null;
    var dataPortWorked = false;
    SendPeer chunkPeer() => useDataPort
        ? SendPeer(
            session.target.address,
            session.dataPort!,
            session.target.fingerprint,
          )
        : session.target;

    Future<void> worker() async {
      // One client per worker keeps a TLS connection open across its chunks.
      var onDataPort = useDataPort;
      var client = _newClient(chunkPeer());
      try {
        while (pending.isNotEmpty) {
          if (isCancelled?.call() ?? false) return;
          final (start, end) = pending.removeFirst();
          var attempt = 0;
          while (true) {
            if (onDataPort != useDataPort) {
              client.close(force: true);
              onDataPort = useDataPort;
              client = _newClient(chunkPeer());
            }
            var inFlight = 0;
            try {
              await _sendChunk(
                client,
                chunkPeer(),
                session,
                file,
                token,
                start,
                end,
                (n) {
                  inFlight += n;
                  sent += n;
                  onProgress?.call(file.id, sent);
                },
                isCancelled,
              );
              if (onDataPort) dataPortWorked = true;
              break;
            } catch (e) {
              sent -= inFlight; // this chunk starts over
              if (isCancelled?.call() ?? false) rethrow;
              if (onDataPort &&
                  !dataPortWorked &&
                  (e is SocketException || e is TlsException)) {
                useDataPort = false;
                continue; // switching routes is not a retry
              }
              if (attempt++ >= options.retries || !isTransientError(e)) {
                rethrow;
              }
              await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
            }
          }
        }
      } finally {
        client.close(force: true);
      }
    }


    final workers = [
      for (var i = 0; i < options.parallel && i < pending.length; i++) worker(),
    ];
    // Stop the others as soon as one worker gives up.
    try {
      await Future.wait(workers, eagerError: true);
    } catch (_) {
      pending.clear();
      rethrow;
    }
  }

  static bool isTransientError(Object error) {
    if (error is SendException) {
      // 5xx and dropped connections may recover; 4xx are final answers.
      final status = error.statusCode;
      return status == null || status >= 500;
    }
    return error is SocketException ||
        error is HttpException ||
        error is TlsException ||
        error is TimeoutException;
  }

  Future<void> _sendChunk(
    HttpClient client,
    SendPeer peer,
    SendSession session,
    SendFile file,
    String token,
    int start,
    int end,
    void Function(int bytes) onBytes,
    bool Function()? isCancelled,
  ) async {
    final request = await client.postUrl(
      _uri(peer, '/upload', {
        'sessionId': session.sessionId,
        'fileId': file.id,
        'token': token,
        'offset': '$start',
      }),
    );
    request.headers
      ..contentType = ContentType.binary
      ..contentLength = end - start;
    await request.addStream(
      file.file.openRead(start, end).map((data) {
        if (isCancelled?.call() ?? false) {
          throw const SendException('Cancelled');
        }
        onBytes(data.length);
        return data;
      }),
    );
    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode != 200) {
      throw SendException('Chunk failed', statusCode: response.statusCode);
    }
  }

  Future<RangeSet> _receivedRanges(
    SendSession session,
    SendFile file,
    String token,
  ) async {
    final client = _newClient(session.target);
    try {
      final request = await client.getUrl(
        _uri(session.target, '/zajel/progress', {
          'sessionId': session.sessionId,
          'fileId': file.id,
          'token': token,
        }),
      );
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      if (response.statusCode != 200) return RangeSet();
      final json = jsonDecode(body) as Map<String, dynamic>;
      return RangeSet.fromJson(json['ranges'] as List<dynamic>);
    } finally {
      client.close(force: true);
    }
  }

  /// Sends [bytes] of zeros to the peer's speed-test endpoint and times it.
  /// Nothing is written to disk on either side. Needs a Zajel peer.
  Future<BenchmarkResult> benchmark({
    required InternetAddress address,
    required int port,
    required String expectedFingerprint,
    int bytes = 256 * 1024 * 1024,
  }) async {
    final peer = SendPeer(address, port, expectedFingerprint);
    final client = _newClient(peer);
    try {
      final watch = Stopwatch()..start();
      final request = await client.postUrl(
        _uri(peer, '/zajel/benchmark', const {}),
      );
      request.headers
        ..contentType = ContentType.binary
        ..contentLength = bytes;
      // The first flush completes the TLS handshake and sends the headers.
      await request.flush();
      final connectMs = watch.elapsedMilliseconds;

      final block = Uint8List(1 << 20);
      watch
        ..reset()
        ..start();
      var remaining = bytes;
      while (remaining > 0) {
        final n = remaining < block.length ? remaining : block.length;
        request.add(n == block.length ? block : Uint8List.sublistView(block, 0, n));
        remaining -= n;
        // Respect back-pressure so the whole payload is never queued in memory.
        await request.flush();
      }
      final response = await request.close();
      await response.drain<void>();
      watch.stop();
      if (response.statusCode != 200) {
        throw SendException('Benchmark failed', statusCode: response.statusCode);
      }
      return BenchmarkResult(
        bytes: bytes,
        connectMs: connectMs,
        transferMs: watch.elapsedMilliseconds,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> cancel(SendSession session) async {
    if (session.sessionId.isEmpty) return;
    await _post(
      session.target,
      '/cancel',
      query: {'sessionId': session.sessionId},
    );
  }

  Future<void> _uploadOne(
    SendSession session,
    SendFile file,
    String token,
    void Function(String fileId, int sent)? onProgress,
    bool Function()? isCancelled,
  ) async {
    final client = _newClient(session.target);
    try {
      final uri = _uri(session.target, '/upload', {
        'sessionId': session.sessionId,
        'fileId': file.id,
        'token': token,
      });
      final request = await client.postUrl(uri);
      request.headers
        ..contentType = ContentType.binary
        ..contentLength = file.size;
      var sent = 0;
      await request.addStream(
        file.file.openRead().map((chunk) {
          if (isCancelled?.call() ?? false) {
            throw const SendException('Cancelled');
          }
          sent += chunk.length;
          onProgress?.call(file.id, sent);
          return chunk;
        }),
      );
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode != 200) {
        throw SendException('Upload failed', statusCode: response.statusCode);
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<_Response> _post(
    SendPeer peer,
    String route, {
    Map<String, String> query = const {},
    String? body,
    Map<String, String> headers = const {},
  }) async {
    final client = _newClient(peer);
    try {
      final request = await client.postUrl(_uri(peer, route, query));
      headers.forEach(request.headers.set);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(body);
      }
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      return _Response(
        response.statusCode,
        text,
        response.headers.value(zajelExtensionHeader),
        response.headers.value(zajelDataPortHeader),
        response.headers.value(zajelTarTokenHeader),
      );
    } finally {
      client.close(force: true);
    }
  }

  Uri _uri(SendPeer peer, String route, Map<String, String> query) => Uri(
    scheme: 'https',
    host: peer.address.address,
    port: peer.port,
    path: '$localSendApiPrefix$route',
    queryParameters: query.isEmpty ? null : query,
  );

  HttpClient _newClient(SendPeer peer) {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..badCertificateCallback = (cert, host, port) {
        // Peers use self-signed certificates, so identity is the fingerprint.
        // An unknown fingerprint is refused: no trust-on-first-use.
        final seen = DeviceIdentity.fingerprintOfDer(cert.der);
        final expected = peer.fingerprint;
        return expected != null && expected.toLowerCase() == seen;
      };
    return client;
  }

  void _expect(_Response response, int status) {
    if (response.status != status) {
      throw SendException(
        _messageOf(response.body) ?? 'Unexpected response',
        statusCode: response.status,
      );
    }
  }

  String? _messageOf(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? decoded['message'] as String? : null;
    } catch (_) {
      return null;
    }
  }
}

class _Response {
  const _Response(
    this.status,
    this.body,
    this.extension,
    this.dataPort,
    this.tarToken,
  );
  final int status;
  final String body;
  final String? extension;
  final String? dataPort;
  final String? tarToken;
}

/// SHA-256 of a file, streamed (used by tests and optional pre-hashing).
Future<String> sha256OfFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();
