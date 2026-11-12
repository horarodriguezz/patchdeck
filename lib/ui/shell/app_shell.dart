import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../workspace/workspace_screen.dart';
import 'reviews_sidebar.dart';
import 'shell_buttons.dart';
import 'title_bar.dart';

/// Root layout: reviews sidebar + the open review (or a placeholder).
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ReviewsSidebar(),
          Expanded(
            child: ListenableBuilder(
              listenable: shell,
              builder: (context, _) {
                final id = shell.openReviewId;
                if (id == null) return const _NoReview();
                return WorkspaceScreen(key: ValueKey(id), reviewId: id);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NoReview extends StatelessWidget {
  const _NoReview();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppTopBar(),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.rate_review_outlined, size: 56, color: muted),
                const SizedBox(height: 12),
                Text('Ninguna review abierta', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  'Elige una en el panel lateral o crea una nueva y pega uno o más git patches.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => createReview(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva review'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
