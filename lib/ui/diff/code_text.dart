import 'package:flutter/material.dart';

import '../../diff/diff_models.dart';
import '../../diff/syntax.dart';

/// Lines longer than this are truncated on screen (minified bundles can have
/// 100k+ chars per line; laying those out every frame would cause jank).
const int maxRenderedChars = 2000;

TextSpan buildCodeSpan(DiffLine line, TextStyle base, List<Color?> colors) {
  var text = line.text;
  final truncated = text.length > maxRenderedChars;
  if (truncated) text = text.substring(0, maxRenderedChars);
  final sp = line.spans;
  if (sp == null) {
    return TextSpan(text: truncated ? '$text …' : text, style: base);
  }
  final children = <TextSpan>[];
  var pos = 0;
  for (var i = 0; i + 2 < sp.length; i += 3) {
    final s = sp[i], k = sp[i + 2];
    var e = sp[i + 1];
    if (s >= text.length) break;
    if (e > text.length) e = text.length;
    if (s > pos) children.add(TextSpan(text: text.substring(pos, s)));
    children.add(TextSpan(
      text: text.substring(s, e),
      style: TextStyle(
        color: colors[k],
        fontStyle: k == TokenKind.comment ? FontStyle.italic : null,
      ),
    ));
    pos = e;
  }
  if (pos < text.length) children.add(TextSpan(text: text.substring(pos)));
  if (truncated) children.add(const TextSpan(text: ' …'));
  return TextSpan(style: base, children: children);
}
