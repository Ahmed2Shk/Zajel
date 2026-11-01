import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../platform/native_data_bridge.dart';
import '../security/device_identity.dart';
import '../security/file_name_sanitizer.dart';
import 'protocol_models.dart';
import 'range_set.dart';
import 'tar_stream.dart';

/// What the receiver sees when a sender asks to upload files.
class IncomingTransfer {
  const IncomingTransfer({
    required this.sender,
    required this.senderAddress,
    required this.files,
  });

  final DeviceInfo sender;
  final InternetAddress senderAddress;
  final Map<String, FileMetadata> files;

  int get totalBytes => files.values.fold(0, (sum, f) => sum + f.size);
}

/// Returns the ids of the files the user accepts, or null to decline.
typedef IncomingDecision =
    Future<Set<String>?> Function(IncomingTransfer transfer);

sealed class ReceiveEvent {
  const ReceiveEvent(this.sessionId);
  final String sessionId;
}

class SessionStarted extends ReceiveEvent {
  const SessionStarted(super.sessionId, this.transfer);
  final IncomingTransfer transfer;
}

class FileProgress extends ReceiveEvent {
  const FileProgress(super.sessionId, this.fileId, this.received, this.total);
  final String fileId;
  final int received;
  final int total;
}

class FileReceived extends ReceiveEvent {
  const FileReceived(super.sessionId, this.fileId, this.path);
  final String fileId;
  final String path;
}

class SessionEnded extends ReceiveEvent {
  const SessionEnded(super.sessionId, {required this.cancelled});
  final bool cancelled;
}

class _AcceptedFile {
  _AcceptedFile(this.meta, this.token);

  final FileMetadata meta;
  final String token;
  bool done = false;
  String? partPath;

  // Chunked (Zajel-to-Zajel) uploads only.
  final received = RangeSet();
  Future<File>? allocation;
  File? destination;
  int liveBytes = 0;
  bool finishing = false;

  /// The native data server has written to this file.
  bool nativeTouched = false;

  /// Bytes the native server holds of chunks that are still arriving.
  int nativeLiveBytes = 0;

  RandomAccessFile? _handle;
  Future<void> _writeQueue = Future.value();

  void attachHandle(RandomAccessFile handle) => _handle = handle;

  /// Writes [data] at [position]. Every chunk of the file shares one handle, so
  /// each seek-and-write pair runs alone; otherwise two chunks arriving at the
  /// same time would move each other's position.
  Future<void> writeAt(int position, List<int> data) {
    final turn = _writeQueue.then((_) async {
      final handle = _handle;
      if (handle == null) throw const _HttpError(500, 'File is closed');
      await handle.setPosition(position);
      await handle.writeFrom(data);
    });
    _writeQueue = turn.then((_) {}, onError: (_) {});
    return turn;
  }

  /// Flushes pending writes and closes the file.
  Future<void> closeHandle() async {
    await _writeQueue;
    final handle = _handle;
    _handle = null;
    if (handle != null) {
      await handle.flush();
      await handle.close();
    }
  }
}

class _Session {
  _Session(this.id, this.transfer, this.files, this.tarToken);

  final String id;
  final IncomingTransfer transfer;
  final Map<String, _AcceptedFile> files;

  /// Authorizes the tar upload of small files for this session.
  final String tarToken;

  bool get finished => files.values.every((f) => f.done);
}

/// HTTPS server implementing the receiving side of LocalSend v2:
/// `/register`, `/info`, `/prepare-upload`, `/upload`, `/cancel`.
class ReceiveServer {
  ReceiveServer({
    required this.identity,
    required this.device,
    required this.downloadDirectory,
    required this.onIncoming,
    this.onDeviceRegistered,
    this.pin,
    this.enableChunking = true,
    this.sessionIdleTimeout = const Duration(minutes: 2),
    this.nativeData,
    this.onError,
    this.onNote,
  });

