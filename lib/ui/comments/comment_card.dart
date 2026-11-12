import 'package:flutter/material.dart';

import '../../models/label.dart';
import '../../models/review.dart';
import '../common/label_chip.dart';

/// Variable-height comment card used outside the virtualized diff
/// (comments tab, finalization screen). Dismissed comments render muted.
class CommentCard extends StatefulWidget {
  const CommentCard({
    super.key,
    required this.comment,
    required this.labels,
    required this.locations,
    required this.onCopy,
    required this.onToggleDismissed,
    required this.onEdit,
    required this.onDelete,
    this.onTap,
    this.alsoIn,
    this.snippet,
    this.maxLines = 4,
  });

  final ReviewComment comment;
  final List<ReviewLabel> labels;
  final String locations;
  final String? alsoIn;
  final Widget? snippet;
  final int? maxLines;
  final VoidCallback? onTap;
  final VoidCallback onCopy;
  final VoidCallback onToggleDismissed;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<CommentCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.comment;
    final muted = theme.colorScheme.onSurfaceVariant;
    final dismissed = c.dismissed;
    final accent = dismissed
        ? theme.dividerColor
        : (widget.labels.isEmpty ? theme.colorScheme.primary : widget.labels.first.colorValue);

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (dismissed) const DismissedBadge(),
                    for (final l in widget.labels) LabelChip(label: l, dense: true),
                  ],
                ),
              ),
              _Action(icon: Icons.content_copy, tip: 'Copiar comentario', onTap: widget.onCopy, visible: true),
              _Action(
                icon: dismissed ? Icons.restore : Icons.block,
                tip: dismissed ? 'Restaurar' : 'Denegar',
                onTap: widget.onToggleDismissed,
                visible: _hover || dismissed,
              ),
              _Action(icon: Icons.edit_outlined, tip: 'Editar', onTap: widget.onEdit, visible: _hover),
              _Action(icon: Icons.delete_outline, tip: 'Eliminar', onTap: widget.onDelete, visible: _hover),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.locations,
            style: TextStyle(fontSize: 11.5, color: muted, fontWeight: FontWeight.w500),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (widget.alsoIn != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                widget.alsoIn!,
                style: TextStyle(fontSize: 11, color: muted, fontStyle: FontStyle.italic),
              ),
            ),
          if (widget.snippet != null) ...[const SizedBox(height: 8), widget.snippet!],
          const SizedBox(height: 6),
          Text(
            c.text.isEmpty ? '(sin texto)' : c.text,
            maxLines: widget.maxLines,
            overflow: widget.maxLines == null ? null : TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: dismissed ? muted : null,
              decoration: dismissed ? TextDecoration.lineThrough : null,
              decorationColor: muted,
            ),
          ),
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Opacity(
        opacity: dismissed ? 0.6 : 1,
        child: Material(
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: _hover ? theme.colorScheme.primary.withValues(alpha: 0.5) : theme.dividerColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 3, color: accent),
                  Expanded(child: body),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DismissedBadge extends StatelessWidget {
  const DismissedBadge({super.key, this.dense = true});
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7, vertical: dense ? 1 : 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: muted.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block, size: 11, color: muted),
          const SizedBox(width: 3),
          Text(
            'denegado',
            style: TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w600, height: 1.3),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.tip, required this.onTap, required this.visible});
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    // Keep the slot so hovering doesn't shift the layout.
    return Visibility(
      visible: visible,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(icon, size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
