import 'package:flutter/material.dart';

import '../../models/review.dart';
import '../common/dialogs.dart';

class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key, required this.summary, required this.onOpen, required this.onRename, required this.onDelete});

  final ReviewSummary summary;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(children: [
            Icon(Icons.description_outlined, color: muted),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(summary.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Actualizada ${formatDate(summary.updatedAt)}  ·  creada ${formatDate(summary.createdAt)}',
                    style: TextStyle(color: muted, fontSize: 12)),
              ]),
            ),
            _Stat(icon: Icons.layers_outlined, text: summary.patchNames.isEmpty ? '0' : summary.patchNames.join(' · '), tip: 'Patches'),
            const SizedBox(width: 16),
            _Stat(icon: Icons.chat_bubble_outline, text: '${summary.commentCount}', tip: 'Comentarios'),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              tooltip: 'Acciones',
              icon: Icon(Icons.more_vert, color: muted),
              onSelected: (v) => v == 'rename' ? onRename() : onDelete(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                PopupMenuItem(value: 'delete', child: Text('Eliminar')),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.text, required this.tip});
  final IconData icon;
  final String text;
  final String tip;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message: tip,
      child: Row(children: [
        Icon(icon, size: 16, color: muted),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 13)),
        ),
      ]),
    );
  }
}
