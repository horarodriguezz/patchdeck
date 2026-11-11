import 'dart:typed_data';

import '../models/app_settings.dart';
import 'diff_models.dart';

/// Identity of a rendered line inside one patch: (patchId, file, hunk, line).
typedef LineKey = (String, int, int, int);

enum RowKind { preamble, fileHeader, notice, hunk, line, comment, gap }

/// Which column of a split row a gutter belongs to. Unified rows use [left].
enum Side { left, right }

/// One virtualized row. In unified mode [a] is the line index inside the hunk;
/// in split mode [a] is the left (old) line and [b] the right (new) line, -1 if empty.
class DiffRow {
  const DiffRow(this.kind, this.file, {this.hunk = -1, this.a = -1, this.b = -1, this.commentId});

  final RowKind kind;
  final int file;
  final int hunk;
  final int a;
  final int b;
  final String? commentId;
}

class DiffMetrics {
  DiffMetrics(this.fontSize)
      : lineHeight = (fontSize * 1.55).roundToDouble(),
        charWidth = fontSize * 0.6;

  final double fontSize;
  final double lineHeight;
  final double charWidth;

  static const double fileHeader = 42;
  static const double notice = 40;
  static const double comment = 88;
  static const double gap = 14;
  static const int maxPreambleLines = 14;

  double get hunk => lineHeight + 8;

  double preamble(int lines) => lines.clamp(1, maxPreambleLines) * lineHeight + 24;
}

/// Flattened list of rows plus prefix-summed offsets. Every row has a known
/// height so the list can use `itemExtentBuilder`: layout is O(visible rows)
/// and jumping to any file is a binary search, no matter how big the patch.
class DiffLayout {
  DiffLayout._(this.rows, this.offsets, this.fileRow, this.patchId, this.maxLineChars);

  final List<DiffRow> rows;
  final Float64List offsets; // offsets[i] = top of row i; offsets[rows.length] = total height.
  final Int32List fileRow; // row index of each file header
  final String patchId;
  final int maxLineChars;

  double extent(int i) => offsets[i + 1] - offsets[i];
  double get totalHeight => offsets[rows.length];

