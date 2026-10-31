import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/router/app_router.dart';
import '../../core/transfer/localsend_service.dart';
import '../../core/transfer/transfer_providers.dart';
import '../../l10n/l10n.dart';

/// Sits above the router and shows the accept/decline dialog whenever another
/// device asks to send files, whichever screen is open.
class IncomingTransferHost extends ConsumerWidget {
  const IncomingTransferHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Starts the service as soon as the app opens.
    ref.watch(localSendServiceProvider);

    ref.listen(incomingTransferProvider, (_, next) {
      final pending = next.value;
      if (pending == null || pending.isDecided) return;
      final dialogContext = rootNavigatorKey.currentContext;
      if (dialogContext == null) {
        pending.decline();
        return;
      }
      unawaited(
        showDialog<void>(
          context: dialogContext,
          barrierDismissible: false,
          builder: (_) => _IncomingDialog(pending: pending),
        ),
      );
    });
    return child;
  }
}

class _IncomingDialog extends StatefulWidget {
  const _IncomingDialog({required this.pending});

  final PendingIncoming pending;

  @override
  State<_IncomingDialog> createState() => _IncomingDialogState();
}

class _IncomingDialogState extends State<_IncomingDialog> {
  @override
  void initState() {
    super.initState();
    // Closes on any answer, including the receiver-side timeout.
    widget.pending.decision.then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final transfer = widget.pending.transfer;
    return AlertDialog(
      title: Text(l10n.incomingTitle),
      content: Text(
        '${l10n.incomingBody(transfer.sender.alias, transfer.files.length, formatBytes(transfer.totalBytes))}\n\n'
        '${transfer.files.values.take(5).map((f) => f.fileName).join('\n')}',
      ),
      actions: [
        TextButton(
          onPressed: widget.pending.decline,
          child: Text(l10n.decline),
        ),
        FilledButton(
          onPressed: widget.pending.accept,
          child: Text(l10n.accept),
        ),
      ],
    );
  }
}
