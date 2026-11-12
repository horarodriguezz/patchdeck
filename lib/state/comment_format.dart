import '../models/label.dart';
import '../models/review.dart';

/// Plain-text formatting used by every "copy" action:
///
///     [bug, nit] src/a.ts L3-L5, L9 · styles/app.css L11: the comment text
///
/// Lines that only exist on the old side (deletions) are suffixed with
/// "(eliminada/s)". When [patchId] is given only that patch's anchors are
/// listed; otherwise anchors from several patches are prefixed with the
/// patch name.
String formatComment(
  ReviewComment c, {
  required ReviewLabel? Function(String) labelById,
  required Map<String, String> patchNames,
  String? patchId,
}) {
  final labels = [for (final id in c.labelIds) labelById(id)?.title].whereType<String>().toList();
  final b = StringBuffer();
  if (labels.isNotEmpty) b.write('[${labels.join(', ')}] ');
  final locs = describeLocations(c.anchors, patchNames: patchNames, patchId: patchId);
  if (locs.isNotEmpty) b.write(locs);
  b.write(': ');
  b.write(c.text.trim());
  return b.toString();
}

/// Joins comments with a blank line, skipping dismissed ones.
String formatComments(
  Iterable<ReviewComment> comments, {
  required ReviewLabel? Function(String) labelById,
  required Map<String, String> patchNames,
  String? patchId,
}) =>
    [
      for (final c in comments)
        if (!c.dismissed) formatComment(c, labelById: labelById, patchNames: patchNames, patchId: patchId),
    ].join('\n\n');

String describeLocations(List<LineAnchor> anchors, {required Map<String, String> patchNames, String? patchId}) {
  final byPatch = <String, Map<String, List<LineAnchor>>>{};
  for (final a in anchors) {
    if (patchId != null && a.patchId != patchId) continue;
    (byPatch.putIfAbsent(a.patchId, () => {})[a.path] ??= []).add(a);
  }
  final multiPatch = byPatch.length > 1;
  final parts = <String>[];
  byPatch.forEach((pid, files) {
    final fileParts = [for (final e in files.entries) '${e.key} ${lineRanges(e.value)}'];
    final joined = fileParts.join(' · ');
    parts.add(multiPatch ? '${patchNames[pid] ?? '?'}: $joined' : joined);
  });
  return parts.join(' | ');
}

/// "L3-L5, L9" for new-side lines, "L7-L8 (eliminadas)" for deleted lines.
String lineRanges(List<LineAnchor> anchors) {
  final news = <int>{for (final a in anchors) if (a.newLine != null) a.newLine!}.toList()..sort();
  final olds = <int>{for (final a in anchors) if (a.newLine == null && a.oldLine != null) a.oldLine!}.toList()..sort();
  final out = <String>[];
  if (news.isNotEmpty) out.add(_compress(news));
  if (olds.isNotEmpty) out.add('${_compress(olds)} (${olds.length == 1 ? 'eliminada' : 'eliminadas'})');
  return out.join(', ');
}

String _compress(List<int> v) {
  final parts = <String>[];
  for (var i = 0; i < v.length;) {
    var j = i;
    while (j + 1 < v.length && v[j + 1] == v[j] + 1) {
      j++;
    }
    parts.add(i == j ? 'L${v[i]}' : 'L${v[i]}-L${v[j]}');
    i = j + 1;
  }
  return parts.join(', ');
}
