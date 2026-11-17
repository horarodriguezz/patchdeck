import 'package:flutter/material.dart';

enum GlyphKind { chevronUp, chevronDown, close, check }

/// Tiny stroked glyphs drawn with a painter, so they render the same on every
/// build regardless of the icon font. Color comes from the ambient [IconTheme].
class Glyph extends StatelessWidget {
  const Glyph(this.kind, {super.key, this.size = 16, this.color, this.stroke = 1.6});

  final GlyphKind kind;
  final double size;
  final Color? color;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _GlyphPainter(kind, c, stroke)),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.kind, this.color, this.stroke);
  final GlyphKind kind;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = s.width, h = s.height;
    final path = Path();
    switch (kind) {
      case GlyphKind.chevronUp:
        path
          ..moveTo(w * 0.25, h * 0.62)
          ..lineTo(w * 0.5, h * 0.37)
          ..lineTo(w * 0.75, h * 0.62);
      case GlyphKind.chevronDown:
        path
          ..moveTo(w * 0.25, h * 0.38)
          ..lineTo(w * 0.5, h * 0.63)
          ..lineTo(w * 0.75, h * 0.38);
      case GlyphKind.close:
        path
          ..moveTo(w * 0.28, h * 0.28)
          ..lineTo(w * 0.72, h * 0.72)
          ..moveTo(w * 0.72, h * 0.28)
          ..lineTo(w * 0.28, h * 0.72);
      case GlyphKind.check:
        path
          ..moveTo(w * 0.2, h * 0.52)
          ..lineTo(w * 0.42, h * 0.72)
          ..lineTo(w * 0.8, h * 0.3);
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.kind != kind || old.color != color || old.stroke != stroke;
}
