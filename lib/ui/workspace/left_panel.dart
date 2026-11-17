import 'package:flutter/material.dart';

import '../../state/selection_controller.dart';
import '../../state/workspace_controller.dart';
import '../comments/comments_tab.dart';
import '../common/markdown_panel.dart';
import 'files_tab.dart';
import 'side_panel.dart';

/// Left column: "Contexto" (free markdown), "Comentarios" (comments of the
/// visible patches) and "Archivos" (file tree of the visible patches).
/// Collapsed, its rail exposes the tabs as icons.
class LeftPanel extends StatelessWidget {
  const LeftPanel({super.key, required this.workspace, required this.selection});

  final WorkspaceController workspace;
  final SelectionController selection;

  int _activeCount() {
    var n = 0;
    for (final pid in workspace.visiblePatchIds) {
      n += workspace.commentsInPatch(pid, includeDismissed: false).length;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final ws = workspace;
    final count = _activeCount();
    return SidePanel(
      side: AxisDirection.left,
      open: ws.leftOpen,
      onToggle: ws.toggleLeft,
      initialWidth: 360,
      header: LayoutBuilder(
        // Narrow panel: only the selected tab keeps its label.
        builder: (context, c) {
          final compact = c.maxWidth < 330;
          return Row(
            children: [
              const SizedBox(width: 6),
              _TabButton(
                icon: Icons.description_outlined,
                label: 'Contexto',
                compact: compact,
                selected: ws.leftTab == 0,
                onTap: () => ws.setLeftTab(0),
              ),
              _TabButton(
                icon: Icons.forum_outlined,
                label: 'Comentarios',
                compact: compact,
                badge: count,
                selected: ws.leftTab == 1,
                onTap: () => ws.setLeftTab(1),
              ),
              _TabButton(
                icon: Icons.account_tree_outlined,
                label: 'Archivos',
                tooltip: 'Archivos (Ctrl+E)',
                compact: compact,
                selected: ws.leftTab == 2,
                onTap: () => ws.setLeftTab(2),
              ),
            ],
          );
        },
      ),
      rail: Column(
        children: [
          const SizedBox(height: 6),
          IconButton(
            tooltip: 'Contexto',
            iconSize: 18,
            icon: const Icon(Icons.description_outlined),
            onPressed: () => ws.openLeftTab(0),
          ),
          IconButton(
            tooltip: 'Comentarios',
            iconSize: 18,
            icon: Badge(isLabelVisible: count > 0, label: Text('$count'), child: const Icon(Icons.forum_outlined)),
            onPressed: () => ws.openLeftTab(1),
          ),
          IconButton(
            tooltip: 'Archivos (Ctrl+E)',
            iconSize: 18,
            icon: const Icon(Icons.account_tree_outlined),
            onPressed: () => ws.openLeftTab(2),
          ),
        ],
      ),
      child: IndexedStack(
        index: ws.leftTab,
        sizing: StackFit.expand,
        children: [
          MarkdownPanel(
            initialText: ws.review.contextMarkdown,
            onChanged: ws.setContext,
            hint: 'Pega aquí la descripción del PR, el ticket, requisitos… (Markdown)',
          ),
          CommentsTab(workspace: ws, selection: selection),
          FilesTab(workspace: ws),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
    this.compact = false,
    this.tooltip,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;
  final bool compact;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant;
    final showLabel = selected || !compact;
    return Tooltip(
      message: tooltip ?? label,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 40,
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: selected ? color : Colors.transparent, width: 2)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              if (showLabel) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? null : color,
                  ),
                ),
              ],
              if (badge > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('$badge', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
