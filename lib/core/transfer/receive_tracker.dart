import 'dart:async';

import 'package:mime/mime.dart';

import 'receive_server.dart';

enum ReceiveFileStatus { waiting, receiving, saving, saved, failed }

class ReceiveFile {
  const ReceiveFile({
    required this.id,
    required this.name,
    required this.size,
    required this.mimeType,
    this.received = 0,
    this.status = ReceiveFileStatus.waiting,
    this.location,
    this.published = false,
  });

  final String id;
  final String name;
  final int size;
  final String mimeType;
  final int received;
  final ReceiveFileStatus status;

  /// Where the finished file is: a content Uri when it went to a public folder,
  /// otherwise a path in the app's own folder.
  final String? location;
  final bool published;

  double get fraction => size == 0 ? 1 : (received / size).clamp(0.0, 1.0);

  ReceiveFile copyWith({
    int? received,
    ReceiveFileStatus? status,
    String? location,
    bool? published,
  }) => ReceiveFile(
    id: id,
    name: name,
    size: size,
    mimeType: mimeType,
    received: received ?? this.received,
    status: status ?? this.status,
    location: location ?? this.location,
    published: published ?? this.published,
  );
}

/// What the receiving side of a transfer looks like right now.
class ReceiveSnapshot {
  const ReceiveSnapshot({
    required this.sessionId,
    required this.senderAlias,
    required this.senderAddress,
    required this.files,
    required this.startedAt,
    this.bytesPerSecond = 0,
    this.sessionEnded = false,
    this.cancelled = false,
  });

  final String sessionId;
  final String senderAlias;
  final String senderAddress;
  final List<ReceiveFile> files;
  final DateTime startedAt;
  final double bytesPerSecond;
  final bool sessionEnded;
  final bool cancelled;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);
  int get receivedBytes => files.fold(0, (sum, f) => sum + f.received);
  double get fraction => totalBytes == 0 ? 0 : receivedBytes / totalBytes;

  /// Nothing is left to receive or to save. A cancelled session is over at once.
  bool get isOver =>
      cancelled ||
      (sessionEnded &&
          files.every(
            (f) => f.status != ReceiveFileStatus.saving && f.status != ReceiveFileStatus.receiving,
          ));

  ReceiveSnapshot copyWith({
    List<ReceiveFile>? files,
    double? bytesPerSecond,
    bool? sessionEnded,
    bool? cancelled,
  }) => ReceiveSnapshot(
    sessionId: sessionId,
    senderAlias: senderAlias,
    senderAddress: senderAddress,
    files: files ?? this.files,
    startedAt: startedAt,
    bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
    sessionEnded: sessionEnded ?? this.sessionEnded,
    cancelled: cancelled ?? this.cancelled,
  );
}

/// Turns the receiver's events into a [ReceiveSnapshot] for the receiving
/// screen, and moves each finished file to its public folder.
class ReceiveTracker {
  ReceiveTracker({required this.publish});

  /// Moves a finished file to a public folder. Returns where it ended up, or
  /// null if it stayed where it was. Called once per file.
  final Future<String?> Function(String path, String name, String mimeType) publish;

  final _controller = StreamController<ReceiveSnapshot?>.broadcast();
  ReceiveSnapshot? _current;
  final _paths = <String, String>{};
  final _samples = <(DateTime, int)>[];

  ReceiveSnapshot? get current => _current;
  Stream<ReceiveSnapshot?> get stream => _controller.stream;

  /// Forgets the finished transfer (the user left the receiving screen).
  void dismiss() {
    if (_current != null && _current!.isOver) _emit(null);
  }

  void handle(ReceiveEvent event) {
    switch (event) {
      case SessionStarted(:final transfer, :final sessionId):
        _samples.clear();
        _paths.clear();
        _emit(
          ReceiveSnapshot(
            sessionId: sessionId,
            senderAlias: transfer.sender.alias,
            senderAddress: transfer.senderAddress.address,
            startedAt: DateTime.now(),
            files: [
              for (final f in transfer.files.values)
                ReceiveFile(
                  id: f.id,
                  name: f.fileName,
                  size: f.size,
                  mimeType: lookupMimeType(f.fileName) ?? f.fileType,
                ),
            ],
          ),
        );

      case FileProgress(:final sessionId, :final fileId, :final received):
        _update(sessionId, (s) {
          final files = [
            for (final f in s.files)
              if (f.id == fileId && f.status != ReceiveFileStatus.saved && f.status != ReceiveFileStatus.saving)
                f.copyWith(received: received.clamp(0, f.size), status: ReceiveFileStatus.receiving)
              else
                f,
          ];
          final next = s.copyWith(files: files);
          return next.copyWith(bytesPerSecond: _speed(next.receivedBytes));
        });

      case FileReceived(:final sessionId, :final fileId, :final path):
        _paths['$sessionId|$fileId'] = path;
        _update(sessionId, (s) {
          final files = [
            for (final f in s.files)
              if (f.id == fileId) f.copyWith(received: f.size, status: ReceiveFileStatus.saving) else f,
          ];
          return s.copyWith(files: files);
        });
        _save(sessionId, fileId, path);

      case SessionEnded(:final sessionId, :final cancelled):
        _update(
          sessionId,
          (s) => s.copyWith(sessionEnded: true, cancelled: cancelled, bytesPerSecond: 0),
        );
    }
  }

  Future<void> _save(String sessionId, String fileId, String path) async {
    final file = _current?.files.where((f) => f.id == fileId).firstOrNull;
    if (file == null) return;
    String? location;
    var published = false;
    try {
      location = await publish(path, file.name, file.mimeType);
      published = location != null;
    } catch (_) {
      location = null;
    }
    // Stays in the app's own folder when it could not be moved.
    _update(sessionId, (s) {
      final files = [
        for (final f in s.files)
          if (f.id == fileId)
            f.copyWith(
              status: ReceiveFileStatus.saved,
              location: location ?? path,
              published: published,
            )
          else
            f,
      ];
      return s.copyWith(files: files);
    });
  }

  /// Bytes per second over roughly the last three seconds.
  double _speed(int total) {
    final now = DateTime.now();
    _samples.add((now, total));
    _samples.removeWhere((s) => now.difference(s.$1) > const Duration(seconds: 3));
    if (_samples.length < 2) return 0;
    final first = _samples.first;
    final seconds = now.difference(first.$1).inMilliseconds / 1000;
    return seconds < 0.4 ? 0 : (total - first.$2) / seconds;
  }

  void _update(String sessionId, ReceiveSnapshot Function(ReceiveSnapshot) change) {
    final current = _current;
    if (current == null || current.sessionId != sessionId) return;
    _emit(change(current));
  }

  void _emit(ReceiveSnapshot? snapshot) {
    _current = snapshot;
    if (!_controller.isClosed) _controller.add(snapshot);
  }

  Future<void> close() => _controller.close();
}
