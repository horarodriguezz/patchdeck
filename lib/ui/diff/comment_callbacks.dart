import '../../models/review.dart';

/// What the diff can do with an inline comment card.
class CommentCallbacks {
  const CommentCallbacks({required this.edit, required this.delete, required this.copy, required this.toggleDismissed});

  final void Function(ReviewComment) edit;
  final void Function(ReviewComment) delete;
  final void Function(ReviewComment, String patchId) copy;
  final void Function(ReviewComment) toggleDismissed;
}
