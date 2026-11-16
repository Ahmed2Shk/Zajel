import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/settings/app_settings.dart';
import '../../l10n/app_localizations.dart';
import '../discovery/multicast_discovery.dart';
import '../logging/log_providers.dart';
import '../platform/native_data_bridge.dart';
import '../platform/platform_api.g.dart';
import '../platform/platform_providers.dart';
import '../security/device_identity.dart';
import '../transport/pairing_payload.dart';
import '../transport/transport_manager.dart';
import 'localsend_service.dart';
import 'protocol_models.dart';
import 'receive_tracker.dart';
import 'send_client.dart';
import 'web_share_page.dart';

/// The running LocalSend service, or null on platforms without dart:io sockets
/// (the browser build).
final localSendServiceProvider = FutureProvider<LocalSendService?>((ref) async {
  if (kIsWeb) return null;

  // Changing any of these restarts the service with the new values.
  final (:deviceName, :downloadPath, :receivePin) = ref.watch(
    appSettingsProvider.select(
      (s) => (
        deviceName: s.deviceName,
        downloadPath: s.downloadPath,
        receivePin: s.receivePin,
      ),
    ),
  );

  final support = await getApplicationSupportDirectory();
  final identity = await DeviceIdentity.loadOrCreate(support);
  final platform = Platform.isAndroid ? PlatformApi() : null;

  String? model;
  if (platform != null) {
    try {
      model = (await platform.getDeviceInfo()).model;
    } catch (_) {}
  }

  final service = await LocalSendService.start(
    identity: identity,
    alias: deviceName ?? defaultDeviceName(identity),
    pin: receivePin,
    log: ref.read(appLogProvider),
    deviceModel: model,
    deviceType: Platform.isAndroid || Platform.isIOS
        ? DeviceType.mobile
        : DeviceType.desktop,
    downloadDirectory: downloadPath != null
        ? Directory(downloadPath)
        : await defaultDownloadDirectory(),
    platform: platform,
    nativeData: Platform.isAndroid ? PigeonNativeDataBridge() : null,
  );
  service.notificationText = () {
    final l10n = lookupAppLocalizations(ref.read(appSettingsProvider).locale);
    return (title: l10n.appName, text: l10n.transferNotification);
  };
  ref.onDispose(service.stop);
  return service;
});

String defaultDeviceName(DeviceIdentity identity) =>
    'Zajel-${identity.fingerprint.substring(0, 4)}';

/// Files land in a "Zajel" folder. On Android this is the app's own external
/// folder, which needs no storage permission; a public Downloads location
/// arrives with the Android release phase.
Future<Directory> defaultDownloadDirectory() async {
  final base =
      await getDownloadsDirectory() ??
      await getExternalStorageDirectory() ??
      await getApplicationDocumentsDirectory();
  return Directory('${base.path}/Zajel');
}

/// Devices heard on the network, newest state of the list.
final nearbyDevicesProvider = StreamProvider<List<DiscoveredDevice>>((
  ref,
) async* {
  final service = await ref.watch(localSendServiceProvider.future);
  if (service == null) {
    yield const [];
    return;
  }
  yield service.devices;
  yield* service.devicesStream;
});

/// Incoming requests that need an accept/decline answer.
final incomingTransferProvider = StreamProvider<PendingIncoming>((ref) async* {
  final service = await ref.watch(localSendServiceProvider.future);
  if (service != null) yield* service.incoming;
});

class SelectedFilesNotifier extends Notifier<List<SendFile>> {
  static const _prefsKey = 'pendingSelection';

  /// A saved selection older than this is not brought back: it is there to
  /// survive Android closing the app while the system picker is open, not to
  /// greet the user with last week's files.
  static const restoreWithin = Duration(minutes: 10);

  SharedPreferences? _prefs;

  @override
  List<SendFile> build() {
    try {
      _prefs = ref.read(sharedPreferencesProvider);
    } catch (_) {
      _prefs = null; // no storage here (some tests): the selection is memory only
    }
    // After build: the state cannot be read while it is being created.
    unawaited(Future.microtask(_restore));
    return const [];
  }

  @override
  set state(List<SendFile> files) {
    super.state = files;
    _save(files);
  }

  void _save(List<SendFile> files) {
    final prefs = _prefs;
    if (prefs == null) return;
    if (files.isEmpty) {
      unawaited(prefs.remove(_prefsKey));
      return;
    }
    unawaited(
      prefs.setString(
        _prefsKey,
        jsonEncode({
          'at': DateTime.now().millisecondsSinceEpoch,
          'files': [
            for (final f in files) {'id': f.id, 'path': f.file.path, 'name': f.name},
          ],
        }),
      ),
    );
  }

