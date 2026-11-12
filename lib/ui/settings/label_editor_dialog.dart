import 'package:flutter/material.dart';

import '../../models/label.dart';
import '../common/label_chip.dart';

const _palette = [
  0xFFE5534B,
  0xFFE0823D,
  0xFFC69026,
  0xFF57AB5A,
  0xFF2EA39C,
  0xFF539BF5,
  0xFF6E7FF3,
  0xFFB083F0,
  0xFFE275AD,
  0xFF8B949E,
  0xFF5C6370,
  0xFF1F883D,
];

/// Returns a [ReviewLabel] with the edited values (id is ignored by caller).
class LabelEditorDialog extends StatefulWidget {
  const LabelEditorDialog({super.key, this.initial});
  final ReviewLabel? initial;

  @override
  State<LabelEditorDialog> createState() => _LabelEditorDialogState();
}

class _LabelEditorDialogState extends State<LabelEditorDialog> {
  late final _title = TextEditingController(text: widget.initial?.title ?? '');
  late final _desc = TextEditingController(text: widget.initial?.description ?? '');
  late int _color = widget.initial?.color ?? _palette[5];
  late final _hex = TextEditingController(text: _hexOf(_color));

  static String _hexOf(int c) => '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _hex.dispose();
    super.dispose();
  }

  void _submit() {
    if (_title.text.trim().isEmpty) return;
    Navigator.pop(
      context,
      ReviewLabel(id: '', title: _title.text.trim(), description: _desc.text.trim(), color: _color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = ReviewLabel(
      id: '',
      title: _title.text.isEmpty ? 'vista previa' : _title.text,
      description: '',
      color: _color,
    );
    return AlertDialog(
      title: Text(widget.initial == null ? 'Nueva etiqueta' : 'Editar etiqueta'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LabelChip(label: preview),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Título'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              decoration: const InputDecoration(labelText: 'Descripción'),
              maxLines: 2,
              minLines: 1,
            ),
            const SizedBox(height: 16),
            const Text('Color'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _palette)
                  InkWell(
                    onTap: () => setState(() {
                      _color = c;
                      _hex.text = _hexOf(c);
                    }),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == _color ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 140,
              child: TextField(
                controller: _hex,
                decoration: const InputDecoration(labelText: 'Hex'),
                onChanged: (v) {
                  final parsed = ReviewLabel.parseColor(v);
                  if (parsed != null) setState(() => _color = parsed);
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}
