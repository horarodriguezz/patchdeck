import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/label.dart';
import '../../models/review.dart';
import '../../state/comment_format.dart';
import '../../state/selection_controller.dart';
import '../../state/workspace_controller.dart';
import 'comment_actions.dart';
import 'comment_card.dart';

/// Comments of the patches currently on screen, grouped by patch and
/// ordered by position. Clicking a comment scrolls the diff to it and opens
/// it in the composer.
class CommentsTab extends StatefulWidget {
  const CommentsTab({super.key, required this.workspace, required this.selection});

  final WorkspaceController workspace;
  final SelectionController selection;

  @override
  State<CommentsTab> createState() => _CommentsTabState();
}

class _CommentsTabState extends State<CommentsTab> {
  bool _showDismissed = true;

  @override
  Widget build(BuildContext context) {
    final ws = widget.workspace;
    final settings = AppScope.of(context).settings;
    final actions = CommentActions(context, ws);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final names = actions.patchNames;

    final items = <Widget Function()>[];
    var total = 0, dismissedCount = 0;
    for (final pid in ws.visiblePatchIds) {
      final all = ws.commentsInPatch(pid);
      final active = all.where((c) => !c.dismissed).length;
      total += all.length;
      dismissedCount += all.length - active;
      final shown = _showDismissed ? all : all.where((c) => !c.dismissed).toList();
      items.add(
        () => _PatchHeader(
          name: names[pid] ?? '?',
          active: active,
          dismissed: all.length - active,
          onCopy: active == 0 ? null : () => actions.copyPatch(pid),
        ),
      );
      if (shown.isEmpty) {
        items.add(
          () => Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
              'Sin comentarios. Selecciona líneas con + para comentar.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
        );
      }
      for (final c in shown) {
        items.add(() {
          final others = <String>{
            for (final a in c.anchors)
              if (a.patchId != pid) names[a.patchId] ?? '?',
          };
          return Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: CommentCard(
              comment: c,
              labels: [for (final id in c.labelIds) ?settings.labelById(id)],
              locations: describeLocations(c.anchors, patchNames: names, patchId: pid),
              alsoIn: others.isEmpty ? null : 'También en ${others.join(', ')}',
              onTap: () => _open(c, pid),
              onCopy: () => actions.copyOne(c, patchId: pid),
              onToggleDismissed: () => actions.toggleDismissed(c),
              onEdit: () => _open(c, pid),
              onDelete: () => actions.delete(
                c,
                afterDelete: () {
                  if (widget.selection.editingCommentId == c.id) widget.selection.clear();
                },
              ),
            ),
          );
        });
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  total == 0
                      ? 'Sin comentarios'
                      : '$total ${total == 1 ? 'comentario' : 'comentarios'}${dismissedCount > 0 ? ' · $dismissedCount ${dismissedCount == 1 ? 'denegado' : 'denegados'}' : ''}',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ),
              if (dismissedCount > 0)
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Denegados', style: TextStyle(fontSize: 12)),
                  selected: _showDismissed,
                  onSelected: (v) => setState(() => _showDismissed = v),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: items.length,
            itemBuilder: (_, i) => items[i](),
          ),
        ),
      ],
    );
  }

  void _open(ReviewComment c, String patchId) {
    final ws = widget.workspace;
    final k = ws.firstKeyOf(c, patchId) ?? ws.firstKeyOf(c);
    if (k != null) ws.reveal(k);
    widget.selection.setSelection(ws.keysFor(c), editing: c.id);
  }
}

class _PatchHeader extends StatelessWidget {
  const _PatchHeader({required this.name, required this.active, required this.dismissed, required this.onCopy});
  final String name;
  final int active;
  final int dismissed;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
      child: Row(
        children: [
          PatchBadge(name: name),
          const SizedBox(width: 8),
          Text(
            '$active ${active == 1 ? 'activo' : 'activos'}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          if (dismissed > 0)
            Text(
              '  ·  $dismissed ${dismissed == 1 ? 'denegado' : 'denegados'}',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
          const Spacer(),
          TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: primary),
            onPressed: onCopy,
            icon: const Icon(Icons.copy_all, size: 16),
            label: const Text('Copiar todos', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class PatchBadge extends StatelessWidget {
  const PatchBadge({super.key, required this.name, this.large = false});
  final String name;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 10 : 7, vertical: large ? 3 : 1),
      decoration: BoxDecoration(color: primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
      child: Text(
        name,
        style: TextStyle(fontWeight: FontWeight.w700, color: primary, fontSize: large ? 14 : 12),
      ),
    );
  }
}

List<ReviewLabel> labelsOf(ReviewComment c, ReviewLabel? Function(String) byId) => [
  for (final id in c.labelIds) ?byId(id),
];
