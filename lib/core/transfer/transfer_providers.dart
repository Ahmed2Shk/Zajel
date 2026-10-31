import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/settings/app_settings.dart';
import '../../l10n/app_localizations.dart';
import '../discovery/multicast_discovery.dart';
import '../logging/log_providers.dart';
import '../platform/native_data_bridge.dart';
import '../platform/platform_api.g.dart';
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
  @override
  List<SendFile> build() => const [];

  void set(List<SendFile> files) => state = files;

  void clear() => state = const [];
}

final selectedFilesProvider =
    NotifierProvider<SelectedFilesNotifier, List<SendFile>>(
      SelectedFilesNotifier.new,
    );

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

  SendSession? _session;
  var _cancelled = false;
  List<PeerRoute> _lastRoutes = const [];

  /// The QR code this send was started from, so a failed join can be retried
  /// after the user joins the hotspot by hand.
  PairingPayload? get lastQrPayload =>
      _lastRoutes.whereType<QrRoute>().firstOrNull?.payload;

  @override
  SendJob build() => const SendJob();

  Future<void> send(
    DiscoveredDevice target, {
    String? pin,
    String? pairToken,
    PeerEndpoint? endpoint,
  }) async {
    final service = await ref.read(localSendServiceProvider.future);
    final files = ref.read(selectedFilesProvider);
    if (service == null || files.isEmpty) return;

    _cancelled = false;
    state = SendJob(
      status: SendStatus.connecting,
      target: target,
      files: files,
    );

    await service.beginTransfer();
    try {
      final session = await service.client.prepareUpload(
        address: target.address,
        port: target.info.port,
        files: files,
        expectedFingerprint: target.info.fingerprint,
        pin: pin,
        pairToken: pairToken,
      );
      _session = session;
      state = state.copyWith(status: SendStatus.sending);

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
            isCancelled: () => _cancelled,
            onProgress: (id, bytes) {
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
          if (_cancelled ||
              attempt++ >= maxResumeAttempts ||
              !SendClient.isTransientError(e)) {
            rethrow;
          }
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
      if (_cancelled) return;
      state = state.copyWith(
        status: SendStatus.done,
        sentPerFile: {for (final f in files) f.id: f.size},
      );
    } on SendException catch (e) {
      if (_cancelled) return;
      ref.read(appLogProvider)?.error('send', e);
      state = state.copyWith(
        status: e.pinRequired ? SendStatus.needsPin : SendStatus.failed,
        error: e.declined ? 'declined' : e.message,
      );
    } on SocketException catch (e, stack) {
      // Connection refused or timed out: the device is gone or unreachable.
      if (_cancelled) return;
      ref.read(appLogProvider)?.error('send', e, stack);
      state = state.copyWith(status: SendStatus.failed, error: 'unreachable');
    } on HandshakeException catch (e, stack) {
      // The device answered with a different identity than the one chosen.
      if (_cancelled) return;
      ref.read(appLogProvider)?.error('send', e, stack);
      state = state.copyWith(status: SendStatus.failed, error: 'unreachable');
    } catch (e, stack) {
      if (_cancelled) return;
      ref.read(appLogProvider)?.error('send', e, stack);
      state = state.copyWith(status: SendStatus.failed, error: e.toString());
    } finally {
      await service.endTransfer();
      // Leave the hotspot or Wi-Fi Direct group the transfer used.
      if (endpoint != null) {
        await ref.read(transportManagerProvider)?.release(endpoint);
      }
    }
  }

  /// Sends to a peer that may be reachable several ways. The routes are tried
  /// fastest first (Wi-Fi Direct, then a QR hotspot, then the shared Wi-Fi),
  /// and the first one that connects carries the transfer.
  Future<void> sendVia(List<PeerRoute> routes) async {
    if (routes.isEmpty) return;
    final files = ref.read(selectedFilesProvider);
    if (files.isEmpty) return;
    final manager = ref.read(transportManagerProvider);

    _cancelled = false;
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

    final PeerEndpoint endpoint;
    try {
      // Without a manager (not Android) only the shared Wi-Fi is possible.
      final usable = manager == null
          ? routes.whereType<LanRoute>().toList()
          : routes;
      endpoint = await (manager ?? TransportManager(NoTransportBackend())).establish(usable);
    } on AllTransportsFailed catch (e) {
      ref.read(appLogProvider)?.warn('transport', e.toString());
      state = state.copyWith(
        status: SendStatus.failed,
        error: 'transport:${e.failures.isEmpty ? TransportFailure.failed.name : e.failures.last.reason.name}',
      );
      return;
    }
    if (_cancelled) {
      await manager?.release(endpoint);
      return;
    }

    await send(
      DiscoveredDevice(
        DeviceInfo(
          alias: endpoint.alias,
          fingerprint: endpoint.fingerprint,
          port: endpoint.port,
        ),
        endpoint.address,
      ),
      pin: endpoint.pin,
      pairToken: endpoint.pairToken,
      endpoint: endpoint,
    );
  }

  Future<void> cancel() async {
    _cancelled = true;
    final session = _session;
    final service = ref.read(localSendServiceProvider).value;
    if (session != null && service != null) {
      try {
        await service.client.cancel(session);
      } catch (_) {}
    }
    state = const SendJob();
  }

  void reset() {
    _session = null;
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
  return TransportManager(PigeonTransportBackend());
});

/// What is being received right now (or was just received), or null.
final receiveSnapshotProvider = StreamProvider<ReceiveSnapshot?>((ref) async* {
  final service = await ref.watch(localSendServiceProvider.future);
  if (service == null) {
    yield null;
    return;
  }
  yield service.receive.current;
  yield* service.receive.stream;
});
