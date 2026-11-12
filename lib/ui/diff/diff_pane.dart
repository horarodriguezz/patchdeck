import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../diff/diff_layout.dart';
import 'comment_callbacks.dart';
import '../../state/selection_controller.dart';
import '../../state/workspace_controller.dart';
import 'diff_view.dart';

/// One patch: a slim toolbar (stats, jump-to-file, collapse) + its DiffView.
class DiffPane extends StatefulWidget {
  const DiffPane({
    super.key,
    required this.patchId,
    required this.workspace,
    required this.selection,
    required this.showName,
    required this.horizontalScroll,
    required this.callbacks,
  });

  final String patchId;
  final WorkspaceController workspace;
  final SelectionController selection;
  final bool showName;
  final bool horizontalScroll;
  final CommentCallbacks callbacks;

  @override
  State<DiffPane> createState() => _DiffPaneState();
}

class _DiffPaneState extends State<DiffPane> {
  final ScrollController _scroll = ScrollController();

  /// Scrolls so [key] sits about a third from the top of the viewport.
  void _scrollTo(DiffLayout layout, LineKey key) {
    if (!mounted || !_scroll.hasClients) return;
    final row = layout.rows.indexWhere((r) =>
        r.kind == RowKind.line && r.file == key.$2 && r.hunk == key.$3 && (r.a == key.$4 || r.b == key.$4));
    if (row < 0) return;
    final pos = _scroll.position;
    final target = (layout.offsets[row] - pos.viewportDimension / 3).clamp(0.0, pos.maxScrollExtent);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings.settings;
    final ws = widget.workspace;
    final model = ws.model(widget.patchId);
    final entry = ws.entry(widget.patchId);
    final theme = Theme.of(context);
    if (model == null || entry == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final metrics = DiffMetrics(settings.codeFontSize);
    final layout = ws.layout(widget.patchId, settings.diffMode, metrics)!;
    final parsed = model.parsed;
    final muted = theme.colorScheme.onSurfaceVariant;
    final reveal = ws.takeReveal(widget.patchId);
    if (reveal != null) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(layout, reveal));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(children: [
          if (widget.showName) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
              child: Text(entry.name, style: TextStyle(fontWeight: FontWeight.w700, color: theme.colorScheme.primary, fontSize: 12)),
            ),
            const SizedBox(width: 10),
          ],
          Text('${parsed.files.length} ${parsed.files.length == 1 ? 'archivo' : 'archivos'}', style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(width: 10),
          Text('+${parsed.additions}', style: const TextStyle(color: Color(0xFF57AB5A), fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Text('−${parsed.deletions}', style: const TextStyle(color: Color(0xFFE5534B), fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (parsed.files.isNotEmpty)
            PopupMenuButton<int>(
              tooltip: 'Ir a archivo',
              icon: Icon(Icons.list_alt, size: 18, color: muted),
              onSelected: (f) {
                // Re-read the layout: it may have changed since the menu opened.
                final l = ws.layout(widget.patchId, settings.diffMode, metrics)!;
                final target = l.offsets[l.fileRow[f]];
                _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
              },
              itemBuilder: (_) => [
                for (var i = 0; i < parsed.files.length; i++)
                  PopupMenuItem(
                    value: i,
                    height: 34,
                    child: Row(children: [
                      Expanded(child: Text(parsed.files[i].displayPath, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                      const SizedBox(width: 12),
                      Text('+${parsed.files[i].additions} −${parsed.files[i].deletions}', style: TextStyle(fontSize: 11, color: muted)),
                    ]),
                  ),
              ],
            ),
          IconButton(
            tooltip: 'Colapsar todo',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.unfold_less, color: muted),
            onPressed: () => ws.setAllCollapsed(widget.patchId, true),
          ),
          IconButton(
            tooltip: 'Expandir todo',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.unfold_more, color: muted),
            onPressed: () => ws.setAllCollapsed(widget.patchId, false),
          ),
        ]),
      ),
      Expanded(
        child: parsed.files.isEmpty && parsed.preamble.isEmpty
            ? Center(child: Text('No se encontraron cambios en este patch', style: TextStyle(color: muted)))
            : DiffView(
                workspace: ws,
                selection: widget.selection,
                model: model,
                layout: layout,
                mode: settings.diffMode,
                metrics: metrics,
                controller: _scroll,
                horizontalScroll: widget.horizontalScroll,
                callbacks: widget.callbacks,
              ),
      ),
    ]);
  }
}
