import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/widgets/zajel_widgets.dart';
import '../../l10n/l10n.dart';
import 'qr_host.dart';
import 'transport_messages.dart';

/// The receiving side of a QR pairing: a hotspot, its QR code and a short PIN.
class QrShowScreen extends ConsumerStatefulWidget {
  const QrShowScreen({super.key});

  @override
  ConsumerState<QrShowScreen> createState() => _QrShowScreenState();
}

class _QrShowScreenState extends ConsumerState<QrShowScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(qrHostProvider.notifier).start());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = ref.watch(qrHostProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.qrShowTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            switch (state) {
              QrHostStarting() => Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(l10n.qrStarting),
                  ],
                ),
              ),
              QrHostFailed(:final reason) => ZajelCard(
                child: Column(
                  children: [
                    Icon(Icons.error_outline, size: 48, color: scheme.error),
                    const SizedBox(height: 12),
                    Text(transportMessage(l10n, reason), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => ref.read(qrHostProvider.notifier).start(),
                      child: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
              QrHostReady(:final payload) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.qrShowIntro, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  Center(
                    // QR codes scan best as black on white, whatever the theme.
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: QrImageView(
                        key: ValueKey(payload.encode()), // lets tests read the code
                        data: payload.encode(),
                        size: (MediaQuery.sizeOf(context).width - 112).clamp(260.0, 360.0),
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.L, // fewer, bigger squares
                        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ZajelCard(
                    child: Column(
                      children: [
                        Text(l10n.qrPinLabel, style: theme.textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text(
                          payload.pin,
                          textDirection: TextDirection.ltr,
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ZajelCard(
                    child: Row(
                      children: [
                        IconBadge(icon: Icons.wifi_tethering, color: scheme.secondary, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l10n.qrNetworkLabel, style: theme.textTheme.bodySmall),
                              Text(
                                payload.ssid,
                                textDirection: TextDirection.ltr,
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            },
          ],
        ),
      ),
    );
  }
}
