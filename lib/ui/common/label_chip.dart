import 'package:flutter/material.dart';

import '../../models/label.dart';

/// GitHub-style pill. Text color is chosen for contrast with the label color.
class LabelChip extends StatelessWidget {
  const LabelChip({
    super.key,
    required this.label,
    this.onDeleted,
    this.dense = false,
    this.onTap,
    this.outlined = false,
  });

  final ReviewLabel label;
  final VoidCallback? onDeleted;
  final VoidCallback? onTap;
  final bool dense;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final c = label.colorValue;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = outlined ? Colors.transparent : c.withValues(alpha: dark ? 0.22 : 0.16);
    final fg = dark ? Color.lerp(c, Colors.white, 0.35)! : Color.lerp(c, Colors.black, 0.35)!;
    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 9, vertical: dense ? 1 : 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: dense ? 11 : 12, fontWeight: FontWeight.w600, height: 1.3),
            ),
          ),
          if (onDeleted != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onDeleted,
              child: Icon(Icons.close, size: dense ? 12 : 14, color: fg),
            ),
          ],
        ],
      ),
    );
    final withTip = label.description.isEmpty ? chip : Tooltip(message: label.description, child: chip);
    return onTap == null
        ? withTip
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(onTap: onTap, child: withTip),
          );
  }
}