  /// Brings back a selection saved a moment ago, leaving out files that are
  /// gone. With nothing to bring back, the copies the system picker left in
  /// the cache are removed: nothing refers to them any more.
  Future<void> _restore() async {
    if (!ref.mounted) return;
    final restored = <SendFile>[];
    try {
      final raw = _prefs?.getString(_prefsKey);
      if (raw != null) {
        final saved = jsonDecode(raw) as Map<String, dynamic>;
        final at = DateTime.fromMillisecondsSinceEpoch((saved['at'] as num).toInt());
        if (DateTime.now().difference(at) <= restoreWithin) {
          for (final item in saved['files'] as List<dynamic>) {
            final entry = item as Map<String, dynamic>;
            final path = entry['path'] as String;
            if (!await File(path).exists()) continue;
            restored.add(
              await SendFile.fromPath(path, id: entry['id'] as String, name: entry['name'] as String?),
            );
          }
        }
      }
    } catch (_) {
      restored.clear(); // unreadable: start empty
    }
    if (!ref.mounted) return;
    if (restored.isNotEmpty && state.isEmpty) {
      state = restored;
    } else if (state.isEmpty) {
      unawaited(_prefs?.remove(_prefsKey));
      unawaited(_clearPickerCache());
    }
  }

  /// The system picker copies every picked file into the app's cache and never
  /// removes it. Called when no selection refers to those copies.
  static Future<void> _clearPickerCache() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (_) {
      // Best effort.
    }
  }

  void set(List<SendFile> files) => state = files;

  /// Adds the files that are not selected yet. A file counts as selected when
  /// its id or its path is already there, so a double tap or a late answer
  /// from a slow lookup never adds it twice. Works on the list as it is now,
  /// not on a copy read before an await.
  void addAll(Iterable<SendFile> files) {
    final ids = {for (final f in state) f.id};
    final paths = {for (final f in state) f.file.path};
    final next = [...state];
    for (final file in files) {
      if (ids.contains(file.id) || paths.contains(file.file.path)) continue;
      ids.add(file.id);
      paths.add(file.file.path);
      next.add(file);
    }
    if (next.length != state.length) state = next;
  }

  void add(SendFile file) => addAll([file]);

  void removeWhere(bool Function(SendFile file) test) {
    final next = [
      for (final f in state)
        if (!test(f)) f,
    ];
    if (next.length != state.length) state = next;
  }

  void remove(String id) => removeWhere((f) => f.id == id);

  /// Empties the selection (after a send, or by the user) and removes the
  /// picker's copies of the files, which are no longer needed.
  void clear() {
    state = const [];
    unawaited(_clearPickerCache());
  }
}

final selectedFilesProvider =
    NotifierProvider<SelectedFilesNotifier, List<SendFile>>(
      SelectedFilesNotifier.new,
    );

/// A QR code that was scanned before any file was chosen. The picker's Send
/// button then continues with it, instead of sending the user to the radar to
/// find the same device again. A code is only good while the receiver's QR
/// screen is open, so it is forgotten after a few minutes.
class PendingQrNotifier extends Notifier<PairingPayload?> {
  static const keepFor = Duration(minutes: 5);
  DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  PairingPayload? build() => null;

  void remember(PairingPayload payload) {
    _at = DateTime.now();
    state = payload;
  }

  /// The remembered code if it is still fresh, forgetting it either way.
  PairingPayload? take() {
    final payload = state;
    state = null;
    if (payload == null || DateTime.now().difference(_at) > keepFor) return null;
    return payload;
  }
}

final pendingQrProvider = NotifierProvider<PendingQrNotifier, PairingPayload?>(PendingQrNotifier.new);

enum SendStatus { idle, connecting, needsPin, sending, done, failed }

class SendJob {
  const SendJob({
    this.status = SendStatus.idle,
    this.target,
    this.files = const [],
    this.sentPerFile = const {},
    this.bytesPerSecond = 0,
    this.error,
  });

  final SendStatus status;
  final DiscoveredDevice? target;
  final List<SendFile> files;
  final Map<String, int> sentPerFile;
  final double bytesPerSecond;
  final String? error;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);
  int get sentBytes => sentPerFile.values.fold(0, (sum, n) => sum + n);
  double get fraction => totalBytes == 0 ? 0 : sentBytes / totalBytes;

  SendJob copyWith({
    SendStatus? status,
    Map<String, int>? sentPerFile,
    double? bytesPerSecond,
    String? error,
  }) => SendJob(
    status: status ?? this.status,
    target: target,
    files: files,
    sentPerFile: sentPerFile ?? this.sentPerFile,
    bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
    error: error,
  );
}

