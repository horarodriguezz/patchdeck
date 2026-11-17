import 'package:flutter/material.dart';

import '../../diff/diff_models.dart';
import '../../diff/syntax.dart';
import '../../state/diff_search.dart';

/// Lines longer than this are truncated on screen (minified bundles can have
/// 100k+ chars per line; laying those out every frame would cause jank).
const int maxRenderedChars = 2000;

/// Builds the (optionally syntax-coloured) span of a code line. [marks]
/// paints search matches with [markBg] (or [currentBg] for the active one);
/// [selection] paints selected text with [selectionBg] (an end past the text
/// length means the line break is selected too).
TextSpan buildCodeSpan(
  DiffLine line,
  TextStyle base,
  List<Color?> colors, {
  List<SearchMark>? marks,
  Color markBg = const Color(0x66F2CC60),
  Color currentBg = const Color(0xCCFF9632),
  ({int start, int end})? selection,
  Color selectionBg = const Color(0x664D8DF7),
}) {
  var text = line.text;
  final truncated = text.length > maxRenderedChars;
  if (truncated) text = text.substring(0, maxRenderedChars);

  // Flatten into contiguous segments (start, end, style) covering the text.
  final segs = <(int, int, TextStyle?)>[];
  final sp = line.spans;
  var pos = 0;
  if (sp != null) {
    for (var i = 0; i + 2 < sp.length; i += 3) {
      final s = sp[i], k = sp[i + 2];
      var e = sp[i + 1];
      if (s >= text.length) break;
      if (e > text.length) e = text.length;
      if (s > pos) segs.add((pos, s, null));
      if (e > s) {
        segs.add((s, e, TextStyle(color: colors[k], fontStyle: k == TokenKind.comment ? FontStyle.italic : null)));
      }
      pos = e;
    }
  }
  if (pos < text.length) segs.add((pos, text.length, null));

  final sel = selection;
  if ((marks == null || marks.isEmpty) && sel == null) {
    if (sp == null) return TextSpan(text: truncated ? '$text …' : text, style: base);
    return TextSpan(
      style: base,
      children: [
        for (final (s, e, st) in segs) TextSpan(text: text.substring(s, e), style: st),
        if (truncated) const TextSpan(text: ' …'),
      ],
    );
  }

  // Cut the text at every syntax / match / selection boundary and style each
  // piece: syntax colour, plus a background for selection (wins) or matches.
  final cuts = <int>{0, text.length};
  for (final (s, e, _) in segs) {
    cuts
      ..add(s)
      ..add(e);
  }
  int clampTo(int v) => v < 0 ? 0 : (v > text.length ? text.length : v);
  for (final m in marks ?? const <SearchMark>[]) {
    cuts
      ..add(clampTo(m.start))
      ..add(clampTo(m.end));
  }
  if (sel != null) {
    cuts
      ..add(clampTo(sel.start))
      ..add(clampTo(sel.end));
  }
  final points = cuts.toList()..sort();
  final children = <TextSpan>[];
  var si = 0;
  for (var i = 0; i + 1 < points.length; i++) {
    final a = points[i], b = points[i + 1];
    if (a >= b) continue;
    while (si < segs.length && segs[si].$2 <= a) {
      si++;
    }
    final st = si < segs.length && segs[si].$1 <= a ? segs[si].$3 : null;
    Color? bg;
    if (sel != null && sel.start <= a && b <= sel.end) {
      bg = selectionBg;
    } else if (marks != null) {
      for (final m in marks) {
        if (m.start <= a && b <= m.end) {
          bg = m.current ? currentBg : markBg;
          break;
        }
      }
    }
    final style = bg == null ? st : (st ?? const TextStyle()).merge(TextStyle(backgroundColor: bg));
    children.add(TextSpan(text: text.substring(a, b), style: style));
  }
  if (truncated) children.add(const TextSpan(text: ' …'));
  // The line break itself is selected: show it as one highlighted cell.
  if (sel != null && sel.end > text.length) {
    children.add(
      TextSpan(
        text: ' ',
        style: TextStyle(backgroundColor: selectionBg),
      ),
    );
  }
  return TextSpan(style: base, children: children);
}
