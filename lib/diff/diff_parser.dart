import 'dart:convert';
import 'dart:isolate';

import 'diff_models.dart';
import 'syntax.dart';

/// Parses off the UI thread; large patches never cause jank.
Future<ParsedPatch> parsePatchAsync(String raw, {bool highlight = true}) {
  if (raw.length < 20000) return Future.value(parsePatch(raw, highlight: highlight));
  return Isolate.run(() => parsePatch(raw, highlight: highlight));
}

final RegExp _hunkRe = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@ ?(.*)$');

/// Parser for unified diffs as produced by `git diff`, `git show`,
/// `git format-patch` and plain `diff -u`.
ParsedPatch parsePatch(String raw, {bool highlight = true}) {
  final lines = const LineSplitter().convert(raw);
  final files = <DiffFile>[];
  final preamble = StringBuffer();

  _FileBuilder? file;
  _HunkBuilder? hunk;
  var oldLeft = 0, newLeft = 0;

  void closeHunk() {
    final h = hunk, f = file;
    if (h != null && f != null) f.hunks.add(h.build());
    hunk = null;
    oldLeft = newLeft = 0;
  }

  void closeFile() {
    closeHunk();
    final f = file;
    if (f != null) files.add(f.build(highlight));
    file = null;
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    // Inside a hunk the counters tell us exactly how many lines belong to it,
    // so content like "--- foo" in a removed line is never mistaken for a header.
    if (hunk != null && (oldLeft > 0 || newLeft > 0)) {
      final h = hunk!;
      final c = line.isEmpty ? ' ' : line[0];
      final text = line.isEmpty ? '' : _expandTabs(line.substring(1));
      switch (c) {
        case ' ':
          h.lines.add(DiffLine(LineKind.context, h.oldNo++, h.newNo++, text));
          oldLeft--;
          newLeft--;
          continue;
        case '-':
          h.lines.add(DiffLine(LineKind.del, h.oldNo++, null, text));
          file!.deletions++;
          oldLeft--;
          continue;
        case '+':
          h.lines.add(DiffLine(LineKind.add, null, h.newNo++, text));
          file!.additions++;
          newLeft--;
          continue;
        case '\\':
          h.lines.add(const DiffLine(LineKind.noNewline, null, null, 'No newline at end of file'));
          continue;
        default:
          closeHunk(); // malformed counts: fall through to header handling
      }
    } else if (hunk != null && line.startsWith('\\')) {
      hunk!.lines.add(const DiffLine(LineKind.noNewline, null, null, 'No newline at end of file'));
      continue;
    }

    if (line.startsWith('diff --git ')) {
      closeFile();
      final paths = _splitGitPaths(line.substring(11));
      file = _FileBuilder(paths.$1, paths.$2);
      continue;
    }
    if (line.startsWith('@@ ') && file != null) {
      closeHunk();
      final m = _hunkRe.firstMatch(line);
      if (m == null) continue;
      final os = int.parse(m[1]!), ns = int.parse(m[3]!);
      oldLeft = m[2] == null ? 1 : int.parse(m[2]!);
      newLeft = m[4] == null ? 1 : int.parse(m[4]!);
      hunk = _HunkBuilder(line, os, ns, m[5] ?? '');
      continue;
    }
    if (line.startsWith('--- ') && i + 1 < lines.length && lines[i + 1].startsWith('+++ ')) {
      final oldP = _stripPrefix(line.substring(4));
      final newP = _stripPrefix(lines[i + 1].substring(4));
      if (file == null || file!.hunks.isNotEmpty || hunk != null) {
        // Plain `diff -u` without a `diff --git` header.
        closeFile();
        file = _FileBuilder(oldP ?? newP ?? '', newP ?? oldP ?? '');
      }
      if (oldP == null) file!.status = FileStatus.added;
      if (newP == null) file!.status = FileStatus.deleted;
      if (oldP != null) file!.oldPath = oldP;
      if (newP != null) file!.newPath = newP;
      i++;
      continue;
    }
    final f = file;
    if (f != null && hunk == null) {
      if (line.startsWith('new file mode')) {
        f.status = FileStatus.added;
        continue;
      }
      if (line.startsWith('deleted file mode')) {
        f.status = FileStatus.deleted;
        continue;
      }
      if (line.startsWith('rename from ')) {
        f.status = FileStatus.renamed;
        f.oldPath = line.substring(12);
        continue;
      }
      if (line.startsWith('rename to ')) {
        f.status = FileStatus.renamed;
        f.newPath = line.substring(10);
        continue;
      }
      if (line.startsWith('copy from ')) {
        f.status = FileStatus.copied;
        f.oldPath = line.substring(10);
        continue;
      }
      if (line.startsWith('copy to ')) {
        f.status = FileStatus.copied;
        f.newPath = line.substring(8);
        continue;
      }
      if (line.startsWith('Binary files ') || line.startsWith('GIT binary patch')) {
        f.isBinary = true;
        continue;
      }
      if (line.startsWith('index ') ||
          line.startsWith('similarity index') ||
          line.startsWith('dissimilarity index') ||
          line.startsWith('old mode') ||
          line.startsWith('new mode')) {
        continue;
      }
      if (f.isBinary) continue; // binary payload
    }
    // Everything else: commit headers / messages / signature.
    if (file != null) closeFile();
    if (line == '-- ' || (preamble.isEmpty && line.trim().isEmpty)) continue;
    if (_isGitVersionLine(line, i, lines)) continue;
    preamble.writeln(line);
  }
  closeFile();
  return ParsedPatch(preamble: preamble.toString().trimRight(), files: files);
}

