import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// Body of a Phase 0 screen: a title and a "coming soon" note, plus optional
/// buttons that let you walk through the route graph.
class PlaceholderScaffold extends StatelessWidget {
  const PlaceholderScaffold({
    required this.title,
    this.actions = const [],
    super.key,
  });

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.comingSoon,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (actions.isNotEmpty) const SizedBox(height: 32),
              for (final action in actions) ...[
                action,
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
