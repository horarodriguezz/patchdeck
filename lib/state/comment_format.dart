import '../models/label.dart';
import '../models/review.dart';

/// Default copy template (Settings → Copiar comentarios).
const String defaultCopyTemplate = '{{fileName + lines}}:  {{commentText}}';

/// Variables a copy template can use, with a short description.
const List<(String, String)> copyTemplateVariables = [
  ('fileName + lines', 'nombre de archivo y líneas · greet.ts L2-L3'),
  ('filePath + lines', 'ruta y líneas · src/greet.ts L2-L3'),
  ('fileName', 'nombre de archivo · greet.ts'),
  ('filePath', 'ruta · src/greet.ts'),
  ('lines', 'sólo líneas · L2-L3'),
  ('commentText', 'texto del comentario'),
  ('commentTags', 'etiquetas · bug, nit'),
  ('patchName', 'nombre del patch · A'),
];

final RegExp _var = RegExp(r'\{\{\s*([^}]*?)\s*\}\}');

/// Formats [c] with a user template such as `{{fileName + lines}}:  {{commentText}}`.
///
/// Text outside `{{…}}` is copied as is. Spaces inside the braces are
/// ignored (`{{fileName+lines}}` works too) and unknown variables are kept
/// verbatim. Several files are joined with " · "; when [patchId] is null and
/// the comment spans several patches, locations are prefixed with the patch.
String formatComment(
  ReviewComment c, {
  required ReviewLabel? Function(String) labelById,
  required Map<String, String> patchNames,
  String? patchId,
  String template = defaultCopyTemplate,
}) {
  final anchors = [
    for (final a in c.anchors)
      if (patchId == null || a.patchId == patchId) a,
  ];
  final byPatch = <String, Map<String, List<LineAnchor>>>{};
  for (final a in anchors) {
    (byPatch.putIfAbsent(a.patchId, () => {})[a.path] ??= []).add(a);
  }
  final multiPatch = byPatch.length > 1;

  String locations(String Function(String path, List<LineAnchor> lines) fileFmt) {
    final parts = <String>[];
    byPatch.forEach((pid, files) {
      final joined = [for (final e in files.entries) fileFmt(e.key, e.value)].join(' · ');
      parts.add(multiPatch ? '${patchNames[pid] ?? '?'}: $joined' : joined);
    });
    return parts.join(' | ');
  }

  String baseName(String p) => p.split('/').last;
  final values = <String, String Function()>{
    'filename+lines': () => locations((p, l) => '${baseName(p)} ${lineRanges(l)}'),
    'filepath+lines': () => locations((p, l) => '$p ${lineRanges(l)}'),
    'filename': () => locations((p, _) => baseName(p)),
    'filepath': () => locations((p, _) => p),
    'lines': () => locations((_, l) => lineRanges(l)),
    'commenttext': () => c.text.trim(),
    'commenttags': () => [for (final id in c.labelIds) labelById(id)?.title].whereType<String>().join(', '),
    'patchname': () => [for (final pid in byPatch.keys) patchNames[pid] ?? '?'].join(', '),
  };
  return template.replaceAllMapped(_var, (m) {
    final key = m[1]!.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return values[key]?.call() ?? m[0]!;
  }).trim();
}

/// Joins comments with a blank line, skipping dismissed ones.
String formatComments(
  Iterable<ReviewComment> comments, {
  required ReviewLabel? Function(String) labelById,
  required Map<String, String> patchNames,
  String? patchId,
  String template = defaultCopyTemplate,
}) => [
  for (final c in comments)
    if (!c.dismissed)
      formatComment(c, labelById: labelById, patchNames: patchNames, patchId: patchId, template: template),
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
  final news = <int>{
    for (final a in anchors)
      if (a.newLine != null) a.newLine!,
  }.toList()..sort();
  final olds = <int>{
    for (final a in anchors)
      if (a.newLine == null && a.oldLine != null) a.oldLine!,
  }.toList()..sort();
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
