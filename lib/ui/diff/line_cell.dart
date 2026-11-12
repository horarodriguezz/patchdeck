import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../diff/diff_layout.dart';
import '../../diff/diff_models.dart';
import '../../theme/diff_theme.dart';
import 'code_text.dart';

typedef GutterDown = void Function(Side side);

/// One code line (unified) or one half of a split row.
///
/// The `+` button appears on hover; pressing it starts a selection that the
/// enclosing DiffView continues while the pointer is dragged.
class LineCell extends StatefulWidget {
  const LineCell({
    super.key,
    required this.line,
    required this.side,
    required this.showOld,
    required this.showNew,
    required this.selected,
    required this.commented,
    required this.numberWidth,
    required this.codeStyle,
    required this.onGutterDown,
    required this.hOffset,
  });

  /// Horizontal scroll of the code column (shared by both split sides).
  final ValueListenable<double> hOffset;

  /// Null renders an empty filler cell (split view without counterpart).
  final DiffLine? line;
  final Side side;
  final bool showOld;
  final bool showNew;
  final bool selected;
  final bool commented;
  final double numberWidth;
  final TextStyle codeStyle;
  final GutterDown onGutterDown;

  @override
  State<LineCell> createState() => _LineCellState();
}

class _LineCellState extends State<LineCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.diffTheme;
    final line = widget.line;
    if (line == null) return ColoredBox(color: t.emptyBg, child: const SizedBox.expand());

    final kind = line.kind;
    Color bg, gutterBg;
    String sign;
    switch (kind) {
      case LineKind.add:
        bg = t.addBg;
        gutterBg = t.addGutterBg;
        sign = '+';
      case LineKind.del:
        bg = t.delBg;
        gutterBg = t.delGutterBg;
        sign = '-';
      case LineKind.context:
        bg = t.codeBg;
        gutterBg = t.codeBg;
        sign = ' ';
      case LineKind.noNewline:
        bg = t.codeBg;
        gutterBg = t.codeBg;
        sign = ' ';
    }
    if (widget.selected) {
      bg = Color.alphaBlend(t.selectedBg, bg);
      gutterBg = t.selectedGutterBg;
    }
    final numStyle = widget.codeStyle.copyWith(color: t.lineNoFg);
    final selectable = kind != LineKind.noNewline;

    Widget number(int? n) => Container(
      width: widget.numberWidth,
      color: gutterBg,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 8),
      child: n == null ? null : Text('$n', style: numStyle, maxLines: 1),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: ColoredBox(
        color: bg,
        child: Row(
          children: [
            if (widget.showOld) number(line.oldNo),
            if (widget.showNew) number(line.newNo),
            // Gutter with the "+" handle.
            SizedBox(
              width: 22,
              child: selectable
                  ? Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (e) {
                        if (e.buttons == kPrimaryButton) widget.onGutterDown(widget.side);
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Center(
                          child: _PlusHandle(visible: _hover, commented: widget.commented),
                        ),
                      ),
                    )
                  : null,
            ),
            SizedBox(
              width: 14,
              child: Text(sign, style: widget.codeStyle.copyWith(color: t.lineNoFg)),
            ),
            Expanded(
              child: kind == LineKind.noNewline
                  ? Text(line.text, style: numStyle.copyWith(fontStyle: FontStyle.italic), maxLines: 1)
                  : ClipRect(
                      child: ValueListenableBuilder<double>(
                        valueListenable: widget.hOffset,
                        // Only the transform rebuilds on scroll; the text is laid out once.
                        builder: (context, x, child) => Transform.translate(offset: Offset(-x, 0), child: child),
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: 0,
                          maxWidth: double.infinity,
                          child: RichText(
                            text: buildCodeSpan(line, widget.codeStyle.copyWith(color: t.codeFg), t.tokenColors),
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlusHandle extends StatelessWidget {
  const _PlusHandle({required this.visible, required this.commented});
  final bool visible;
  final bool commented;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    if (visible) {
      return Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(4)),
        child: const Icon(Icons.add, size: 14, color: Colors.white),
      );
    }
    if (commented) {
      return Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
      );
    }
    return const SizedBox.shrink();
  }
}
