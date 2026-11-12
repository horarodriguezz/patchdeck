import 'package:flutter/material.dart';

import '../../diff/diff_layout.dart';
import '../../diff/diff_models.dart';
import '../../state/patch_model.dart';
import '../../theme/app_themes.dart';
import '../../theme/diff_theme.dart';
import '../diff/code_text.dart';

/// Read-only excerpt of the lines a comment points at, grouped by file.
/// Non-contiguous lines are separated by a "⋯" row.
class CodeSnippet extends StatelessWidget {
  const CodeSnippet({super.key, required this.model, required this.keys, this.maxLinesPerFile = 8});

  final PatchModel model;
  final List<LineKey> keys;
  final int maxLinesPerFile;

  @override
  Widget build(BuildContext context) {
    final t = context.diffTheme;
    final style = TextStyle(fontFamily: monoFamily, fontFamilyFallback: monoFallback, fontSize: 12, height: 1.25);
    final byFile = <int, List<LineKey>>{};
    for (final k in keys) {
      (byFile[k.$2] ??= []).add(k);
    }
    final files = byFile.keys.toList()..sort();
    final children = <Widget>[];
    for (final f in files) {
      final ks = byFile[f]!..sort((a, b) => a.$3 != b.$3 ? a.$3.compareTo(b.$3) : a.$4.compareTo(b.$4));
      {
        children.add(Container(
          color: t.fileHeaderBg,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(model.parsed.files[f].displayPath,
              style: style.copyWith(fontSize: 11, color: t.hunkFg), maxLines: 1, overflow: TextOverflow.ellipsis),
        ));
      }
      LineKey? prev;
      for (final k in ks.take(maxLinesPerFile)) {
        if (prev != null && (prev.$3 != k.$3 || k.$4 - prev.$4 > 1)) {
          children.add(Container(
            color: t.hunkBg,
            padding: const EdgeInsets.only(left: 8),
            height: 16,
            alignment: Alignment.centerLeft,
            child: Text('⋯', style: style.copyWith(color: t.hunkFg, fontSize: 11)),
          ));
        }
        children.add(_line(model.lineFor(k), style, t));
        prev = k;
      }
      if (ks.length > maxLinesPerFile) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
          child: Text('+${ks.length - maxLinesPerFile} líneas más', style: style.copyWith(fontSize: 11, color: t.lineNoFg)),
        ));
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.codeBg,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }

  Widget _line(DiffLine l, TextStyle style, DiffTheme t) {
    final (bg, sign) = switch (l.kind) {
      LineKind.add => (t.addBg, '+'),
      LineKind.del => (t.delBg, '-'),
      _ => (t.codeBg, ' '),
    };
    final no = l.newNo ?? l.oldNo;
    return Container(
      color: bg,
      height: 19,
      child: Row(children: [
        SizedBox(
          width: 44,
          child: Text(no == null ? '' : '$no', textAlign: TextAlign.right, style: style.copyWith(color: t.lineNoFg)),
        ),
        SizedBox(width: 18, child: Text(' $sign', style: style.copyWith(color: t.lineNoFg))),
        Expanded(
          child: RichText(
            text: buildCodeSpan(l, style.copyWith(color: t.codeFg), t.tokenColors),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
          ),
        ),
      ]),
    );
  }
}
