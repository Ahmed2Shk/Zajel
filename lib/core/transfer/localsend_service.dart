import 'dart:async';
import 'dart:io';

import '../discovery/multicast_discovery.dart';
import '../platform/native_data_bridge.dart';
import '../platform/platform_api.g.dart';
import '../security/device_identity.dart';
import 'protocol_models.dart';
import 'receive_server.dart';
import 'send_client.dart';
import 'web_share_page.dart';
import 'web_share_server.dart';

/// An incoming transfer waiting for the user to accept or decline it.
class PendingIncoming {
  PendingIncoming(this.transfer);

  final IncomingTransfer transfer;
  final _decision = Completer<Set<String>?>();

  Future<Set<String>?> get decision => _decision.future;
  bool get isDecided => _decision.isCompleted;

  void accept([Set<String>? fileIds]) {
    if (!_decision.isCompleted) {
      _decision.complete(fileIds ?? transfer.files.keys.toSet());
    }
  }

  void decline() {
    if (!_decision.isCompleted) _decision.complete(null);
  }
}

/// Everything the app needs on the LAN: it receives (HTTPS server), announces
/// itself and hears other devices (multicast), and sends (client).
class LocalSendService {
  LocalSendService._({
    required this.device,
    required this.downloadDirectory,
    required ReceiveServer server,
    required MulticastDiscovery discovery,
    required PlatformApi? platform,
  }) : _server = server,
       _discovery = discovery,
       _platform = platform,
       client = SendClient(self: device);

  final DeviceInfo device;
  final Directory downloadDirectory;
  final SendClient client;

  final ReceiveServer _server;
  final MulticastDiscovery _discovery;
  final PlatformApi? _platform;

  /// Localized text for the ongoing-transfer notification.
  ({String title, String text}) Function() notificationText = () =>
      (title: 'Zajel', text: '');

  var _activeTransfers = 0;
  var _askedForNotifications = false;
  WebShareServer? _webShare;
  ReceiveServer? _webReceiver;
  StreamSubscription<ReceiveEvent>? _eventsSub;

  final _incoming = StreamController<PendingIncoming>.broadcast();
  final _devices = <String, DiscoveredDevice>{};
  final _devicesChanged = StreamController<List<DiscoveredDevice>>.broadcast();
  StreamSubscription<DiscoveredDevice>? _discoverySub;

  Stream<PendingIncoming> get incoming => _incoming.stream;
  Stream<ReceiveEvent> get receiveEvents => _server.events;
  Stream<List<DiscoveredDevice>> get devicesStream => _devicesChanged.stream;
  List<DiscoveredDevice> get devices => _devices.values.toList();

  static Future<LocalSendService> start({
    required DeviceIdentity identity,
    required String alias,
    required Directory downloadDirectory,
    String? deviceModel,
    DeviceType deviceType = DeviceType.mobile,
    PlatformApi? platform,
    NativeDataBridge? nativeData,
    String? pin,
    int port = localSendDefaultPort,
  }) async {
    final device = DeviceInfo(
      alias: alias,
      fingerprint: identity.fingerprint,
      deviceModel: deviceModel,
      deviceType: deviceType,
      port: port,
    );
    await downloadDirectory.create(recursive: true);

    late final LocalSendService service;
    final server = ReceiveServer(
      identity: identity,
      device: device,
      downloadDirectory: downloadDirectory,
      nativeData: nativeData,
      pin: pin,
      onIncoming: (transfer) => service._askUser(transfer),
      onDeviceRegistered: (peer, address) =>
          service._remember(DiscoveredDevice(peer, address)),
    );
    final discovery = MulticastDiscovery(self: device, port: port);
    service = LocalSendService._(
      device: device,
      downloadDirectory: downloadDirectory,
      server: server,
      discovery: discovery,
      platform: platform,
    );

    await service._begin(port);
    return service;
  }

