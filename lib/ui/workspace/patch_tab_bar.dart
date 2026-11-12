import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/review.dart';
import '../../state/workspace_controller.dart';

/// Tabs for the review's patches. Click shows a single patch; Ctrl+click
/// toggles it into the side-by-side view.
class PatchTabBar extends StatelessWidget {
  const PatchTabBar({
    super.key,
    required this.workspace,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
  });

  final WorkspaceController workspace;
  final VoidCallback onAdd;
  final void Function(PatchEntry) onRename;
  final void Function(PatchEntry) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final patches = workspace.patches;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              itemCount: patches.length,
              itemBuilder: (context, i) => _PatchTab(
                entry: patches[i],
                visible: workspace.visiblePatchIds.contains(patches[i].id),
                fileCount: workspace.model(patches[i].id)?.parsed.files.length,
                onTap: () => workspace.showPatch(
                  patches[i].id,
                  additive: HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed,
                ),
                onToggleSideBySide: () => workspace.showPatch(patches[i].id, additive: true),
                onRename: () => onRename(patches[i]),
                onDelete: () => onDelete(patches[i]),
              ),
            ),
          ),
          if (patches.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'Ctrl+clic: lado a lado',
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add, size: 16), label: const Text('Patch')),
          ),
        ],
      ),
    );
  }
}

class _PatchTab extends StatelessWidget {
  const _PatchTab({
    required this.entry,
    required this.visible,
    required this.fileCount,
    required this.onTap,
    required this.onToggleSideBySide,
    required this.onRename,
    required this.onDelete,
  });

  final PatchEntry entry;
  final bool visible;
  final int? fileCount;
  final VoidCallback onTap;
  final VoidCallback onToggleSideBySide;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  Future<void> _menu(BuildContext context, Offset pos) async {
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem(value: 'side', child: Text(visible ? 'Quitar de la vista' : 'Ver lado a lado')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'rename', child: Text('Renombrar')),
        const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
      ],
    );
    if (v == 'side') onToggleSideBySide();
    if (v == 'rename') onRename();
    if (v == 'delete') onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.onSurface;
    return GestureDetector(
      onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onRename,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: visible ? primary : Colors.transparent, width: 2)),
          ),
          alignment: Alignment.center,
          child: Row(
            children: [
              Text(
                entry.name,
                style: TextStyle(
                  fontWeight: visible ? FontWeight.w700 : FontWeight.w500,
                  color: visible ? null : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: fileCount == null
                    ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5))
                    : Text('$fileCount', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
              ),
              const SizedBox(width: 2),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTapDown: (d) => _menu(context, d.globalPosition),
                child: Icon(Icons.arrow_drop_down, size: 18, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
