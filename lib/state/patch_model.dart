import '../diff/diff_layout.dart';
import '../diff/diff_models.dart';
import '../models/review.dart';

/// A parsed patch plus bidirectional maps between [LineKey]s (positions in
/// the parsed structure) and persisted [LineAnchor]s.
class PatchModel {
  PatchModel(this.entry, this.parsed) {
    for (var f = 0; f < parsed.files.length; f++) {
      final file = parsed.files[f];
      for (var h = 0; h < file.hunks.length; h++) {
        final lines = file.hunks[h].lines;
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].kind == LineKind.noNewline) continue;
          _keyByAnchor[_anchor(file, lines[i]).key] = (entry.id, f, h, i);
        }
      }
    }
  }

  PatchEntry entry;
  final ParsedPatch parsed;
  final Map<String, LineKey> _keyByAnchor = {};

  String get id => entry.id;

  LineAnchor _anchor(DiffFile file, DiffLine l) => LineAnchor(
        patchId: entry.id,
        path: file.path,
        oldLine: l.kind == LineKind.add ? null : l.oldNo,
        newLine: l.kind == LineKind.del ? null : l.newNo,
      );

  LineAnchor anchorFor(LineKey k) {
    final file = parsed.files[k.$2];
    return _anchor(file, file.hunks[k.$3].lines[k.$4]);
  }

  LineKey? keyFor(LineAnchor a) => _keyByAnchor[a.key];

  DiffLine lineFor(LineKey k) => parsed.files[k.$2].hunks[k.$3].lines[k.$4];
}