class SendJobNotifier extends Notifier<SendJob> {
  /// How many times a dropped connection is retried before the send fails.
  static const maxResumeAttempts = 5;

  /// The send that owns [state] right now. Every send gets its own token; a
  /// send that was cancelled (or is otherwise no longer this one) must not
  /// touch the state, the session or the network of the send that replaced it.
  Object? _run;
  SendSession? _session;
  PeerEndpoint? _endpoint;
  List<PeerRoute> _lastRoutes = const [];

  /// The routes the user asked for, before any automatic upgrade, so a failed
  /// send can be tried again exactly as it was started.
  List<PeerRoute> _requestedRoutes = const [];

  /// A failed send can be started again with the same files and device.
  bool get canRetry => state.status == SendStatus.failed && _requestedRoutes.isNotEmpty;

  /// Starts the failed send again. The selection is untouched.
  Future<void> retry() => sendVia(_requestedRoutes);

  /// The QR code this send was started from, so a failed join can be retried
  /// after the user joins the hotspot by hand.
  PairingPayload? get lastQrPayload =>
      _lastRoutes.whereType<QrRoute>().firstOrNull?.payload;

  /// A send is connecting or sending. A second one is not started meanwhile.
  bool get isBusy =>
      _run != null &&
      (state.status == SendStatus.connecting || state.status == SendStatus.sending);

  @override
  SendJob build() => const SendJob();

  /// Sends the selected files to [target]. Does nothing while another send is
  /// running.
  Future<void> send(
    DiscoveredDevice target, {
    String? pin,
    String? pairToken,
    PeerEndpoint? endpoint,
  }) async {
    if (isBusy) return;
    final files = ref.read(selectedFilesProvider);
    if (files.isEmpty) return;
    final run = _run = Object();
    _endpoint = endpoint;
    await _transfer(run, target, files, pin: pin, pairToken: pairToken, endpoint: endpoint);
  }

