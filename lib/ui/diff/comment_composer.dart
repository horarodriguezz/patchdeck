import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../state/selection_controller.dart';
import '../../state/workspace_controller.dart';
import 'label_picker.dart';

/// Floating editor shown while lines are selected. The comment applies to
/// every selected line, in every file and patch.
class CommentComposer extends StatefulWidget {
  const CommentComposer({super.key, required this.workspace, required this.selection});

  final WorkspaceController workspace;
  final SelectionController selection;

  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer> {
  final _labelsFocus = FocusNode();
  final _textFocus = FocusNode();
  late final TextEditingController _text;
  late List<String> _labels;

  @override
  void initState() {
    super.initState();
    final editing = widget.selection.editingCommentId;
    final c = editing == null ? null : widget.workspace.comment(editing);
    _text = TextEditingController(text: c?.text ?? '');
    _labels = List.of(c?.labelIds ?? const []);
  }

  @override
  void dispose() {
    _labelsFocus.dispose();
    _textFocus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final keys = widget.selection.selected.toList();
    if (keys.isEmpty) return;
    if (_text.text.trim().isEmpty && _labels.isEmpty) return;
    final editing = widget.selection.editingCommentId;
    if (editing != null) {
      widget.workspace.updateComment(editing, keys, _labels, _text.text.trim());
    } else {
      widget.workspace.addComment(keys, _labels, _text.text.trim());
    }
    widget.selection.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = AppScope.of(context).settings.labels;
    return ListenableBuilder(
      listenable: widget.selection,
      builder: (context, _) {
        final keys = widget.selection.selected;
        final files = <(String, int)>{for (final k in keys) (k.$1, k.$2)}.length;
        final patches = <String>{for (final k in keys) k.$1}.length;
        final editing = widget.selection.editingCommentId != null;
        var scope = '${keys.length} ${keys.length == 1 ? 'línea' : 'líneas'}';
        if (files > 1) scope += ' en $files archivos';
        if (patches > 1) scope += ' de $patches patches';

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter, control: true): _submit,
            const SingleActivator(LogicalKeyboardKey.escape): widget.selection.clear,
          },
          child: Material(
            elevation: 12,
            color: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        editing ? Icons.edit_note : Icons.add_comment_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        editing ? 'Editando comentario · $scope' : 'Comentar $scope',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        'Ctrl+clic agrega líneas · Esc cancela',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                      ),
                      IconButton(
                        tooltip: 'Cancelar',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: widget.selection.clear,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LabelPicker(
                    labels: labels,
                    selected: _labels,
                    focusNode: _labelsFocus,
                    onChanged: (v) => setState(() => _labels = v),
                    onDone: _textFocus.requestFocus,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _text,
                    focusNode: _textFocus,
                    minLines: 2,
                    maxLines: 6,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Escribe un comentario…',
                      contentPadding: EdgeInsets.all(10),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: widget.selection.clear, child: const Text('Cancelar')),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _submit,
                        icon: const Icon(Icons.check, size: 16),
                        label: Text(editing ? 'Guardar  (Ctrl+Enter)' : 'Comentar  (Ctrl+Enter)'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
