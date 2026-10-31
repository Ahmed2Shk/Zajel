import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/home_screen.dart';
import '../../features/qr/qr_scan_screen.dart';
import '../../features/receive/receive_screen.dart';
import '../../features/qr/qr_show_screen.dart';
import '../../features/send/discovery_screen.dart';
import '../../features/send/done_screen.dart';
import '../../features/send/file_picker_screen.dart';
import '../../features/send/transfer_progress_screen.dart';
import '../../features/send/web_share_screen.dart';
import '../../features/settings/benchmark_screen.dart';
import '../../features/settings/settings_screen.dart';

abstract final class AppRoutes {
  static const home = '/';
  static const filePicker = '/file-picker';
  static const discovery = '/discovery';
  static const qrShow = '/qr/show';
  static const qrScan = '/qr/scan';
  static const transfer = '/transfer';
  static const done = '/done';
  static const settings = '/settings';
  static const benchmark = '/benchmark';
  static const webShare = '/web-share';
  static const receive = '/receive';
}

/// Lets code outside the widget tree (incoming-transfer dialogs) reach the
/// navigator.
final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    routes: [
      GoRoute(path: AppRoutes.home, builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: AppRoutes.filePicker,
        builder: (_, _) => const FilePickerScreen(),
      ),
      GoRoute(
        path: AppRoutes.discovery,
        builder: (_, _) => const DiscoveryScreen(),
      ),
      GoRoute(path: AppRoutes.qrShow, builder: (_, _) => const QrShowScreen()),
      GoRoute(path: AppRoutes.qrScan, builder: (_, _) => const QrScanScreen()),
      GoRoute(
        path: AppRoutes.transfer,
        builder: (_, _) => const TransferProgressScreen(),
      ),
      GoRoute(path: AppRoutes.done, builder: (_, _) => const DoneScreen()),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.webShare,
        builder: (_, _) => const WebShareScreen(),
      ),
      GoRoute(
        path: AppRoutes.receive,
        builder: (_, _) => const ReceiveScreen(),
      ),
      GoRoute(
        path: AppRoutes.benchmark,
        builder: (_, _) => const BenchmarkScreen(),
      ),
    ],
  );
});
