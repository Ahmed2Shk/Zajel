import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/transfer/receive_server.dart';
import '../../core/transfer/transfer_providers.dart';
import '../settings/app_settings.dart';

enum TransferDirection { sent, received }

/// One finished file transfer, kept for the "recent transfers" list.
class HistoryEntry {
  const HistoryEntry({
    required this.name,
    required this.size,
    required this.peer,
    required this.direction,
    required this.at,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    name: json['name'] as String,
    size: (json['size'] as num).toInt(),
    peer: json['peer'] as String? ?? '',
    direction: json['direction'] == 'received'
        ? TransferDirection.received
        : TransferDirection.sent,
    at: DateTime.fromMillisecondsSinceEpoch((json['at'] as num).toInt()),
  );

  final String name;
  final int size;
  final String peer;
  final TransferDirection direction;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'name': name,
    'size': size,
    'peer': peer,
    'direction': direction.name,
    'at': at.millisecondsSinceEpoch,
  };
}

/// Newest first, kept on the device only. Nothing is sent anywhere.
class HistoryNotifier extends Notifier<List<HistoryEntry>> {
  static const _key = 'history';
  static const maxEntries = 50;

  @override
  List<HistoryEntry> build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(_key);
    if (raw == null) return const [];
    try {
      return [
        for (final item in jsonDecode(raw) as List)
          HistoryEntry.fromJson(item as Map<String, dynamic>),
      ];
    } catch (_) {
      return const []; // A damaged list is not worth crashing for.
    }
  }

  void add(Iterable<HistoryEntry> entries) {
    final next = [...entries.toList().reversed, ...state];
    state = next.length > maxEntries ? next.sublist(0, maxEntries) : next;
    ref
        .read(sharedPreferencesProvider)
        .setString(_key, jsonEncode([for (final e in state) e.toJson()]));
  }

  void clear() {
    state = const [];
    ref.read(sharedPreferencesProvider).remove(_key);
  }
}

final historyProvider = NotifierProvider<HistoryNotifier, List<HistoryEntry>>(
  HistoryNotifier.new,
);

/// Records every file the receiver finishes. Watched once, near the app root.
final historyRecorderProvider = Provider<void>((ref) {
  StreamSubscription<ReceiveEvent>? subscription;
  final names = <String, ({String name, int size, String peer})>{};

  ref.listen(localSendServiceProvider, (_, next) {
    subscription?.cancel();
    final service = next.value;
    if (service == null) return;
    subscription = service.receiveEvents.listen((event) {
      if (event is SessionStarted) {
        names.clear();
        for (final file in event.transfer.files.values) {
          names['${event.sessionId}|${file.id}'] = (
            name: file.fileName,
            size: file.size,
            peer: event.transfer.sender.alias,
          );
        }
      } else if (event is FileReceived) {
        final info = names['${event.sessionId}|${event.fileId}'];
        if (info == null) return;
        ref.read(historyProvider.notifier).add([
          HistoryEntry(
            name: info.name,
            size: info.size,
            peer: info.peer,
            direction: TransferDirection.received,
            at: DateTime.now(),
          ),
        ]);
      }
    });
  }, fireImmediately: true);
  ref.onDispose(() => subscription?.cancel());
});
