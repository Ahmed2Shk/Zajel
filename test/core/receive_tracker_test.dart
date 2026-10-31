import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/transfer/protocol_models.dart';
import 'package:zajel/core/transfer/receive_server.dart';
import 'package:zajel/core/transfer/receive_tracker.dart';

IncomingTransfer _incoming() => IncomingTransfer(
  sender: const DeviceInfo(alias: 'Sara phone', fingerprint: 'abc'),
  senderAddress: InternetAddress('192.168.1.7'),
  files: const {
    'f1': FileMetadata(id: 'f1', fileName: 'photo.jpg', size: 1000, fileType: 'image'),
    'f2': FileMetadata(id: 'f2', fileName: 'notes.txt', size: 500, fileType: 'text'),
  },
);

void main() {
  late List<(String, String, String)> published;
  late ReceiveTracker tracker;

  setUp(() {
    published = [];
    tracker = ReceiveTracker(
      publish: (path, name, mime) async {
        published.add((path, name, mime));
        return 'content://media/$name';
      },
    );
  });

  test('a new session lists every file as waiting', () {
    tracker.handle(SessionStarted('s1', _incoming()));
    final snapshot = tracker.current!;
    expect(snapshot.senderAlias, 'Sara phone');
    expect(snapshot.senderAddress, '192.168.1.7');
    expect(snapshot.files.map((f) => f.status), everyElement(ReceiveFileStatus.waiting));
    expect(snapshot.totalBytes, 1500);
    expect(snapshot.files.first.mimeType, 'image/jpeg');
  });

  test('progress moves the bar and never past the file size', () {
    tracker.handle(SessionStarted('s1', _incoming()));
    tracker.handle(const FileProgress('s1', 'f1', 400, 1000));
    expect(tracker.current!.files.first.status, ReceiveFileStatus.receiving);
    expect(tracker.current!.files.first.fraction, 0.4);
    tracker.handle(const FileProgress('s1', 'f1', 5000, 1000));
    expect(tracker.current!.files.first.received, 1000);
  });

  test('a finished file is published to the public folder and then saved', () async {
    tracker.handle(SessionStarted('s1', _incoming()));
    tracker.handle(const FileReceived('s1', 'f1', '/app/photo.jpg'));
    expect(tracker.current!.files.first.status, ReceiveFileStatus.saving);
    await Future<void>.delayed(Duration.zero);

    final file = tracker.current!.files.first;
    expect(file.status, ReceiveFileStatus.saved);
    expect(file.published, isTrue);
    expect(file.location, 'content://media/photo.jpg');
    expect(published.single, ('/app/photo.jpg', 'photo.jpg', 'image/jpeg'));
  });

  test('a file that cannot be published stays in the app folder, still saved', () async {
    final failing = ReceiveTracker(publish: (_, _, _) async => throw Exception('no space'));
    failing.handle(SessionStarted('s1', _incoming()));
    failing.handle(const FileReceived('s1', 'f1', '/app/photo.jpg'));
    await Future<void>.delayed(Duration.zero);

    final file = failing.current!.files.first;
    expect(file.status, ReceiveFileStatus.saved);
    expect(file.published, isFalse);
    expect(file.location, '/app/photo.jpg');
  });

  test('a file the platform leaves alone keeps its own path', () async {
    final unchanged = ReceiveTracker(publish: (_, _, _) async => null);
    unchanged.handle(SessionStarted('s1', _incoming()));
    unchanged.handle(const FileReceived('s1', 'f2', '/downloads/notes.txt'));
    await Future<void>.delayed(Duration.zero);
    expect(unchanged.current!.files.last.location, '/downloads/notes.txt');
    expect(unchanged.current!.files.last.published, isFalse);
  });

  test('the transfer is over only when the session ended and nothing is being saved', () async {
    tracker.handle(SessionStarted('s1', _incoming()));
    tracker.handle(const FileReceived('s1', 'f1', '/app/photo.jpg'));
    tracker.handle(const SessionEnded('s1', cancelled: false));
    expect(tracker.current!.isOver, isFalse, reason: 'still saving');
    await Future<void>.delayed(Duration.zero);
    expect(tracker.current!.isOver, isTrue);
  });

  test('a cancelled session is over at once', () {
    tracker.handle(SessionStarted('s1', _incoming()));
    tracker.handle(const FileProgress('s1', 'f1', 10, 1000));
    tracker.handle(const SessionEnded('s1', cancelled: true));
    expect(tracker.current!.isOver, isTrue);
    expect(tracker.current!.cancelled, isTrue);
    expect(tracker.current!.bytesPerSecond, 0);
  });

  test('events of an old session do not touch the current one', () {
    tracker.handle(SessionStarted('s2', _incoming()));
    tracker.handle(const FileProgress('s1', 'f1', 900, 1000));
    expect(tracker.current!.receivedBytes, 0);
  });

  test('dismiss forgets a finished transfer but not a running one', () {
    tracker.handle(SessionStarted('s1', _incoming()));
    tracker.dismiss();
    expect(tracker.current, isNotNull);
    tracker.handle(const SessionEnded('s1', cancelled: true));
    tracker.dismiss();
    expect(tracker.current, isNull);
  });
}
