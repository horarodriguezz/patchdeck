import 'package:flutter/material.dart';

import '../../diff/diff_models.dart';
import '../../state/workspace_controller.dart';
import '../comments/comments_tab.dart' show PatchBadge;
import '../diff/diff_rows.dart' show CopyPathButton;

/// A folder or file of [buildFileTree]. Chains of single-child folders are
/// compacted into one node ("src/ui/diff").
class FileTreeNode {
  FileTreeNode.dir(this.name, this.path) : file = -1;
  FileTreeNode.file(this.name, this.path, this.file);

  final String name;

  /// Folder path (for expansion state) or the file's path.
  final String path;

  /// Index of the file in its patch, -1 for folders.
  final int file;
  final List<FileTreeNode> children = [];

  bool get isDir => file < 0;
}

/// Builds the folder tree of [files]: folders first, then files, by name.
List<FileTreeNode> buildFileTree(List<DiffFile> files) {
  final root = FileTreeNode.dir('', '');
  for (var i = 0; i < files.length; i++) {
    final parts = files[i].path.split('/');
    var node = root;
    for (var p = 0; p < parts.length - 1; p++) {
      final path = parts.sublist(0, p + 1).join('/');
      var next = node.children.where((c) => c.isDir && c.path == path).firstOrNull;
      if (next == null) {
        next = FileTreeNode.dir(parts[p], path);
        node.children.add(next);
      }
      node = next;
    }
    node.children.add(FileTreeNode.file(parts.last, files[i].path, i));
  }

  FileTreeNode compact(FileTreeNode n) {
    var cur = n;
    while (cur.isDir && cur.children.length == 1 && cur.children.first.isDir) {
      final child = cur.children.first;
      final merged = FileTreeNode.dir('${cur.name}/${child.name}', child.path)..children.addAll(child.children);
      cur = merged;
    }
    final kids = [for (final c in cur.children) c.isDir ? compact(c) : c]
      ..sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    cur.children
      ..clear()
      ..addAll(kids);
    return cur;
  }

  return [for (final c in root.children) c.isDir ? compact(c) : c]..sort((a, b) {
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
}

/// "Archivos": the files of the visible patches as a folder tree. Clicking a
/// file jumps to it in the diff.
class FilesTab extends StatefulWidget {
  const FilesTab({super.key, required this.workspace});
  final WorkspaceController workspace;

  @override
  State<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<FilesTab> {
  /// Collapsed folders, as "patchId|path".
  final Set<String> _closed = {};

  /// Trees are rebuilt only when a patch's parsed files change.
  final Map<String, (List<DiffFile>, List<FileTreeNode>)> _trees = {};

  List<FileTreeNode> _treeFor(String patchId, List<DiffFile> files) {
    final cached = _trees[patchId];
    if (cached != null && identical(cached.$1, files)) return cached.$2;
    final t = buildFileTree(files);
    _trees[patchId] = (files, t);
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final ws = widget.workspace;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final ids = ws.visiblePatchIds;
    final multi = ids.length > 1;
    final items = <Widget Function()>[];
    for (final pid in ids) {
      final model = ws.model(pid);
      final entry = ws.entry(pid);
      if (entry == null) continue;
      if (multi) {
        items.add(
          () => Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(children: [PatchBadge(name: entry.name)]),
          ),
        );
      }
      if (model == null) {
        items.add(
          () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
        );
        continue;
      }
      final files = model.parsed.files;
      if (files.isEmpty) {
        items.add(
          () => Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('Sin archivos', style: TextStyle(color: muted, fontSize: 12)),
          ),
        );
        continue;
      }
      final counts = <String, int>{};
      for (final c in ws.comments) {
        if (c.dismissed) continue;
        for (final path in {
          for (final a in c.anchors)
            if (a.patchId == pid) a.path,
        }) {
          counts[path] = (counts[path] ?? 0) + 1;
        }
      }
      void walk(List<FileTreeNode> nodes, int depth) {
        for (final n in nodes) {
          if (n.isDir) {
            final key = '$pid|${n.path}';
            final open = !_closed.contains(key);
            items.add(
              () => _TreeRow(
                depth: depth,
                icon: open ? Icons.folder_open_outlined : Icons.folder_outlined,
                chevron: open ? Icons.expand_more : Icons.chevron_right,
                name: n.name,
                onTap: () => setState(() => open ? _closed.add(key) : _closed.remove(key)),
              ),
            );
            if (open) walk(n.children, depth + 1);
          } else {
            final f = files[n.file];
            items.add(
              () => _TreeRow(
                depth: depth,
                name: n.name,
                file: f,
                comments: counts[f.path] ?? 0,
                viewed: ws.isViewed(pid, n.file),
                onTap: () => ws.revealFile(pid, n.file),
              ),
            );
          }
        }
      }

      walk(_treeFor(pid, files), 0);
    }
    if (items.isEmpty) {
      return Center(
        child: Text('No hay patches abiertos', style: TextStyle(color: muted, fontSize: 12)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: items.length,
      itemBuilder: (_, i) => items[i](),
    );
  }
}

class _TreeRow extends StatefulWidget {
  const _TreeRow({
    required this.depth,
    required this.name,
    required this.onTap,
    this.icon,
    this.chevron,
    this.file,
    this.comments = 0,
    this.viewed = false,
  });

  final int depth;
  final String name;
  final VoidCallback onTap;
  final IconData? icon;
  final IconData? chevron;
  final DiffFile? file;
  final int comments;
  final bool viewed;

  @override
  State<_TreeRow> createState() => _TreeRowState();
}

class _TreeRowState extends State<_TreeRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final file = widget.file;
    final statusColor = switch (file?.status) {
      FileStatus.added => const Color(0xFF57AB5A),
      FileStatus.deleted => const Color(0xFFE5534B),
      FileStatus.renamed => const Color(0xFFC69026),
      FileStatus.copied => const Color(0xFF539BF5),
      _ => muted,
    };
    final row = InkWell(
      onTap: widget.onTap,
      child: SizedBox(
        height: 26,
        child: Row(
          children: [
            SizedBox(width: 8.0 + widget.depth * 14),
            SizedBox(width: 16, child: widget.chevron == null ? null : Icon(widget.chevron, size: 16, color: muted)),
            const SizedBox(width: 2),
            Icon(widget.icon ?? Icons.insert_drive_file_outlined, size: 15, color: file == null ? muted : statusColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: widget.viewed ? muted : null,
                  decoration: file?.status == FileStatus.deleted ? TextDecoration.lineThrough : null,
                  decorationColor: muted,
                ),
              ),
            ),
            if (file != null) ...[
              if (_hover) CopyPathButton(path: file.path, size: 13),
              if (widget.comments > 0) ...[
                const SizedBox(width: 4),
                Icon(Icons.chat_bubble_outline, size: 12, color: theme.colorScheme.primary),
                const SizedBox(width: 2),
                Text('${widget.comments}', style: TextStyle(fontSize: 11, color: theme.colorScheme.primary)),
              ],
              const SizedBox(width: 6),
              if (file.additions > 0)
                Text('+${file.additions}', style: const TextStyle(fontSize: 11, color: Color(0xFF57AB5A))),
              if (file.additions > 0 && file.deletions > 0) const SizedBox(width: 4),
              if (file.deletions > 0)
                Text('−${file.deletions}', style: const TextStyle(fontSize: 11, color: Color(0xFFE5534B))),
              const SizedBox(width: 6),
              Tooltip(
                message: widget.viewed ? 'Visto' : 'Sin ver',
                child: Icon(
                  widget.viewed ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 14,
                  color: widget.viewed ? theme.colorScheme.primary : muted.withValues(alpha: 0.5),
                ),
              ),
            ],
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
    if (file == null) return row;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(message: file.displayPath, waitDuration: const Duration(milliseconds: 600), child: row),
    );
  }
}
