import 'package:flutter/material.dart';

/// A collapsible, resizable column. Collapsed it is a thin rail with a
/// vertical title; expanded it shows [child] with a draggable inner edge.
class SidePanel extends StatefulWidget {
  const SidePanel({
    super.key,
    required this.title,
    required this.icon,
    required this.open,
    required this.onToggle,
    required this.child,
    required this.side,
    this.initialWidth = 340,
  });

  final String title;
  final IconData icon;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;
  final AxisDirection side; // left or right
  final double initialWidth;

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  late double _width = widget.initialWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLeft = widget.side == AxisDirection.left;
    final border = BorderSide(color: theme.dividerColor);
    final decoration = BoxDecoration(
      color: theme.colorScheme.surface,
      border: isLeft ? Border(right: border) : Border(left: border),
    );

    if (!widget.open) {
      return Container(
        width: 38,
        decoration: decoration,
        child: InkWell(
          onTap: widget.onToggle,
          child: Column(children: [
            const SizedBox(height: 8),
            Icon(widget.icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            RotatedBox(
              quarterTurns: isLeft ? 3 : 1,
              child: Text(widget.title, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12, letterSpacing: 0.5)),
            ),
          ]),
        ),
      );
    }

    final handle = MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => setState(() {
          final max = MediaQuery.sizeOf(context).width * 0.45;
          _width = (_width + (isLeft ? d.delta.dx : -d.delta.dx)).clamp(220.0, max < 240 ? 240.0 : max);
        }),
        child: const SizedBox(width: 6),
      ),
    );

    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 36,
        child: Row(children: [
          const SizedBox(width: 12),
          Icon(widget.icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          IconButton(
            tooltip: 'Colapsar',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            icon: Icon(isLeft ? Icons.keyboard_double_arrow_left : Icons.keyboard_double_arrow_right),
            onPressed: widget.onToggle,
          ),
        ]),
      ),
      const Divider(),
      Expanded(child: widget.child),
    ]);

    return Container(
      width: _width,
      decoration: decoration,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!isLeft) handle,
        Expanded(child: content),
        if (isLeft) handle,
      ]),
    );
  }
}
