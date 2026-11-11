import '../models/label.dart';
import '../models/review.dart';

/// Renders the review (context, comments, notes) as Markdown for sharing.
String exportReviewMarkdown(Review review, ReviewLabel? Function(String) labelById) {
  final b = StringBuffer('# ${review.title}\n\n');
  final patchName = {for (final p in review.patches) p.id: p.name};

  if (review.contextMarkdown.trim().isNotEmpty) {
    b.writeln('## Contexto\n\n${review.contextMarkdown.trim()}\n');
  }
  if (review.comments.isNotEmpty) {
    b.writeln('## Comentarios\n');
    for (final c in review.comments) {
      final labels = [for (final id in c.labelIds) labelById(id)?.title].whereType<String>();
      b.write('- ');
      if (labels.isNotEmpty) b.write('${labels.map((l) => '`$l`').join(' ')} ');
      b.writeln(c.text.replaceAll('\n', '\n  '));
      for (final loc in describeAnchors(c.anchors, patchName)) {
        b.writeln('  - $loc');
      }
    }
    b.writeln();
  }
  if (review.notesMarkdown.trim().isNotEmpty) {
    b.writeln('## Notas\n\n${review.notesMarkdown.trim()}\n');
  }
  return b.toString();
}

/// "A: src/foo.ts L10-L14, L20" style descriptions, grouped by patch + file.
List<String> describeAnchors(List<LineAnchor> anchors, Map<String, String> patchName) {
  final groups = <String, List<int>>{};
  final labels = <String, String>{};
  for (final a in anchors) {
    final key = '${a.patchId}|${a.path}';
    labels[key] = '${patchName[a.patchId] ?? '?'}: `${a.path}`';
    groups.putIfAbsent(key, () => []).add(a.newLine ?? -(a.oldLine ?? 0));
  }
  return [
    for (final e in groups.entries) '${labels[e.key]} ${_ranges(e.value)}',
  ];
}

String _ranges(List<int> lines) {
  // Positive = new-side line, negative = old-side (deleted) line.
  final news = lines.where((l) => l > 0).toList()..sort();
  final olds = lines.where((l) => l < 0).map((l) => -l).toList()..sort();
  String fmt(List<int> v, String p) {
    final parts = <String>[];
    for (var i = 0; i < v.length;) {
      var j = i;
      while (j + 1 < v.length && v[j + 1] <= v[j] + 1) {
        j++;
      }
      parts.add(i == j ? '$p${v[i]}' : '$p${v[i]}-$p${v[j]}');
      i = j + 1;
    }
    return parts.join(', ');
  }

  return [if (news.isNotEmpty) fmt(news, 'L'), if (olds.isNotEmpty) fmt(olds, 'L-')].join('; ');
}
