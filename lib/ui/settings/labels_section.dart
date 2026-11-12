import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/label.dart';
import '../common/dialogs.dart';
import '../common/label_chip.dart';
import 'label_editor_dialog.dart';

class LabelsSection extends StatelessWidget {
  const LabelsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final labels = ctrl.labels;
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Etiquetas', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          'Se usan para clasificar los comentarios. Arrastra para reordenar.',
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _edit(context, null),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Nueva etiqueta'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                buildDefaultDragHandles: false,
                itemCount: labels.length,
                onReorder: ctrl.reorderLabel,
                itemBuilder: (context, i) {
                  final l = labels[i];
                  return Padding(
                    key: ValueKey(l.id),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator)),
                        title: Align(
                          alignment: Alignment.centerLeft,
                          child: LabelChip(label: l),
                        ),
                        subtitle: l.description.isEmpty ? null : Text(l.description),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Editar',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _edit(context, l),
                            ),
                            IconButton(
                              tooltip: 'Eliminar',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                if (await confirmDialog(
                                  context,
                                  title: 'Eliminar etiqueta',
                                  message: '¿Eliminar "${l.title}"?',
                                )) {
                                  ctrl.deleteLabel(l.id);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, ReviewLabel? label) async {
    final ctrl = AppScope.of(context).settings;
    final r = await showDialog<ReviewLabel>(
      context: context,
      builder: (_) => LabelEditorDialog(initial: label),
    );
    if (r == null) return;
    ctrl.upsertLabel(id: label?.id, title: r.title, description: r.description, color: r.color);
  }
}
