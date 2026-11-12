import '../models/label.dart';
import '../models/review.dart';
import 'comment_format.dart';

/// Active (non-dismissed) comments touching [patchId], in creation order.
List<ReviewComment> commentsForPatch(Review review, String patchId, {bool includeDismissed = false}) => [
  for (final c in review.comments)
    if ((includeDismissed || !c.dismissed) && c.anchors.any((a) => a.patchId == patchId)) c,
];

/// Plain-text copy of every active comment, grouped by patch.
String exportAllCommentsText(Review review, ReviewLabel? Function(String) labelById) {
  final names = {for (final p in review.patches) p.id: p.name};
  final sections = <String>[];
  for (final p in review.patches) {
    final text = formatComments(commentsForPatch(review, p.id), labelById: labelById, patchNames: names, patchId: p.id);
    if (text.isNotEmpty) sections.add('Patch ${p.name}\n\n$text');
  }
  return sections.join('\n\n');
}

/// Renders the review (context, comments per patch, notes) as Markdown.
String exportReviewMarkdown(Review review, ReviewLabel? Function(String) labelById) {
  final b = StringBuffer('# ${review.title}\n\n');
  final names = {for (final p in review.patches) p.id: p.name};

  if (review.contextMarkdown.trim().isNotEmpty) {
    b.writeln('## Contexto\n\n${review.contextMarkdown.trim()}\n');
  }
  for (final p in review.patches) {
    final comments = commentsForPatch(review, p.id);
    if (comments.isEmpty) continue;
    b.writeln('## Patch ${p.name}\n');
    for (final c in comments) {
      final labels = [for (final id in c.labelIds) labelById(id)?.title].whereType<String>();
      b.write('- ');
      if (labels.isNotEmpty) b.write('${labels.map((l) => '`$l`').join(' ')} ');
      b.writeln('**${describeLocations(c.anchors, patchNames: names, patchId: p.id)}**');
      b.writeln('  ${c.text.trim().replaceAll('\n', '\n  ')}');
    }
    b.writeln();
  }
  if (review.notesMarkdown.trim().isNotEmpty) {
    b.writeln('## Notas\n\n${review.notesMarkdown.trim()}\n');
  }
  return b.toString();
}