  final DeviceIdentity identity;
  final DeviceInfo device;
  final Directory downloadDirectory;
  final IncomingDecision onIncoming;
  final void Function(DeviceInfo device, InternetAddress address)?
  onDeviceRegistered;

  /// When set, `prepare-upload` requires `?pin=`.
  final String? pin;

  /// Offers the Zajel chunked-upload extension to Zajel senders. Turn off to
  /// behave exactly like a stock LocalSend receiver.
  final bool enableChunking;

  /// Android only: the Kotlin data server that writes chunks to disk.
  final NativeDataBridge? nativeData;

  /// Called with unexpected errors (not the expected 4xx answers), for logging.
  final void Function(Object error, StackTrace stack)? onError;

  /// Plain-text notes about the session (who ended it, which data path), for the log.
  final void Function(String note)? onNote;
  int? _dataPort;

  /// A session with no traffic for this long is dropped, so a sender that
  /// vanishes cannot keep the receiver busy (and the phone awake) forever.
  final Duration sessionIdleTimeout;
  Timer? _idleTimer;

  static const maxPinAttempts = 5;
  static const pinLockout = Duration(seconds: 60);

  final _events = StreamController<ReceiveEvent>.broadcast();
  final _random = Random.secure();
  final _pinFailures = <String, List<DateTime>>{};
  HttpServer? _server;
  _Session? _session;
  ({String token, String pin})? _pairing;

  Stream<ReceiveEvent> get events => _events.stream;

  /// How many plain uploads and tar uploads were served. For tests and the
  /// benchmark, to see which route a transfer used.
  int plainUploadRequests = 0;
  int tarUploadRequests = 0;
  int get port => _server!.port;