  Future<void> _transfer(
    Object run,
    DiscoveredDevice target,
    List<SendFile> files, {
    String? pin,
    String? pairToken,
    PeerEndpoint? endpoint,
  }) async {
    bool live() => identical(_run, run);

    state = SendJob(
      status: SendStatus.connecting,
      target: target,
      files: files,
    );

    LocalSendService? service;
    try {
      try {
        service = await ref.read(localSendServiceProvider.future);
      } catch (e, stack) {
        ref.read(appLogProvider)?.error('service', e, stack);
      }
      if (service == null) {
        // The transfer service did not start: say so instead of waiting forever.
        if (live()) state = state.copyWith(status: SendStatus.failed, error: 'service');
        return;
      }
      await service.beginTransfer();
      final session = await service.client.prepareUpload(
        address: target.address,
        port: target.info.port,
        files: files,
        expectedFingerprint: target.info.fingerprint,
        pin: pin,
        pairToken: pairToken,
      );
      if (!live()) {
        // Cancelled while the receiver was deciding: free its session.
        try {
          await service.client.cancel(session);
        } catch (_) {}
        return;
      }
      _session = session;
      state = state.copyWith(status: SendStatus.sending);
      unawaited(_logLink(endpoint));

      final stopwatch = Stopwatch()..start();
      final sent = <String, int>{};
      var lastUiUpdate = 0;
      // A dropped Wi-Fi link is retried on the same session. Chunked files then
      // resume from what the receiver already holds.
      var attempt = 0;
      while (true) {
        try {
          await service.client.upload(
            session: session,
            files: files,
            isCancelled: () => !live(),
            onProgress: (id, bytes) {
              if (!live()) return;
              sent[id] = bytes;
              final ms = stopwatch.elapsedMilliseconds;
              // Throttle UI rebuilds to ~10 per second.
              if (ms - lastUiUpdate < 100) return;
              lastUiUpdate = ms;
              final total = sent.values.fold(0, (a, b) => a + b);
              state = state.copyWith(
                sentPerFile: Map.of(sent),
                bytesPerSecond: ms == 0 ? 0 : total / (ms / 1000),
              );
            },
          );
          break;
        } catch (e) {
          if (!live() ||
              attempt++ >= maxResumeAttempts ||
              !SendClient.isTransientError(e)) {
            rethrow;
          }
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
      if (!live()) return;
      final seconds = stopwatch.elapsedMilliseconds / 1000;
      final bytes = files.fold(0, (sum, f) => sum + f.size);
      ref.read(appLogProvider)?.info(
        'send',
        'finished: $bytes bytes in ${seconds.toStringAsFixed(1)} s, '
            '${seconds == 0 ? '-' : (bytes / (1024 * 1024) / seconds).toStringAsFixed(1)} MB/s',
      );
      state = state.copyWith(
        status: SendStatus.done,
        sentPerFile: {for (final f in files) f.id: f.size},
      );
    } on SendException catch (e) {
      if (!live()) return;
      ref.read(appLogProvider)?.error('send', e);
      state = state.copyWith(
        status: e.pinRequired ? SendStatus.needsPin : SendStatus.failed,
        error: e.declined
            ? 'declined'
            : e.busy
            ? 'busy'
            : e.message,
      );
    } on SocketException catch (e, stack) {
      // Connection refused or timed out: the device is gone or unreachable.
      if (!live()) return;
      ref.read(appLogProvider)?.error('send', e, stack);
      state = state.copyWith(status: SendStatus.failed, error: 'unreachable');
    } on HandshakeException catch (e, stack) {
      // The device answered with a different identity than the one chosen.
      if (!live()) return;
      ref.read(appLogProvider)?.error('send', e, stack);
      state = state.copyWith(status: SendStatus.failed, error: 'unreachable');
    } catch (e, stack) {
      if (!live()) return;
      ref.read(appLogProvider)?.error('send', e, stack);
      state = state.copyWith(status: SendStatus.failed, error: e.toString());
    } finally {
      await service?.endTransfer();
      // Leave the hotspot or Wi-Fi Direct group the transfer used. A cancelled
      // send has already left it in cancel(); doing it again here could cut
      // off the send that started since.
      if (live()) {
        _session = null;
        _endpoint = null;
        if (endpoint != null) {
          await ref.read(transportManagerProvider)?.release(endpoint);
        }
      }
    }
  }

  /// Notes in the log which route this send uses and what this phone's Wi-Fi
  /// link looks like (band, link speed, signal). When one transfer is fast and
  /// the next is slow, this tells a 2.4 GHz hotspot or a weak signal from a
  /// problem in the app.
  Future<void> _logLink(PeerEndpoint? endpoint) async {
    final log = ref.read(appLogProvider);
    if (log == null) return;
    final route = (endpoint?.via ?? TransportKind.sameLan).name;
    try {
      final wifi = await ref.read(platformApiProvider).getWifiInfo();
      log.info(
        'send',
        wifi == null
            ? 'route $route, no Wi-Fi details'
            : 'route $route, Wi-Fi ${wifi.frequencyMhz} MHz, link ${wifi.linkSpeedMbps} Mbps, '
                  'signal ${wifi.rssiDbm} dBm',
      );
    } catch (_) {
      log.info('send', 'route $route');
    }
  }

  /// Sends to a peer that may be reachable several ways. The routes are tried
  /// fastest first (Wi-Fi Direct, then a QR hotspot, then the shared Wi-Fi),
  /// and the first one that connects carries the transfer. Does nothing while
  /// another send is running.
  Future<void> sendVia(List<PeerRoute> routes) async {
    if (routes.isEmpty || isBusy) return;
    final files = ref.read(selectedFilesProvider);
    if (files.isEmpty) return;
    final manager = ref.read(transportManagerProvider);

    final run = _run = Object();
    bool live() => identical(_run, run);
    _endpoint = null;
    _requestedRoutes = routes;
    _lastRoutes = routes;
    final first = routes.first;
    state = SendJob(
      status: SendStatus.connecting,
      target: DiscoveredDevice(
        DeviceInfo(alias: first.alias, fingerprint: first.fingerprint),
        InternetAddress.loopbackIPv4,
      ),
      files: files,
    );

    // A receiver that is waiting with its hotspot up hands over the way in:
    // the transfer then runs phone to phone instead of through the router.
    PairingPayload? offered;
    final service = ref.read(localSendServiceProvider).value;
    if (manager != null && service != null) {
      routes = await withDirectUpgrade(
        routes,
        (device) => service.client.requestDirectCode(
          address: device.address,
          port: device.info.port,
          expectedFingerprint: device.info.fingerprint,
        ),
      );
      if (!live()) return;
      offered = routes.first is QrRoute && routes.length > 1 ? (routes.first as QrRoute).payload : null;
      if (offered != null) {
        ref.read(appLogProvider)?.info('transport', 'the receiver offers its hotspot: switching to it');
      }
      _lastRoutes = routes;
    }

    final PeerEndpoint endpoint;
    try {
      // Without a manager (not Android) only the shared Wi-Fi is possible.
      final usable = manager == null
          ? routes.whereType<LanRoute>().toList()
          : routes;
      endpoint = await (manager ?? TransportManager(NoTransportBackend())).establish(usable);
    } on AllTransportsFailed catch (e) {
      if (!live()) return;
      ref.read(appLogProvider)?.warn('transport', e.toString());
      state = state.copyWith(
        status: SendStatus.failed,
        error: 'transport:${e.failures.isEmpty ? TransportFailure.failed.name : e.failures.last.reason.name}',
      );
      return;
    }
    if (!live()) {
      // Cancelled while joining: leave what was joined, unless a newer send
      // is already using the network.
      if (_run == null) await manager?.release(endpoint);
      return;
    }
    _endpoint = endpoint;
    if (offered != null && endpoint.via == TransportKind.sameLan) {
      ref.read(appLogProvider)?.warn('transport', 'could not join the hotspot: staying on the Wi-Fi');
    }

    await _transfer(
      run,
      DiscoveredDevice(
        DeviceInfo(
          alias: endpoint.alias,
          fingerprint: endpoint.fingerprint,
          port: endpoint.port,
        ),
        endpoint.address,
      ),
      files,
      pin: endpoint.pin,
      // The receiver is in pairing mode: over the Wi-Fi it wants the same
      // token as over its hotspot.
      pairToken: endpoint.pairToken ?? offered?.token,
      endpoint: endpoint,
    );
  }

  /// Stops the running send: tells the receiver, leaves the network the send
  /// had joined, and clears the job. The stopped send can no longer change
  /// anything, so a new one may start at once.
  Future<void> cancel() async {
    final session = _session;
    final endpoint = _endpoint;
    _run = null;
    _session = null;
    _endpoint = null;
    state = const SendJob();

    final service = ref.read(localSendServiceProvider).value;
    if (session != null && service != null) {
      try {
        await service.client.cancel(session);
      } catch (_) {}
    }
    if (endpoint != null) {
      try {
        await ref.read(transportManagerProvider)?.release(endpoint);
      } catch (_) {}
    }
  }

  void reset() {
    _run = null;
    _session = null;
    _endpoint = null;
    state = const SendJob();
  }
}

final sendJobProvider = NotifierProvider<SendJobNotifier, SendJob>(
  SendJobNotifier.new,
);

/// The browser share, or null while it is off.
class WebShareNotifier extends Notifier<WebShareStatus?> {
  @override
  WebShareStatus? build() => null;

  Future<void> start() async {
    final service = await ref.read(localSendServiceProvider.future);
    if (service == null) return;
    final settings = ref.read(appSettingsProvider);
    final l10n = lookupAppLocalizations(settings.locale);
    final status = await service.startWebShare(
      files: ref.read(selectedFilesProvider),
      rtl: settings.locale.languageCode == 'ar',
      strings: WebPageStrings(
        title: l10n.webPageTitle,
        warning: l10n.webPageWarning,
        downloads: l10n.webPageDownloads,
        uploads: l10n.webPageUploads,
        choose: l10n.webPageChoose,
        send: l10n.webPageSend,
        waiting: l10n.webPageWaiting,
        done: l10n.webPageDone,
        declined: l10n.webPageDeclined,
        busy: l10n.webPageBusy,
        failed: l10n.webPageFailed,
        pin: l10n.webPagePin,
        noFiles: l10n.webPageNoFiles,
      ),
    );
    state = status;
  }

  Future<void> stop() async {
    final service = ref.read(localSendServiceProvider).value;
    await service?.stopWebShare();
    state = null;
  }
}

final webShareProvider = NotifierProvider<WebShareNotifier, WebShareStatus?>(
  WebShareNotifier.new,
);

/// Router-free transports (QR hotspot and Wi-Fi Direct). Null away from Android.
final transportManagerProvider = Provider<TransportManager?>((ref) {
  if (kIsWeb || !Platform.isAndroid) return null;
  final log = ref.read(appLogProvider);
  return TransportManager(
    PigeonTransportBackend(),
    onNote: log == null ? null : (note) => log.info('wifi', note),
  );
});

/// What is being received right now (or was just received), or null.
final receiveSnapshotProvider = StreamProvider<ReceiveSnapshot?>((ref) async* {
  final service = await ref.watch(localSendServiceProvider.future);
  if (service == null) {
    yield null;
    return;
  }
  // Subscribe first, then add the current value: an event that arrives in
  // between is not lost (the tracker's stream is a broadcast stream).
  final controller = StreamController<ReceiveSnapshot?>();
  final subscription = service.receive.stream.listen(controller.add);
  ref.onDispose(() {
    subscription.cancel();
    controller.close();
  });
  controller.add(service.receive.current);
  yield* controller.stream;
});