bool _isGitVersionLine(String line, int i, List<String> lines) =>
    i > 0 && lines[i - 1] == '-- ' && RegExp(r'^\d+\.\d+').hasMatch(line);

String? _stripPrefix(String p) {
  var s = p;
  final tab = s.indexOf('\t');
  if (tab >= 0) s = s.substring(0, tab);
  if (s.startsWith('"') && s.endsWith('"') && s.length > 1) s = s.substring(1, s.length - 1);
  if (s == '/dev/null') return null;
  if (s.startsWith('a/') || s.startsWith('b/')) return s.substring(2);
  return s;
}

(String, String) _splitGitPaths(String rest) {
  // "a/foo b/foo" – paths may contain spaces; the halves are usually equal.
  final mid = rest.indexOf(' b/');
  if (mid > 0) {
    return (_stripPrefix(rest.substring(0, mid)) ?? '', _stripPrefix(rest.substring(mid + 1)) ?? '');
  }
  final parts = rest.split(' ');
  return (_stripPrefix(parts.first) ?? '', _stripPrefix(parts.last) ?? '');
}

String _expandTabs(String s) {
  if (!s.contains('\t')) return s;
  final b = StringBuffer();
  var col = 0;
  for (final ch in s.runes) {
    if (ch == 9) {
      final n = 4 - col % 4;
      b.write(' ' * n);
      col += n;
    } else {
      b.writeCharCode(ch);
      col++;
    }
  }
  return b.toString();
}

class _HunkBuilder {
  _HunkBuilder(this.header, this.oldNo, this.newNo, this.section)
      : oldStart = oldNo,
        newStart = newNo;
  final String header;
  final int oldStart;
  final int newStart;
  final String section;
  int oldNo;
  int newNo;
  final List<DiffLine> lines = [];

  DiffHunk build() =>
      DiffHunk(header: header, oldStart: oldStart, newStart: newStart, section: section, lines: lines);
}

class _FileBuilder {
  _FileBuilder(this.oldPath, this.newPath);
  String oldPath;
  String newPath;
  FileStatus status = FileStatus.modified;
  bool isBinary = false;
  int additions = 0;
  int deletions = 0;
  final List<DiffHunk> hunks = [];

  DiffFile build(bool highlight) {
    var finalHunks = hunks;
    final lang = highlight ? languageForPath(status == FileStatus.deleted ? oldPath : newPath) : null;
    if (lang != null) finalHunks = [for (final h in hunks) _highlightHunk(h, lang)];
    return DiffFile(
      oldPath: oldPath,
      newPath: newPath,
      status: status,
      isBinary: isBinary,
      hunks: finalHunks,
      additions: additions,
      deletions: deletions,
    );
  }
}

/// Tokenizes the old and new streams of a hunk separately so multi-line
/// constructs (block comments, template strings) keep their state per side.
DiffHunk _highlightHunk(DiffHunk h, SyntaxLanguage lang) {
  var oldState = 0, newState = 0;
  final out = <DiffLine>[];
  for (final l in h.lines) {
    if (l.kind == LineKind.noNewline) {
      out.add(l);
      continue;
    }
    final res = tokenizeLine(l.text, lang, l.kind == LineKind.del ? oldState : newState);
    switch (l.kind) {
      case LineKind.context:
        newState = res.state;
        // Re-tokenizing for the old side would almost always yield the same
        // result; keep the streams in sync cheaply.
        oldState = res.state;
      case LineKind.add:
        newState = res.state;
      case LineKind.del:
        oldState = res.state;
      case LineKind.noNewline:
        break;
    }
    out.add(DiffLine(l.kind, l.oldNo, l.newNo, l.text, res.spans));
  }
  return DiffHunk(header: h.header, oldStart: h.oldStart, newStart: h.newStart, section: h.section, lines: out);
}
