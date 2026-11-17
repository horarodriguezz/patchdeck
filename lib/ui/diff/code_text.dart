import 'package:flutter/material.dart';

import '../../diff/diff_models.dart';
import '../../diff/syntax.dart';
import '../../state/diff_search.dart';

/// Lines longer than this are truncated on screen (minified bundles can have
/// 100k+ chars per line; laying those out every frame would cause jank).
const int maxRenderedChars = 2000;

/// Builds the (optionally syntax-coloured) span of a code line. [marks]
/// paints search matches with [markBg] (or [currentBg] for the active one).
TextSpan buildCodeSpan(
  DiffLine line,
  TextStyle base,
  List<Color?> colors, {
  List<SearchMark>? marks,
  Color markBg = const Color(0x66F2CC60),
  Color currentBg = const Color(0xCCFF9632),
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

  if (marks == null || marks.isEmpty) {
    if (sp == null) return TextSpan(text: truncated ? '$text …' : text, style: base);
    return TextSpan(
      style: base,
      children: [
        for (final (s, e, st) in segs) TextSpan(text: text.substring(s, e), style: st),
        if (truncated) const TextSpan(text: ' …'),
      ],
    );
  }

  final children = <TextSpan>[];
  for (final (s, e, st) in segs) {
    var p = s;
    for (final m in marks) {
      if (m.end <= p || m.start >= e) continue;
      final ms = m.start < p ? p : m.start;
      final me = m.end > e ? e : m.end;
      if (ms > p) children.add(TextSpan(text: text.substring(p, ms), style: st));
      final bg = TextStyle(backgroundColor: m.current ? currentBg : markBg);
      children.add(TextSpan(text: text.substring(ms, me), style: st == null ? bg : st.merge(bg)));
      p = me;
    }
    if (p < e) children.add(TextSpan(text: text.substring(p, e), style: st));
  }
  if (truncated) children.add(const TextSpan(text: ' …'));
  return TextSpan(style: base, children: children);
}
