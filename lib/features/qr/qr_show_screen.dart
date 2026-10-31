import 'package:flutter/material.dart';

import '../../core/router/placeholder_scaffold.dart';
import '../../l10n/l10n.dart';

class QrShowScreen extends StatelessWidget {
  const QrShowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PlaceholderScaffold(title: context.l10n.qrShowTitle);
  }
}
