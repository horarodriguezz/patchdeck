import 'package:flutter/material.dart';

import '../../state/selection_controller.dart';
import '../../state/workspace_controller.dart';
import '../comments/comments_tab.dart';
import '../common/markdown_panel.dart';
import 'side_panel.dart';

/// Left column: "Contexto" (free markdown) and "Comentarios" (comments of the
/// visible patches). Collapsed, its rail exposes both tabs as icons.
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
      header: Row(
        children: [
          const SizedBox(width: 6),
          _TabButton(
            icon: Icons.description_outlined,
            label: 'Contexto',
            selected: ws.leftTab == 0,
            onTap: () => ws.setLeftTab(0),
          ),
          _TabButton(
            icon: Icons.forum_outlined,
            label: 'Comentarios',
            badge: count,
            selected: ws.leftTab == 1,
            onTap: () => ws.setLeftTab(1),
          ),
        ],
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
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: selected ? color : Colors.transparent, width: 2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? null : color,
              ),
            ),
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
    );
  }
}