  Future<void> start({
    int port = localSendDefaultPort,
    InternetAddress? address,
  }) async {
    final server = await HttpServer.bindSecure(
      address ?? InternetAddress.anyIPv4,
      port,
      identity.toSecurityContext(),
      shared: true,
    );
    _server = server;
    server.listen(_handle);

    final bridge = nativeData;
    if (bridge != null && enableChunking) {
      try {
        _dataPort = await bridge.start(identity);
        bridge.onChunk = _onNativeChunk;
        bridge.onProgress = _onNativeProgress;
      } catch (_) {
        // No native server: chunks simply go through Dart.
        _dataPort = null;
      }
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    await _abortSession(cancelled: true);
    try {
      await nativeData?.stop();
    } catch (_) {}
    _dataPort = null;
  }

  /// Handles one request. The server calls this for its own socket; the web
  /// share server calls it for the upload routes it forwards.
  Future<void> handleRequest(HttpRequest request) => _handle(request);

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      switch ((request.method, path)) {
        case ('GET', '$localSendApiPrefix/info'):
          await _json(request, 200, device.toInfoJson());
        case ('POST', '$localSendApiPrefix/register'):
          await _register(request);
        case ('POST', '$localSendApiPrefix/prepare-upload'):
          await _prepareUpload(request);
        case ('POST', '$localSendApiPrefix/upload'):
          await _upload(request);
        case ('POST', '$localSendApiPrefix/cancel'):
          await _cancel(request);
        case ('GET', zajelProgressRoute) when enableChunking:
          await _progress(request);
        case ('POST', zajelBenchmarkRoute) when enableChunking:
          await _benchmark(request);
        case ('POST', zajelTarRoute) when enableChunking:
          await _uploadTar(request);
        case ('GET', zajelTarStatusRoute) when enableChunking:
          await _tarStatus(request);
        default:
          await _empty(request, 404);
      }
    } on _HttpError catch (e) {
      await _empty(request, e.status, message: e.message);
    } on FormatException {
      await _empty(request, 400, message: 'Invalid body');
    } on TarFormatException catch (e) {
      await _empty(request, 400, message: e.toString());
    } on UnsafeFileNameException catch (e) {
      await _empty(request, 400, message: e.toString());
    } catch (e, stack) {
      onError?.call(e, stack);
      try {
        await _empty(request, 500);
      } catch (_) {
        // Connection already gone.
      }
    }
  }

  Future<void> _register(HttpRequest request) async {
    final body = await _readJson(request);
    final peer = DeviceInfo.fromJson(body);
    if (peer.fingerprint != device.fingerprint) {
      onDeviceRegistered?.call(peer, request.connectionInfo!.remoteAddress);
    }
    await _json(request, 200, device.toInfoJson());
  }

  Future<void> _prepareUpload(HttpRequest request) async {
    final ip = request.connectionInfo!.remoteAddress;
    _checkPin(request, ip);

    final body = PrepareUploadRequest.fromJson(await _readJson(request));
    if (body.files.isEmpty) {
      await _empty(request, 204);
      return;
    }
    for (final file in body.files.values) {
      sanitizeReceivedFileName(file.fileName);
      if (file.size < 0) throw const FormatException('negative size');
    }
    if (_session != null) throw const _HttpError(409, 'Blocked by another session');

    final transfer = IncomingTransfer(
      sender: body.info,
      senderAddress: ip,
      files: body.files,
    );
    final accepted = await onIncoming(transfer);
    if (accepted == null || accepted.isEmpty) {
      throw const _HttpError(403, 'Rejected');
    }
    // The dialog is async; another sender may have claimed the slot meanwhile.
    if (_session != null) throw const _HttpError(409, 'Blocked by another session');

    final session = _Session(
      _randomToken(),
      transfer,
      {
        for (final id in accepted)
          if (body.files.containsKey(id))
            id: _AcceptedFile(body.files[id]!, _randomToken()),
      },
      _randomToken(),
    );
    _session = session;
    _pairing = null; // a pairing code works once
    _touch();
    _events.add(SessionStarted(session.id, transfer));

    // Only a Zajel sender asks for the extension, and only then do we answer.
    final extensions =
        enableChunking &&
        request.headers.value(zajelExtensionHeader) == zajelExtensionVersion;

    // With a native data server, each file gets its part file now and the
    // server is told who may write to it.
    final dataPort = extensions ? _dataPort : null;
    onNote?.call(
      'session started: zajel extensions=$extensions, native data port=${dataPort != null}, '
      'files=${session.files.length}',
    );
    if (dataPort != null) {
      try {
        for (final entry in session.files.entries) {
          final part = await _reserve(entry.value);
          await nativeData!.register(
            sessionId: session.id,
            fileId: entry.key,
            token: entry.value.token,
            path: part.path,
            size: entry.value.meta.size,
            senderAddress: ip.address,
          );
        }
      } catch (_) {
        await _abortSession(cancelled: true);
        rethrow;
      }
    }

    await _json(
      request,
      200,
      PrepareUploadResponse(
        sessionId: session.id,
        files: {for (final e in session.files.entries) e.key: e.value.token},
      ).toJson(),
      headers: {
        if (extensions) zajelExtensionHeader: zajelExtensionVersion,
        zajelDataPortHeader: ?(dataPort == null ? null : '$dataPort'),
        if (extensions) zajelTarTokenHeader: session.tarToken,
      },
    );
  }

  /// Checks `sessionId`, `fileId` and `token` against the active session and
  /// that the caller is the sender's address.
  (_Session, _AcceptedFile, String) _authorize(HttpRequest request) {
    final query = request.uri.queryParameters;
    final sessionId = query['sessionId'];
    final fileId = query['fileId'];
    final token = query['token'];
    if (sessionId == null || fileId == null || token == null) {
      throw const _HttpError(400, 'Missing parameters');
    }
    final session = _session;
    final file = session?.files[fileId];
    if (session == null ||
        session.id != sessionId ||
        file == null ||
        file.token != token ||
        request.connectionInfo!.remoteAddress != session.transfer.senderAddress) {
      throw const _HttpError(403, 'Invalid token or IP address');
    }
    return (session, file, fileId);
  }

  Future<void> _upload(HttpRequest request) async {
    final (session, file, fileId) = _authorize(request);
    if (file.done) throw const _HttpError(403, 'Invalid token or IP address');
    plainUploadRequests++;

    if (enableChunking && request.uri.queryParameters.containsKey('offset')) {
      await _uploadChunk(request, session, file, fileId);
      return;
    }

    final part = await _reserve(file);
    final destination = file.destination!;

    // Stream to disk and hash on the fly; the file is never held in memory.
    final digestSink = _DigestCollector();
    final hasher = sha256.startChunkedConversion(digestSink);
    var received = 0;
    final sink = part.openWrite();
    try {
      await sink.addStream(
        request.map((chunk) {
          hasher.add(chunk);
          received += chunk.length;
          _touch();
          _events.add(FileProgress(session.id, fileId, received, file.meta.size));
          return chunk;
        }),
      );
      await sink.close();
    } catch (_) {
      await sink.close().catchError((_) {});
      await _deleteQuietly(part);
      rethrow;
    }
    hasher.close();

    if (received != file.meta.size) {
      await _deleteQuietly(part);
      throw const _HttpError(400, 'Size mismatch');
    }
    final expected = file.meta.sha256;
    if (expected != null &&
        expected.toLowerCase() != digestSink.digest.toString()) {
      await _deleteQuietly(part);
      throw const _HttpError(422, 'Checksum mismatch');
    }

    await part.rename(destination.path);
    file.done = true;
    file.partPath = null;
    _events.add(FileReceived(session.id, fileId, destination.path));
    await _empty(request, 200);
    _endSessionIfFinished(session);
  }

  /// One chunk of a file, at `?offset=`. Chunks may arrive in any order over
  /// several connections at once; each request writes through its own file
  /// handle so concurrent chunks cannot disturb each other's position.
  Future<void> _uploadChunk(
    HttpRequest request,
    _Session session,
    _AcceptedFile file,
    String fileId,
  ) async {
    final size = file.meta.size;
    final offset = int.tryParse(request.uri.queryParameters['offset'] ?? '');
    final length = request.contentLength;
    if (offset == null || offset < 0 || length <= 0 || offset + length > size) {
      throw const _HttpError(400, 'Bad range');
    }

    await (file.allocation ??= _allocate(file));
    var written = 0;
    try {
      await for (final data in request) {
        if (written + data.length > length) {
          throw const _HttpError(400, 'Size mismatch');
        }
        await file.writeAt(offset + written, data);
        written += data.length;
        _touch();
        file.liveBytes += data.length;
        _events.add(
          FileProgress(
            session.id,
            fileId,
            file.received.covered + file.liveBytes,
            size,
          ),
        );
      }
      if (written != length) throw const _HttpError(400, 'Size mismatch');
    } finally {
      file.liveBytes -= written;
    }

    await _commitChunk(session, file, fileId, offset, length);
    await _empty(request, 200);
    _endSessionIfFinished(session);
  }

  /// Records that `[offset, offset + length)` is on disk, and finishes the file
  /// when that was the last missing piece. Used for chunks written by Dart and
  /// for chunks written by the native data server.
  Future<void> _commitChunk(
    _Session session,
    _AcceptedFile file,
    String fileId,
    int offset,
    int length,
  ) async {
    // A retried chunk lands on the same bytes, so adding it twice is harmless.
    file.received.add(offset, offset + length);
    _events.add(
      FileProgress(session.id, fileId, file.received.covered, file.meta.size),
    );
    if (file.received.isComplete(file.meta.size) && !file.finishing) {
      file.finishing = true;
      await _finishChunked(session, file, fileId);
    }
  }

  /// Called by the native data server while a chunk is still arriving. Without
  /// it the receiver would see nothing until a whole 8 MB chunk is on disk, and
  /// on a slow link the idle timer would end the session in the meantime.
  void _onNativeProgress(String sessionId, String fileId, int liveBytes) {
    final session = _session;
    final file = session?.files[fileId];
    if (session == null || session.id != sessionId || file == null || file.done) return;
    file.nativeLiveBytes = liveBytes;
    _touch();
    _events.add(
      FileProgress(
        session.id,
        fileId,
        (file.received.covered + liveBytes).clamp(0, file.meta.size),
        file.meta.size,
      ),
    );
  }

  /// Called by the native data server after each chunk it wrote. The returned
  /// status becomes the HTTP answer to the sender.
  Future<int> _onNativeChunk(
    String sessionId,
    String fileId,
    int offset,
    int length,
  ) async {
    try {
      final session = _session;
      final file = session?.files[fileId];
      if (session == null || session.id != sessionId || file == null || file.done) {
        return 403;
      }
      file.nativeTouched = true;
      _touch();
      await _commitChunk(session, file, fileId, offset, length);
      _endSessionIfFinished(session);
      return 200;
    } on _HttpError catch (e) {
      return e.status;
    } catch (_) {
      return 500;
    }
  }

  /// Creates the `.zajel-part` file at its final size and decides the final
  /// name. Safe to call again: it returns the same file.
  Future<File> _reserve(_AcceptedFile file) async {
    final existing = file.partPath;
    if (existing != null) return File(existing);

    final relative = sanitizeReceivedFileName(file.meta.fileName);
    final destination = await _uniqueDestination(relative);
    final part = File('${destination.path}.zajel-part');
    await part.parent.create(recursive: true);
    final handle = await part.open(mode: FileMode.write);
    await handle.truncate(file.meta.size);
    await handle.close();
    file.destination = destination;
    file.partPath = part.path;
    return part;
  }

  /// Opens the part file for chunks that arrive through Dart. Opening
  /// truncates, so it is refused once the native server has written to the
  /// file; the sender only falls back to this route before any native chunk.
  Future<File> _allocate(_AcceptedFile file) async {
    if (file.nativeTouched) {
      throw const _HttpError(409, 'File is being received by the data server');
    }
    final part = await _reserve(file);
    final handle = await part.open(mode: FileMode.write);
    await handle.truncate(file.meta.size);
    file.attachHandle(handle);
    return part;
  }

  Future<void> _finishChunked(
    _Session session,
    _AcceptedFile file,
    String fileId,
  ) async {
    final part = File(file.partPath!);
    await file.closeHandle(); // Windows cannot rename or read an open file.
    final expected = file.meta.sha256;
    if (expected != null) {
      final digest = await sha256.bind(part.openRead()).first;
      if (expected.toLowerCase() != digest.toString()) {
        await _deleteQuietly(part);
        file.partPath = null;
        throw const _HttpError(422, 'Checksum mismatch');
      }
    }
    await part.rename(file.destination!.path);
    file.done = true;
    file.partPath = null;
    _events.add(FileReceived(session.id, fileId, file.destination!.path));
  }

  void _unregisterNative(String sessionId) {
    final bridge = nativeData;
    if (bridge == null) return;
    unawaited(bridge.unregisterSession(sessionId).catchError((_) {}));
  }

  void _endSessionIfFinished(_Session session) {
    if (identical(_session, session) && session.finished) {
      _session = null;
      _unregisterNative(session.id);
      _idleTimer?.cancel();
      _events.add(SessionEnded(session.id, cancelled: false));
    }
  }

  /// Restarts the idle clock; called on every sign of life from the sender.
  void _touch() {
    _idleTimer?.cancel();
    if (_session == null) return;
    _idleTimer = Timer(sessionIdleTimeout, () {
      onNote?.call('session ended: no data for ${sessionIdleTimeout.inSeconds} s');
      _abortSession(cancelled: true);
    });
  }

  /// Which byte ranges of a file have arrived, so a sender that lost its
  /// connection can skip them.
  Future<void> _progress(HttpRequest request) async {
    final (_, file, _) = _authorize(request);
    await _json(request, 200, {
      'size': file.meta.size,
      'done': file.done,
      'ranges': file.done ? [[0, file.meta.size]] : file.received.toJson(),
    });
  }

  _Session _authorizeTar(HttpRequest request) {
    final query = request.uri.queryParameters;
    final session = _session;
    final token = query['token'];
    if (session == null ||
        query['sessionId'] != session.id ||
        token == null ||
        !_constantTimeEquals(token, session.tarToken) ||
        request.connectionInfo!.remoteAddress != session.transfer.senderAddress) {
      throw const _HttpError(403, 'Invalid token or IP address');
    }
    return session;
  }

  /// Which files of the session are already complete, so a sender that lost
  /// its connection mid-archive sends only the rest.
  Future<void> _tarStatus(HttpRequest request) async {
    final session = _authorizeTar(request);
    await _json(request, 200, {
      'done': [
        for (final e in session.files.entries)
          if (e.value.done) e.key,
      ],
    });
  }

  /// Many small files in one tar request. Entry names are file ids, never
  /// paths: each file lands at the destination this receiver chose for it, so
  /// an archive cannot write anywhere else. Files are finished one by one, so
  /// an interrupted archive keeps everything that completed.
  Future<void> _uploadTar(HttpRequest request) async {
    final session = _authorizeTar(request);
    tarUploadRequests++;
    await TarReader(request).read((header, content) async {
      final file = session.files[header.name];
      if (file == null) throw const _HttpError(400, 'Unknown file in archive');
      if (file.done) throw const _HttpError(409, 'File already received');
      if (header.size != file.meta.size) {
        throw const _HttpError(400, 'Size mismatch');
      }

      final part = await _reserve(file);
      final digestSink = _DigestCollector();
      final hasher = sha256.startChunkedConversion(digestSink);
      final sink = part.openWrite();
      var received = 0;
      try {
        while (true) {
          final piece = await content.read();
          if (piece == null) break;
          hasher.add(piece);
          sink.add(piece);
          received += piece.length;
          _touch();
          _events.add(FileProgress(session.id, header.name, received, file.meta.size));
        }
        await sink.close();
      } catch (_) {
        await sink.close().catchError((_) {});
        await _deleteQuietly(part);
        rethrow;
      }
      hasher.close();

      final expected = file.meta.sha256;
      if (received != file.meta.size ||
          (expected != null &&
              expected.toLowerCase() != digestSink.digest.toString())) {
        await _deleteQuietly(part);
        throw _HttpError(
          received != file.meta.size ? 400 : 422,
          received != file.meta.size ? 'Size mismatch' : 'Checksum mismatch',
        );
      }
      await part.rename(file.destination!.path);
      file.done = true;
      file.partPath = null;
      _events.add(FileReceived(session.id, header.name, file.destination!.path));
    });
    await _empty(request, 200);
    _endSessionIfFinished(session);
  }

  /// Reads and discards the body, for the speed test. Nothing touches disk.
  Future<void> _benchmark(HttpRequest request) async {
    final watch = Stopwatch()..start();
    var bytes = 0;
    await for (final data in request) {
      bytes += data.length;
    }
    watch.stop();
    await _json(request, 200, {'bytes': bytes, 'ms': watch.elapsedMilliseconds});
  }

  Future<void> _cancel(HttpRequest request) async {
    final session = _session;
    if (session == null || request.uri.queryParameters['sessionId'] != session.id) {
      throw const _HttpError(403, 'Invalid session');
    }
    onNote?.call('session ended: cancelled by the sender');
    await _abortSession(cancelled: true);
    await _empty(request, 200);
  }

  Future<void> _abortSession({required bool cancelled}) async {
    final session = _session;
    if (session == null) return;
    _session = null;
    _unregisterNative(session.id);
    _idleTimer?.cancel();
    for (final file in session.files.values) {
      try {
        await file.closeHandle();
      } catch (_) {}
      final part = file.partPath;
      if (part != null) await _deleteQuietly(File(part));
    }
    _events.add(SessionEnded(session.id, cancelled: cancelled));
  }

  /// Arms a one-time pairing: until the first transfer is accepted, a sender
  /// must present either [token] (carried in the QR code) or [pin] (shown under
  /// it). This replaces the permanent PIN while armed, because showing the QR
  /// code is the owner's explicit invitation.
  /// Ends the current session and removes its partial files.
  Future<void> cancelSession() => _abortSession(cancelled: true);

  void armPairing({required String token, required String pin}) {
    _pairing = (token: token, pin: pin);
  }

  void disarmPairing() => _pairing = null;

  bool get isPairingArmed => _pairing != null;

  void _checkPin(HttpRequest request, InternetAddress ip) {
    final pairing = _pairing;
    final required = pin;
    if (required == null && pairing == null) return;

    final key = ip.address;
    final now = DateTime.now();
    final failures = (_pinFailures[key] ?? [])
        .where((t) => now.difference(t) < pinLockout)
        .toList();
    _pinFailures[key] = failures;
    if (failures.length >= maxPinAttempts) {
      throw const _HttpError(429, 'Too many requests');
    }

    final supplied = request.uri.queryParameters['pin'];
    final pair = request.uri.queryParameters['pair'];
    if (supplied == null && pair == null) {
      throw const _HttpError(401, 'PIN required');
    }
    final ok = pairing != null
        ? ((pair != null && _constantTimeEquals(pair, pairing.token)) ||
              (supplied != null && _constantTimeEquals(supplied, pairing.pin)))
        : (supplied != null && _constantTimeEquals(supplied, required!));
    if (!ok) {
      failures.add(now);
      throw const _HttpError(401, 'Invalid PIN');
    }
    _pinFailures.remove(key);
  }

  /// Picks `name`, `name (1)`, `name (2)` ... inside the download folder and
  /// refuses any result that would leave it.
  Future<File> _uniqueDestination(String relative) async {
    final root = p.normalize(p.absolute(downloadDirectory.path));
    var candidate = p.normalize(p.join(root, relative));
    if (!p.isWithin(root, candidate)) throw UnsafeFileNameException(relative);

    final dir = p.dirname(candidate);
    final base = p.basenameWithoutExtension(candidate);
    final ext = p.extension(candidate);
    var n = 0;
    while (await File(candidate).exists() ||
        await File('$candidate.zajel-part').exists()) {
      n++;
      candidate = p.join(dir, '$base ($n)$ext');
    }
    return File(candidate);
  }

  String _randomToken() =>
      base64Url.encode(List.generate(18, (_) => _random.nextInt(256)));

  Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    final text = await utf8.decoder.bind(request).join();
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) throw const FormatException('not an object');
    return decoded;
  }

  Future<void> _json(
    HttpRequest request,
    int status,
    Object body, {
    Map<String, String> headers = const {},
  }) async {
    final response = request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json;
    // Headers must be set before the body is written.
    headers.forEach(response.headers.set);
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> _empty(HttpRequest request, int status, {String? message}) async {
    request.response.statusCode = status;
    if (message != null) {
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'message': message}));
    }
    await request.response.close();
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static bool _constantTimeEquals(String a, String b) {
    final x = utf8.encode(a);
    final y = utf8.encode(b);
    var diff = x.length ^ y.length;
    for (var i = 0; i < min(x.length, y.length); i++) {
      diff |= x[i] ^ y[i];
    }
    return diff == 0;
  }
}

class _HttpError implements Exception {
  const _HttpError(this.status, this.message);
  final int status;
  final String message;
}

class _DigestCollector implements Sink<Digest> {
  late Digest digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}
