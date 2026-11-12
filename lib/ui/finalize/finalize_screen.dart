import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/label.dart';
import '../../models/review.dart';
import '../../state/comment_format.dart';
import '../../state/review_export.dart';
import '../../state/workspace_controller.dart';
import '../comments/comment_actions.dart';
import '../comments/comment_card.dart';
import '../comments/comments_tab.dart' show PatchBadge;
import '../common/label_chip.dart';
import '../common/markdown_panel.dart';
import '../shell/title_bar.dart';
import 'code_snippet.dart';

/// End-of-review overview: every comment of every patch (with the code it
/// points at), label filters, dismiss/edit/delete, and the notes on the side.
class FinalizeScreen extends StatefulWidget {
  const FinalizeScreen({super.key, required this.workspace, required this.onClose, required this.onOpenInDiff});

  final WorkspaceController workspace;

  /// Back to the workspace.
  final VoidCallback onClose;

  /// Back to the workspace, jumping to a comment in the diff.
  final void Function(ReviewComment comment, String patchId) onOpenInDiff;

  @override
  State<FinalizeScreen> createState() => _FinalizeScreenState();
}

class _FinalizeScreenState extends State<FinalizeScreen> {
  final Set<String> _labelFilter = {};
  bool _showDismissed = true;

  bool _passes(ReviewComment c) =>
      (_showDismissed || !c.dismissed) && (_labelFilter.isEmpty || c.labelIds.any(_labelFilter.contains));

  @override
  Widget build(BuildContext context) {
    final ws = widget.workspace;
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: Listenable.merge([ws, settings]),
      builder: (context, _) {
        final actions = CommentActions(context, ws);
        final theme = Theme.of(context);
        final comments = ws.comments;
        final active = comments.where((c) => !c.dismissed).length;

        final compact = ButtonStyle(
          visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
          textStyle: WidgetStatePropertyAll(theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTopBar(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TitleBarIconButton(
                    tooltip: 'Volver al workspace',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: widget.onClose,
                  ),
                  const SizedBox(width: 4),
                  const Text('Finalizar review'),
                  Flexible(
                    child: Text(
                      '  ·  ${ws.review.title}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w400, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              actions: [
                OutlinedButton.icon(
                  style: compact,
                  onPressed: () => actions.copyText(
                    exportReviewMarkdown(ws.review, settings.labelById),
                    'Review completa copiada como Markdown',
                  ),
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('Copiar como Markdown'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: compact,
                  onPressed: active == 0
                      ? null
                      : () => actions.copyText(
                          exportAllCommentsText(
                            ws.review,
                            settings.labelById,
                            template: settings.settings.copyTemplate,
                          ),
                          '$active ${active == 1 ? 'comentario copiado' : 'comentarios copiados'}',
                        ),
                  icon: const Icon(Icons.copy_all, size: 16),
                  label: const Text('Copiar todos los comentarios'),
                ),
              ],
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _commentsColumn(context, actions)),
                  VerticalDivider(width: 1, color: theme.dividerColor),
                  SizedBox(width: 400, child: _NotesColumn(workspace: ws)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _commentsColumn(BuildContext context, CommentActions actions) {
    final ws = widget.workspace;
    final settings = AppScope.of(context).settings;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final names = actions.patchNames;
    final all = ws.comments;
    final dismissed = all.where((c) => c.dismissed).length;

    // Label counts over active comments.
    final labelCounts = <String, int>{};
    for (final c in all) {
      if (c.dismissed) continue;
      for (final id in c.labelIds) {
        labelCounts[id] = (labelCounts[id] ?? 0) + 1;
      }
    }

    final items = <Widget Function()>[
      () => _SummaryHeader(
        total: all.length,
        dismissed: dismissed,
        patches: ws.patches.length,
        labels: [
          for (final l in settings.labels)
            if (labelCounts.containsKey(l.id)) l,
        ],
        labelCounts: labelCounts,
        filter: _labelFilter,
        showDismissed: _showDismissed,
        onToggleLabel: (id) =>
            setState(() => _labelFilter.contains(id) ? _labelFilter.remove(id) : _labelFilter.add(id)),
        onShowDismissed: (v) => setState(() => _showDismissed = v),
      ),
    ];

    for (final p in ws.patches) {
      final inPatch = ws.commentsInPatch(p.id);
      final activeHere = inPatch.where((c) => !c.dismissed).length;
      final shown = inPatch.where(_passes).toList();
      final model = ws.model(p.id);
      items.add(
        () => _PatchSectionHeader(
          entry: p,
          files: model?.parsed.files.length,
          additions: model?.parsed.additions,
          deletions: model?.parsed.deletions,
          active: activeHere,
          dismissed: inPatch.length - activeHere,
          onCopy: activeHere == 0 ? null : () => actions.copyPatch(p.id),
        ),
      );
      if (shown.isEmpty) {
        items.add(
          () => Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
            child: Text(
              inPatch.isEmpty ? 'Sin comentarios en este patch.' : 'Ningún comentario coincide con el filtro.',
              style: TextStyle(color: muted, fontSize: 12.5),
            ),
          ),
        );
        continue;
      }
      for (final c in shown) {
        items.add(() {
          final keys = [
            for (final k in ws.keysFor(c))
              if (k.$1 == p.id) k,
          ];
          final others = <String>{
            for (final a in c.anchors)
              if (a.patchId != p.id) names[a.patchId] ?? '?',
          };
          return Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 10),
            child: CommentCard(
              comment: c,
              labels: [for (final id in c.labelIds) ?settings.labelById(id)],
              locations: describeLocations(c.anchors, patchNames: names, patchId: p.id),
              alsoIn: others.isEmpty ? null : 'También en ${others.join(', ')}',
              maxLines: null,
              snippet: model == null || keys.isEmpty ? null : CodeSnippet(model: model, keys: keys),
              onTap: () => widget.onOpenInDiff(c, p.id),
              onCopy: () => actions.copyOne(c, patchId: p.id),
              onToggleDismissed: () => actions.toggleDismissed(c),
              onEdit: () => actions.edit(c),
              onDelete: () => actions.delete(c),
            ),
          );
        });
      }
      items.add(() => const SizedBox(height: 12));
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 32),
          itemCount: items.length,
          itemBuilder: (_, i) => items[i](),
        ),
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.total,
    required this.dismissed,
    required this.patches,
    required this.labels,
    required this.labelCounts,
    required this.filter,
    required this.showDismissed,
    required this.onToggleLabel,
    required this.onShowDismissed,
  });

  final int total;
  final int dismissed;
  final int patches;
  final List<ReviewLabel> labels;
  final Map<String, int> labelCounts;
  final Set<String> filter;
  final bool showDismissed;
  final ValueChanged<String> onToggleLabel;
  final ValueChanged<bool> onShowDismissed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    Widget stat(String value, String label) => Padding(
      padding: const EdgeInsets.only(right: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          Text(label, style: TextStyle(color: muted, fontSize: 12)),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              stat('${total - dismissed}', 'comentarios activos'),
              stat('$dismissed', dismissed == 1 ? 'denegado' : 'denegados'),
              stat('$patches', patches == 1 ? 'patch' : 'patches'),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Filtrar:', style: TextStyle(color: muted, fontSize: 12)),
              for (final l in labels)
                Opacity(
                  opacity: filter.isEmpty || filter.contains(l.id) ? 1 : 0.45,
                  child: LabelChip(
                    label: l.copyWith(title: '${l.title}  ${labelCounts[l.id]}'),
                    onTap: () => onToggleLabel(l.id),
                    outlined: !filter.contains(l.id),
                  ),
                ),
              if (labels.isEmpty) Text('sin etiquetas', style: TextStyle(color: muted, fontSize: 12)),
              if (dismissed > 0)
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Mostrar denegados', style: TextStyle(fontSize: 12)),
                  selected: showDismissed,
                  onSelected: onShowDismissed,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: theme.dividerColor),
        ],
      ),
    );
  }
}

