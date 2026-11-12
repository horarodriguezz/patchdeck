import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../models/review.dart';
import '../diff/label_picker.dart';

/// Edits labels and text of a comment (anchors stay as they are).
/// Pops `(labelIds, text)`.
class CommentEditDialog extends StatefulWidget {
  const CommentEditDialog({super.key, required this.comment, required this.locations});
  final ReviewComment comment;
  final String locations;

  @override
  State<CommentEditDialog> createState() => _CommentEditDialogState();
}

class _CommentEditDialogState extends State<CommentEditDialog> {
  late List<String> _labels = List.of(widget.comment.labelIds);
  late final _text = TextEditingController(text: widget.comment.text);
  final _labelsFocus = FocusNode();
  final _textFocus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _labelsFocus.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, (_labels, _text.text.trim()));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter, control: true): _save},
      child: AlertDialog(
        title: const Text('Editar comentario'),
        content: SizedBox(
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.locations, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            LabelPicker(
              labels: AppScope.of(context).settings.labels,
              selected: _labels,
              focusNode: _labelsFocus,
              onChanged: (v) => setState(() => _labels = v),
              onDone: _textFocus.requestFocus,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              focusNode: _textFocus,
              minLines: 3,
              maxLines: 10,
              decoration: const InputDecoration(hintText: 'Comentario', contentPadding: EdgeInsets.all(10)),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: _save, child: const Text('Guardar  (Ctrl+Enter)')),
        ],
      ),
    );
  }
}
