import 'package:flutter/material.dart';

import '../../diff/diff_layout.dart';
import '../../diff/diff_models.dart';
import '../../models/label.dart';
import '../../models/review.dart';
import '../../theme/diff_theme.dart';
import '../comments/comment_card.dart';
import '../common/label_chip.dart';

class FileHeaderRow extends StatelessWidget {
  const FileHeaderRow({
    super.key,
    required this.file,
    required this.collapsed,
    required this.onToggle,
    required this.commentCount,
  });

  final DiffFile file;
  final bool collapsed;
  final VoidCallback onToggle;
  final int commentCount;

  @override
  Widget build(BuildContext context) {
    final t = context.diffTheme;
    final theme = Theme.of(context);
    final (statusText, statusColor) = switch (file.status) {
      FileStatus.added => ('nuevo', const Color(0xFF57AB5A)),
      FileStatus.deleted => ('eliminado', const Color(0xFFE5534B)),
      FileStatus.renamed => ('renombrado', const Color(0xFFC69026)),
      FileStatus.copied => ('copiado', const Color(0xFF539BF5)),
      FileStatus.modified => ('', Colors.transparent),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: t.fileHeaderBg,
        shape: Border(
          top: BorderSide(color: t.border),
          bottom: BorderSide(color: t.border),
        ),
        child: InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(
                  collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          file.displayPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                      if (statusText.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            border: Border.all(color: statusColor.withValues(alpha: 0.7)),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(statusText, style: TextStyle(fontSize: 11, color: statusColor)),
                        ),
                      ],
                    ],
                  ),
                ),
                if (commentCount > 0) ...[
                  Icon(Icons.chat_bubble_outline, size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 3),
                  Text('$commentCount', style: TextStyle(fontSize: 12, color: theme.colorScheme.primary)),
                  const SizedBox(width: 12),
                ],
                Text(
                  '+${file.additions}',
                  style: const TextStyle(color: Color(0xFF57AB5A), fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                Text(
                  '−${file.deletions}',
                  style: const TextStyle(color: Color(0xFFE5534B), fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HunkRow extends StatelessWidget {
  const HunkRow({super.key, required this.hunk, required this.style});
  final DiffHunk hunk;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final t = context.diffTheme;
    return ColoredBox(
      color: t.hunkBg,
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            hunk.header,
            style: style.copyWith(color: t.hunkFg),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
          ),
        ),
      ),
    );
  }
}

class NoticeRow extends StatelessWidget {
  const NoticeRow({super.key, required this.file});
  final DiffFile file;

  @override
  Widget build(BuildContext context) {
    final t = context.diffTheme;
    final msg = file.isBinary
        ? 'Archivo binario — sin vista de diff'
        : file.status == FileStatus.renamed || file.status == FileStatus.copied
        ? 'Archivo movido sin cambios de contenido'
        : 'Sin cambios de contenido (modo / permisos)';
    return ColoredBox(
      color: t.codeBg,
      child: Center(
        child: Text(msg, style: TextStyle(color: t.lineNoFg, fontSize: 12)),
      ),
    );
  }
}

class PreambleRow extends StatelessWidget {
  const PreambleRow({super.key, required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final t = context.diffTheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.fileHeaderBg,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ClipRect(
        child: Text(
          text,
          style: style.copyWith(color: t.codeFg),
          maxLines: DiffMetrics.maxPreambleLines,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Fixed-height comment card rendered inline after the last commented line.
class CommentRow extends StatelessWidget {
  const CommentRow({
    super.key,
    required this.comment,
    required this.labels,
    required this.summary,
    required this.onEdit,
    required this.onDelete,
    required this.onCopy,
    required this.onToggleDismissed,
    required this.indent,
  });

  final ReviewComment comment;
  final List<ReviewLabel> labels;
  final String summary;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onCopy;
  final VoidCallback onToggleDismissed;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final t = context.diffTheme;
    final theme = Theme.of(context);
    final dismissed = comment.dismissed;
    final muted = theme.colorScheme.onSurfaceVariant;
    final accent = dismissed ? t.border : (labels.isEmpty ? theme.colorScheme.primary : labels.first.colorValue);
    return ColoredBox(
      color: t.codeBg,
      child: Padding(
        padding: EdgeInsets.fromLTRB(indent, 6, 12, 6),
        child: Opacity(
          opacity: dismissed ? 0.55 : 1,
          child: Material(
            color: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(color: t.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onEdit,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: accent),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 20,
                                  child: ClipRect(
                                    child: OverflowBox(
                                      alignment: Alignment.centerLeft,
                                      maxWidth: double.infinity,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        spacing: 4,
                                        children: [
                                          if (dismissed) const DismissedBadge(),
                                          for (final l in labels) LabelChip(label: l, dense: true),
                                          if (labels.isEmpty && !dismissed)
                                            Text(
                                              'sin etiquetas',
                                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(summary, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                              const SizedBox(width: 6),
                              _MiniIcon(icon: Icons.content_copy, tip: 'Copiar comentario', onTap: onCopy),
                              _MiniIcon(
                                icon: dismissed ? Icons.restore : Icons.block,
                                tip: dismissed ? 'Restaurar' : 'Denegar',
                                onTap: onToggleDismissed,
                              ),
                              _MiniIcon(icon: Icons.edit_outlined, tip: 'Editar', onTap: onEdit),
                              _MiniIcon(icon: Icons.delete_outline, tip: 'Eliminar', onTap: onDelete),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: Text(
                              comment.text.isEmpty ? '(sin texto)' : comment.text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: dismissed ? muted : null,
                                decoration: dismissed ? TextDecoration.lineThrough : null,
                                decorationColor: muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniIcon extends StatelessWidget {
  const _MiniIcon({required this.icon, required this.tip, required this.onTap});
  final IconData icon;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}
