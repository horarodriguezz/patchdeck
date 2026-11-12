import 'package:flutter/material.dart';

/// A collapsible, resizable column.
///
/// Opening/closing animates the width with an ease-out curve. The content is
/// laid out once at its full width and clipped while the panel slides, so
/// nothing reflows mid-animation; the collapsed rail cross-fades out.
class SidePanel extends StatefulWidget {
  const SidePanel({
    super.key,
    required this.open,
    required this.onToggle,
    required this.side,
    required this.header,
    required this.rail,
    required this.child,
    this.initialWidth = 340,
  });

  final bool open;
  final VoidCallback onToggle;
  final AxisDirection side; // left or right

  /// Shown at the top of the expanded panel (title or tabs).
  final Widget header;

  /// Content of the 38px collapsed rail.
  final Widget rail;
  final Widget child;
  final double initialWidth;

  static const double railWidth = 38;

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> with SingleTickerProviderStateMixin {
  late double _width = widget.initialWidth;
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 180),
    value: widget.open ? 1 : 0,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _anim,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void didUpdateWidget(SidePanel old) {
    super.didUpdateWidget(old);
    if (old.open != widget.open) {
      widget.open ? _anim.forward() : _anim.reverse();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLeft = widget.side == AxisDirection.left;
    final border = BorderSide(color: theme.dividerColor);
    final decoration = BoxDecoration(
      color: theme.colorScheme.surface,
      border: isLeft ? Border(right: border) : Border(left: border),
    );

    final handle = MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => setState(() {
          final max = MediaQuery.sizeOf(context).width * 0.45;
          _width = (_width + (isLeft ? d.delta.dx : -d.delta.dx)).clamp(240.0, max < 260 ? 260.0 : max);
        }),
        child: const SizedBox(width: 6),
      ),
    );

    final expanded = RepaintBoundary(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!isLeft) handle,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 40,
              child: Row(children: [
                Expanded(child: widget.header),
                IconButton(
                  tooltip: 'Colapsar',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: Icon(isLeft ? Icons.keyboard_double_arrow_left : Icons.keyboard_double_arrow_right),
                  onPressed: widget.onToggle,
                ),
                const SizedBox(width: 2),
              ]),
            ),
            const Divider(),
            Expanded(child: widget.child),
          ]),
        ),
        if (isLeft) handle,
      ]),
    );

    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) {
        final t = _curve.value;
        final width = SidePanel.railWidth + (_width - SidePanel.railWidth) * t;
        return Container(
          width: width,
          decoration: decoration,
          clipBehavior: Clip.hardEdge,
          child: Stack(children: [
            if (t > 0)
              Positioned.fill(
                child: OverflowBox(
                  alignment: isLeft ? Alignment.centerRight : Alignment.centerLeft,
                  minWidth: _width,
                  maxWidth: _width,
                  child: Opacity(opacity: Curves.easeIn.transform(t), child: expanded),
                ),
              ),
            if (t < 1)
              Positioned(
                top: 0,
                bottom: 0,
                left: isLeft ? 0 : null,
                right: isLeft ? null : 0,
                width: SidePanel.railWidth,
                child: IgnorePointer(
                  ignoring: t > 0,
                  child: Opacity(opacity: (1 - t * 2).clamp(0.0, 1.0), child: widget.rail),
                ),
              ),
          ]),
        );
      },
    );
  }
}

/// Default rail: an icon and the rotated title, tapping opens the panel.
class SimpleRail extends StatelessWidget {
  const SimpleRail({super.key, required this.icon, required this.title, required this.onTap, this.isLeft = true});

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isLeft;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Column(children: [
        const SizedBox(height: 10),
        Icon(icon, size: 18, color: muted),
        const SizedBox(height: 12),
        RotatedBox(
          quarterTurns: isLeft ? 3 : 1,
          child: Text(title, style: TextStyle(color: muted, fontSize: 12, letterSpacing: 0.5)),
        ),
      ]),
    );
  }
}

/// Small text header for panels without tabs.
class PanelTitle extends StatelessWidget {
  const PanelTitle({super.key, required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(children: [
        const SizedBox(width: 12),
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ]);
}
