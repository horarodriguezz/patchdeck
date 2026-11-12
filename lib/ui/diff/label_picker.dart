import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/label.dart';
import '../common/label_chip.dart';

/// Tag input: type to filter, Enter adds the first match, Backspace on an
/// empty field removes the last tag, Enter on an empty field moves on.
class LabelPicker extends StatefulWidget {
  const LabelPicker({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    required this.focusNode,
    required this.onDone,
  });

  final List<ReviewLabel> labels;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final FocusNode focusNode;
  final VoidCallback onDone;

  @override
  State<LabelPicker> createState() => _LabelPickerState();
}

class _LabelPickerState extends State<LabelPicker> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<ReviewLabel> get _suggestions {
    final q = _query.text.trim().toLowerCase();
    return [
      for (final l in widget.labels)
        if (!widget.selected.contains(l.id) &&
            (q.isEmpty || l.title.toLowerCase().contains(q) || l.description.toLowerCase().contains(q)))
          l,
    ];
  }

  void _add(ReviewLabel l) {
    widget.onChanged([...widget.selected, l.id]);
    _query.clear();
    setState(() {});
    widget.focusNode.requestFocus();
  }

  void _remove(String id) => widget.onChanged([
    for (final s in widget.selected)
      if (s != id) s,
  ]);

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.backspace && _query.text.isEmpty && widget.selected.isNotEmpty) {
      _remove(widget.selected.last);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final byId = {for (final l in widget.labels) l.id: l};
    final theme = Theme.of(context);
    final suggestions = _suggestions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          isFocused: widget.focusNode.hasFocus,
          decoration: const InputDecoration(
            labelText: 'Etiquetas',
            contentPadding: EdgeInsets.fromLTRB(10, 10, 10, 8),
            prefixIcon: Icon(Icons.label_outline, size: 18),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final id in widget.selected)
                if (byId[id] case final l?) LabelChip(label: l, onDeleted: () => _remove(id)),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 120, maxWidth: 260),
                child: Focus(
                  onKeyEvent: _onKey,
                  skipTraversal: true,
                  child: TextField(
                    controller: _query,
                    focusNode: widget.focusNode,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      final s = _suggestions;
                      if (_query.text.trim().isNotEmpty && s.isNotEmpty) {
                        _add(s.first);
                      } else {
                        widget.onDone();
                      }
                    },
                    decoration: const InputDecoration.collapsed(
                      hintText: 'Buscar etiqueta… (Enter)',
                      filled: false,
                    ).copyWith(enabledBorder: InputBorder.none, focusedBorder: InputBorder.none),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, l) in suggestions.indexed)
                Opacity(
                  opacity: i == 0 && _query.text.isNotEmpty ? 1 : 0.85,
                  child: LabelChip(label: l, onTap: () => _add(l), outlined: !(i == 0 && _query.text.isNotEmpty)),
                ),
            ],
          ),
        ] else if (widget.labels.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'No hay etiquetas: créalas en Configuración.',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}
