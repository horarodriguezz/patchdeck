import 'package:flutter/material.dart';

import '../../diff/diff_models.dart';
import '../../diff/syntax.dart';
import '../../theme/app_themes.dart';
import '../diff/code_text.dart';

/// Tiny diff rendered with a theme's own colors (not the current theme's),
/// so the preview shows exactly what picking it will look like.
class ThemePreview extends StatelessWidget {
  const ThemePreview({super.key, required this.spec, required this.fontSize});
  final AppThemeSpec spec;
  final double fontSize;

  static const _lines = [
    (LineKind.context, 1, 'function greet(name: string) {'),
    (LineKind.del, 2, '  return "Hello, " + name;'),
    (LineKind.add, 2, '  return `Hello, \${name}!`;'),
    (LineKind.context, 3, '}'),
  ];

  @override
  Widget build(BuildContext context) {
    final d = spec.diff;
    final style = TextStyle(fontFamily: monoFamily, fontFamilyFallback: monoFallback, fontSize: fontSize, height: 1.25);
    return Container(
      decoration: BoxDecoration(
        color: d.codeBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: d.border),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final (kind, no, text) in _lines) _row(kind, no, text, style)],
      ),
    );
  }

  Widget _row(LineKind kind, int no, String text, TextStyle style) {
    final d = spec.diff;
    final spans = tokenizeLine(text, SyntaxLanguage.js, 0).spans;
    final line = DiffLine(kind, no, no, text, spans);
    final (bg, bar) = switch (kind) {
      LineKind.add => (d.addBg, d.addGutterBg),
      LineKind.del => (d.delBg, d.delGutterBg),
      _ => (Colors.transparent, Colors.transparent),
    };
    return Container(
      color: bg,
      height: fontSize * 1.7,
      child: Row(
        children: [
          Container(width: 3, color: bar),
          SizedBox(
            width: 40,
            child: Text(
              '$no',
              textAlign: TextAlign.right,
              style: style.copyWith(color: d.lineNoFg),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: RichText(
              maxLines: 1,
              softWrap: false,
              text: buildCodeSpan(line, style.copyWith(color: d.codeFg), d.tokenColors),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small two-tone swatch for theme pickers.
class ThemeSwatch extends StatelessWidget {
  const ThemeSwatch({super.key, required this.spec});
  final AppThemeSpec spec;

  @override
  Widget build(BuildContext context) => Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: spec.border),
      gradient: LinearGradient(
        colors: [spec.background, spec.background, spec.primary, spec.primary],
        stops: const [0, 0.5, 0.5, 1],
      ),
    ),
  );
}
