import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../models/review.dart';
import '../../state/comment_format.dart';
import '../../state/workspace_controller.dart';
import 'comment_edit_dialog.dart';

/// Copy / dismiss / edit / delete behaviour shared by the comments tab, the
/// inline diff cards and the finalization screen.
class CommentActions {
  CommentActions(this.context, this.ws);

  final BuildContext context;
  final WorkspaceController ws;

  Map<String, String> get patchNames => {for (final p in ws.patches) p.id: p.name};

  String format(ReviewComment c, {String? patchId}) =>
      formatComment(c, labelById: AppScope.of(context).settings.labelById, patchNames: patchNames, patchId: patchId);

  void copyOne(ReviewComment c, {String? patchId}) => _copy(format(c, patchId: patchId), 'Comentario copiado');

  /// Copies the active comments of [patchId] separated by a blank line.
  void copyPatch(String patchId) {
    final name = ws.entry(patchId)?.name ?? '';
    final text = formatComments(
      ws.commentsInPatch(patchId, includeDismissed: false),
      labelById: AppScope.of(context).settings.labelById,
      patchNames: patchNames,
      patchId: patchId,
    );
    if (text.isEmpty) {
      _toast('El patch $name no tiene comentarios activos');
      return;
    }
    final n = ws.commentsInPatch(patchId, includeDismissed: false).length;
    _copy(text, '$n ${n == 1 ? 'comentario' : 'comentarios'} de $name copiados');
  }

  void copyText(String text, String message) => _copy(text, message);

  void toggleDismissed(ReviewComment c) {
    ws.setDismissed(c.id, !c.dismissed);
    _toast(c.dismissed ? 'Comentario restaurado' : 'Comentario denegado (no se copiará)');
  }

  Future<void> edit(ReviewComment c) async {
    final r = await showDialog<(List<String>, String)>(
      context: context,
      builder: (_) => CommentEditDialog(
        comment: c,
        locations: describeLocations(c.anchors, patchNames: patchNames),
      ),
    );
    if (r != null) ws.updateCommentContent(c.id, r.$1, r.$2);
  }

  void delete(ReviewComment c, {VoidCallback? afterDelete}) {
    final index = ws.comments.indexOf(c);
    ws.deleteComment(c.id);
    afterDelete?.call();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Comentario eliminado'),
          behavior: SnackBarBehavior.floating,
          width: 360,
          action: SnackBarAction(label: 'Deshacer', onPressed: () => ws.restoreComment(c, index)),
        ),
      );
  }

  void _copy(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    _toast(message);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          width: 380,
          duration: const Duration(seconds: 2),
        ),
      );
  }
}
