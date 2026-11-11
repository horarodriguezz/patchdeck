import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/review.dart';
import '../common/dialogs.dart';
import '../settings/settings_screen.dart';
import '../workspace/workspace_screen.dart';
import 'review_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _create(BuildContext context) async {
    final title = await promptText(context, title: 'Nueva review', label: 'Título', confirm: 'Crear');
    if (title == null || !context.mounted) return;
    final review = await AppScope.of(context).reviews.create(title);
    if (context.mounted) _open(context, review.id);
  }

  void _open(BuildContext context, String id) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkspaceScreen(reviewId: id)));
  }

  @override
  Widget build(BuildContext context) {
    final reviews = AppScope.of(context).reviews;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Icon(Icons.difference_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          const Text('Patchdeck'),
        ]),
        actions: [
          IconButton(
            tooltip: 'Configuración',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: reviews,
        builder: (context, _) {
          if (reviews.loading) return const Center(child: CircularProgressIndicator());
          final items = reviews.items;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                    child: Row(children: [
                      Text('Reviews', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      Text('${items.length}', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: () => _create(context),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Nueva review'),
                      ),
                    ]),
                  ),
                  Expanded(
                    child: items.isEmpty
                        ? _EmptyState(onCreate: () => _create(context))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                            itemCount: items.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, i) => ReviewCard(
                              summary: items[i],
                              onOpen: () => _open(context, items[i].id),
                              onRename: () => _rename(context, items[i]),
                              onDelete: () => _delete(context, items[i]),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _rename(BuildContext context, ReviewSummary s) async {
    final t = await promptText(context, title: 'Renombrar review', initial: s.title, label: 'Título');
    if (t != null && t.trim().isNotEmpty && context.mounted) await AppScope.of(context).reviews.rename(s.id, t.trim());
  }

  Future<void> _delete(BuildContext context, ReviewSummary s) async {
    final ok = await confirmDialog(context,
        title: 'Eliminar review', message: '¿Eliminar "${s.title}"? Esta acción no se puede deshacer.');
    if (ok && context.mounted) await AppScope.of(context).reviews.delete(s.id);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.rate_review_outlined, size: 56, color: muted),
        const SizedBox(height: 12),
        Text('Todavía no hay reviews', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text('Crea una review y pega uno o más git patches para analizarlos.', style: TextStyle(color: muted)),
        const SizedBox(height: 16),
        OutlinedButton.icon(onPressed: onCreate, icon: const Icon(Icons.add), label: const Text('Crear la primera')),
      ]),
    );
  }
}