  Future<void> _begin(int port) async {
    // Best effort: without the lock discovery may be deaf on some phones, but
    // sending and receiving by direct connection still work.
    try {
      await _platform?.setMulticastLock(true);
    } catch (_) {}
    await _server.start(port: port);
    _eventsSub = _server.events.listen((event) {
      if (event is SessionStarted) beginTransfer();
      if (event is SessionEnded) endTransfer();
    });
    _discoverySub = _discovery.devices.listen(_remember);
    await _discovery.start();
  }

  /// A transfer (sending or receiving) is starting. While at least one is
  /// active, Android keeps the app alive with the screen off.
  Future<void> beginTransfer() async {
    if (_activeTransfers++ > 0) return;
    final (:title, :text) = notificationText();
    if (!_askedForNotifications) {
      _askedForNotifications = true;
      try {
        await _platform?.requestNotificationPermission();
      } catch (_) {}
    }
    try {
      await _platform?.startTransferService(title, text);
    } catch (_) {}
  }

  Future<void> endTransfer() async {
    if (_activeTransfers == 0) return;
    if (--_activeTransfers > 0) return;
    try {
      await _platform?.stopTransferService();
    } catch (_) {}
  }

  /// CPU time used by this process so far, or null where it is not available.
  Future<int?> cpuTimeMs() async {
    try {
      return await _platform?.getProcessCpuTimeMs();
    } catch (_) {
      return null;
    }
  }

  /// Starts the browser share (plain HTTP, token in the link). Uploads from the
  /// browser go through the same accept dialog as any other incoming transfer.
  Future<WebShareStatus> startWebShare({
    required List<SendFile> files,
    required WebPageStrings strings,
    required bool rtl,
  }) async {
    await stopWebShare();
    final receiver = ReceiveServer(
      identity: _server.identity,
      device: device,
      downloadDirectory: downloadDirectory,
      pin: _server.pin,
      enableChunking: false, // a browser speaks stock LocalSend only
      onIncoming: _askUser,
    );
    final share = WebShareServer(
      device: device,
      receiver: receiver,
      strings: strings,
      rtl: rtl,
      files: files,
    );
    await share.start();
    _webShare = share;
    _webReceiver = receiver;
    // The browser may download for a long time; keep the phone awake.
    await beginTransfer();
    final addresses = await lanAddresses();
    return WebShareStatus(
      url: addresses.isEmpty ? null : share.linkFor(addresses.first),
      fileCount: files.length,
    );
  }

  Future<void> stopWebShare() async {
    final share = _webShare;
    if (share == null) return;
    _webShare = null;
    await share.stop();
    await _webReceiver?.stop();
    _webReceiver = null;
    await endTransfer();
  }

  bool get isWebSharing => _webShare != null;

  /// Announces again, for the "search again" action.
  void rescan() => _discovery.announce();

  Future<void> stop() async {
    await stopWebShare();
    await _eventsSub?.cancel();
    await _discoverySub?.cancel();
    await _discovery.stop();
    await _server.stop();
    if (_activeTransfers > 0) {
      _activeTransfers = 0;
      try {
        await _platform?.stopTransferService();
      } catch (_) {}
    }
    try {
      await _platform?.setMulticastLock(false);
    } catch (_) {}
  }

  Future<Set<String>?> _askUser(IncomingTransfer transfer) {
    final pending = PendingIncoming(transfer);
    _incoming.add(pending);
    // Nobody listening, or the user ignores it: do not hold the sender forever.
    return pending.decision.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        pending.decline();
        return null;
      },
    );
  }

  void _remember(DiscoveredDevice found) {
    _devices[found.info.fingerprint] = found;
    _devicesChanged.add(devices);
  }
}

/// A running browser share: the link to open and how many files are offered.
class WebShareStatus {
  const WebShareStatus({required this.url, required this.fileCount});

  /// Null when the device has no network address to put in a link.
  final Uri? url;
  final int fileCount;
}