class _PatchSectionHeader extends StatelessWidget {
  const _PatchSectionHeader({
    required this.entry,
    required this.files,
    required this.additions,
    required this.deletions,
    required this.active,
    required this.dismissed,
    required this.onCopy,
  });

  final PatchEntry entry;
  final int? files;
  final int? additions;
  final int? deletions;
  final int active;
  final int dismissed;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 14, 20, 10),
      child: Row(
        children: [
          PatchBadge(name: entry.name, large: true),
          const SizedBox(width: 12),
          Text(
            '$active ${active == 1 ? 'comentario' : 'comentarios'}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (dismissed > 0)
            Text(
              '  ·  $dismissed ${dismissed == 1 ? 'denegado' : 'denegados'}',
              style: TextStyle(color: muted, fontSize: 13),
            ),
          const SizedBox(width: 14),
          if (files != null) ...[
            Text('$files ${files == 1 ? 'archivo' : 'archivos'}', style: TextStyle(color: muted, fontSize: 12)),
            const SizedBox(width: 8),
            Text(
              '+$additions',
              style: const TextStyle(color: Color(0xFF57AB5A), fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            Text(
              '−$deletions',
              style: const TextStyle(color: Color(0xFFE5534B), fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
          const Spacer(),
          TextButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.copy_all, size: 16),
            label: Text('Copiar comentarios de ${entry.name}'),
          ),
        ],
      ),
    );
  }
}

class _NotesColumn extends StatelessWidget {
  const _NotesColumn({required this.workspace});
  final WorkspaceController workspace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(
              tabAlignment: TabAlignment.start,
              isScrollable: true,
              dividerColor: theme.dividerColor,
              tabs: const [
                Tab(height: 40, icon: null, text: 'Notas'),
                Tab(height: 40, text: 'Contexto'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  MarkdownPanel(
                    initialText: workspace.review.notesMarkdown,
                    onChanged: workspace.setNotes,
                    hint: 'Conclusiones, resumen, próximos pasos… (Markdown)',
                  ),
                  MarkdownPanel(
                    initialText: workspace.review.contextMarkdown,
                    onChanged: workspace.setContext,
                    hint: 'Contexto de la review (Markdown)',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