  /// Index of the row containing vertical position [y] (content coordinates).
  int indexAt(double y) {
    if (rows.isEmpty) return -1;
    var lo = 0, hi = rows.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (offsets[mid] <= y) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// The line keys a gutter at [side] of row [i] refers to (unified: one key).
  LineKey? keyAt(int i, Side side, DiffMode mode) {
    final r = rows[i];
    if (r.kind != RowKind.line) return null;
    if (mode == DiffMode.unified) return (patchId, r.file, r.hunk, r.a);
    final idx = side == Side.left ? r.a : r.b;
    return idx < 0 ? null : (patchId, r.file, r.hunk, idx);
  }

  /// Line keys between rows [from] and [to] (inclusive) on [side], limited to
  /// the file of [from] (GitHub semantics: ranges never cross files).
  List<LineKey> keysInRange(int from, int to, Side side, DiffMode mode) {
    final lo = from < to ? from : to, hi = from < to ? to : from;
    final file = rows[from].file;
    final out = <LineKey>[];
    final seen = <LineKey>{};
    for (var i = lo; i <= hi; i++) {
      final r = rows[i];
      if (r.file != file || r.kind != RowKind.line) continue;
      final k = keyAt(i, side, mode);
      if (k != null && seen.add(k)) out.add(k);
    }
    return out;
  }
}

DiffLayout buildDiffLayout({
  required String patchId,
  required ParsedPatch patch,
  required DiffMode mode,
  required DiffMetrics metrics,
  required Set<int> collapsedFiles,
  required Map<LineKey, List<String>> commentsByLine,
}) {
  final rows = <DiffRow>[];
  final fileRow = Int32List(patch.files.length);
  var maxChars = 0;

  // Comments are inserted after the *last rendered* row that contains one of
  // their lines in each file; we need row positions first.
  final lastRowFor = <String, int>{}; // "commentId|file" -> row
  void noteLine(LineKey k, int row) {
    final ids = commentsByLine[k];
    if (ids == null) return;
    for (final id in ids) {
      final key = '$id|${k.$2}';
      final prev = lastRowFor[key];
      if (prev == null || prev < row) lastRowFor[key] = row;
    }
  }

  if (patch.preamble.isNotEmpty) rows.add(const DiffRow(RowKind.preamble, -1));

  for (var f = 0; f < patch.files.length; f++) {
    final file = patch.files[f];
    fileRow[f] = rows.length;
    rows.add(DiffRow(RowKind.fileHeader, f));
    if (!collapsedFiles.contains(f)) {
      if (file.isBinary || file.hunks.isEmpty) {
        rows.add(DiffRow(RowKind.notice, f));
      }
      for (var h = 0; h < file.hunks.length; h++) {
        final hunk = file.hunks[h];
        rows.add(DiffRow(RowKind.hunk, f, hunk: h));
        final lines = hunk.lines;
        for (final l in lines) {
          if (l.text.length > maxChars) maxChars = l.text.length;
        }
        if (mode == DiffMode.unified) {
          for (var i = 0; i < lines.length; i++) {
            noteLine((patchId, f, h, i), rows.length);
            rows.add(DiffRow(RowKind.line, f, hunk: h, a: i));
          }
        } else {
          var i = 0;
          while (i < lines.length) {
            final k = lines[i].kind;
            if (k == LineKind.noNewline) {
              i++;
              continue;
            }
            if (k == LineKind.context) {
              noteLine((patchId, f, h, i), rows.length);
              rows.add(DiffRow(RowKind.line, f, hunk: h, a: i, b: i));
              i++;
              continue;
            }
            // Pair a run of deletions with the following run of additions.
            final dels = <int>[], adds = <int>[];
            while (i < lines.length && (lines[i].kind == LineKind.del || lines[i].kind == LineKind.noNewline)) {
              if (lines[i].kind == LineKind.del) dels.add(i);
              i++;
            }
            while (i < lines.length && (lines[i].kind == LineKind.add || lines[i].kind == LineKind.noNewline)) {
              if (lines[i].kind == LineKind.add) adds.add(i);
              i++;
            }
            final n = dels.length > adds.length ? dels.length : adds.length;
            for (var j = 0; j < n; j++) {
              final a = j < dels.length ? dels[j] : -1;
              final b = j < adds.length ? adds[j] : -1;
              if (a >= 0) noteLine((patchId, f, h, a), rows.length);
              if (b >= 0) noteLine((patchId, f, h, b), rows.length);
              rows.add(DiffRow(RowKind.line, f, hunk: h, a: a, b: b));
            }
          }
        }
      }
    }
    rows.add(DiffRow(RowKind.gap, f));
  }

  // Splice comment rows in.
  var finalRows = rows;
  var finalFileRow = fileRow;
  if (lastRowFor.isNotEmpty) {
    final after = <int, List<String>>{};
    lastRowFor.forEach((key, row) => (after[row] ??= []).add(key.substring(0, key.lastIndexOf('|'))));
    finalRows = <DiffRow>[];
    finalFileRow = Int32List(patch.files.length);
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (r.kind == RowKind.fileHeader) finalFileRow[r.file] = finalRows.length;
      finalRows.add(r);
      final ids = after[i];
      if (ids != null) {
        for (final id in ids) {
          finalRows.add(DiffRow(RowKind.comment, r.file, commentId: id));
        }
      }
    }
  }

  final preambleLines = patch.preamble.isEmpty ? 0 : '\n'.allMatches(patch.preamble).length + 1;
  final offsets = Float64List(finalRows.length + 1);
  var y = 0.0;
  for (var i = 0; i < finalRows.length; i++) {
    offsets[i] = y;
    y += switch (finalRows[i].kind) {
      RowKind.preamble => metrics.preamble(preambleLines),
      RowKind.fileHeader => DiffMetrics.fileHeader,
      RowKind.notice => DiffMetrics.notice,
      RowKind.hunk => metrics.hunk,
      RowKind.line => metrics.lineHeight,
      RowKind.comment => DiffMetrics.comment,
      RowKind.gap => DiffMetrics.gap,
    };
  }
  offsets[finalRows.length] = y;
  return DiffLayout._(finalRows, offsets, finalFileRow, patchId, maxChars);
}
