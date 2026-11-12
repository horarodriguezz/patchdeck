import 'package:flutter/material.dart';

/// Thin draggable horizontal scrollbar bound to a plain offset notifier
/// (the diff's code columns scroll horizontally without a Scrollable so the
/// two sides of the split view always move together).
class HScrollBar extends StatelessWidget {
  const HScrollBar({super.key, required this.offset, required this.maxOffset, required this.viewport});

  final ValueNotifier<double> offset;
  final double maxOffset;

  /// Visible code width, used to size the thumb.
  final double viewport;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return LayoutBuilder(
      builder: (context, c) {
        final track = c.maxWidth;
        final content = viewport + maxOffset;
        final thumb = (track * viewport / content).clamp(32.0, track);
        final travel = track - thumb;
        return ValueListenableBuilder<double>(
          valueListenable: offset,
          builder: (context, x, _) {
            final left = maxOffset <= 0 ? 0.0 : travel * (x / maxOffset);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                // Page towards the click.
                final dir = d.localPosition.dx < left ? -1 : (d.localPosition.dx > left + thumb ? 1 : 0);
                offset.value = (x + dir * viewport * 0.9).clamp(0.0, maxOffset);
              },
              onHorizontalDragUpdate: (d) {
                if (travel <= 0) return;
                offset.value = (offset.value + d.delta.dx * maxOffset / travel).clamp(0.0, maxOffset);
              },
              child: SizedBox(
                height: 12,
                child: Stack(
                  children: [
                    Positioned(
                      left: left,
                      width: thumb,
                      top: 3,
                      bottom: 3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

final Map<(String, double), double> _charWidthCache = {};

/// Real advance width of one monospace character for [style].
double monoCharWidth(TextStyle style) {
  final key = (style.fontFamily ?? '', style.fontSize ?? 14);
  return _charWidthCache.putIfAbsent(key, () {
    final tp = TextPainter(
      text: TextSpan(text: 'MMMMMMMMMMMMMMMMMMMM', style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final w = tp.width / 20;
    tp.dispose();
    return w;
  });
}
