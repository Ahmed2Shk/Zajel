import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/router/app_router.dart';
import '../../core/transfer/transfer_providers.dart';
import '../../core/transport/pairing_payload.dart';
import '../../core/transport/transport_manager.dart';
import '../../l10n/l10n.dart';

/// Builds the camera view. Calls [onCode] with the text of each QR code seen.
/// A provider, so tests can stand in for the camera.
typedef QrScannerBuilder = Widget Function(BuildContext context, ValueChanged<String> onCode);

final qrScannerBuilderProvider = Provider<QrScannerBuilder>(
  (ref) =>
      (context, onCode) => _CameraScanner(onCode: onCode),
);

/// The sending side of a QR pairing: scan, join the hotspot, send.
class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  bool _busy = false;
  DateTime _lastInvalid = DateTime.fromMillisecondsSinceEpoch(0);

  void _onCode(String raw) {
    if (_busy) return;
    final l10n = context.l10n;

    final PairingPayload payload;
    try {
      payload = PairingPayload.parse(raw);
    } on PairingFormatException {
      // The camera sees the same code many times a second: warn once in a while.
      final now = DateTime.now();
      if (now.difference(_lastInvalid) > const Duration(seconds: 3)) {
        _lastInvalid = now;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.qrInvalid)));
      }
      return;
    }

    if (ref.read(selectedFilesProvider).isEmpty) {
      _busy = true;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.pickFilesFirst)));
      context.pushReplacement(AppRoutes.filePicker);
      return;
    }

    setState(() => _busy = true);
    // Join the hotspot and send. The progress screen shows each step and any
    // failure with a message that says what to do.
    ref.read(sendJobProvider.notifier).sendVia([QrRoute(payload)]);
    context.pushReplacement(AppRoutes.transfer);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scanner = ref.watch(qrScannerBuilderProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.qrScanTitle)),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: scanner(context, _onCode)),
            // A rounded frame to aim with.
            Center(
              child: IgnorePointer(
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.primary, width: 4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 32,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _busy ? l10n.qrConnecting : l10n.qrScanHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraScanner extends StatefulWidget {
  const _CameraScanner({required this.onCode});

  final ValueChanged<String> onCode;

  @override
  State<_CameraScanner> createState() => _CameraScannerState();
}

class _CameraScannerState extends State<_CameraScanner> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return MobileScanner(
      controller: _controller,
      onDetect: (capture) {
        for (final barcode in capture.barcodes) {
          final value = barcode.rawValue;
          if (value != null) widget.onCode(value);
        }
      },
      errorBuilder: (context, error) {
        final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_photography_outlined, size: 56),
                const SizedBox(height: 16),
                Text(
                  denied ? l10n.cameraDenied : l10n.tfFailed,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // After allowing access in the system dialog or settings.
                FilledButton(
                  onPressed: () => _controller.start(),
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
