import 'dart:typed_data';

enum LineKind { context, add, del, noNewline }

enum FileStatus { modified, added, deleted, renamed, copied }

class DiffLine {
  const DiffLine(this.kind, this.oldNo, this.newNo, this.text, [this.spans]);

  final LineKind kind;
  final int? oldNo;
  final int? newNo;
  final String text;

  /// Packed syntax tokens: `[start, end, kind, start, end, kind, ...]`.
  /// Null when the language is unknown or highlighting is off.
  final Int32List? spans;
}

class DiffHunk {
  DiffHunk({
    required this.header,
    required this.oldStart,
    required this.newStart,
    required this.section,
    required this.lines,
  });

  final String header;
  final int oldStart;
  final int newStart;
  final String section;
  final List<DiffLine> lines;
}

class DiffFile {
  DiffFile({
    required this.oldPath,
    required this.newPath,
    required this.status,
    required this.isBinary,
    required this.hunks,
    required this.additions,
    required this.deletions,
  });

  final String oldPath;
  final String newPath;
  final FileStatus status;
  final bool isBinary;
  final List<DiffHunk> hunks;
  final int additions;
  final int deletions;

  /// Path used for anchoring comments.
  String get path => status == FileStatus.deleted ? oldPath : newPath;

  String get displayPath => (status == FileStatus.renamed || status == FileStatus.copied) && oldPath != newPath
      ? '$oldPath → $newPath'
      : path;
}

class ParsedPatch {
  ParsedPatch({required this.preamble, required this.files});

  /// Text found outside of file sections (e.g. `git format-patch` headers
  /// and commit messages).
  final String preamble;
  final List<DiffFile> files;

  int get additions => files.fold(0, (a, f) => a + f.additions);
  int get deletions => files.fold(0, (a, f) => a + f.deletions);
}
