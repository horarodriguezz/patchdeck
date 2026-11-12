import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_themes.dart';

class NewPatch {
  const NewPatch(this.name, this.raw);
  final String name;
  final String raw;
}

class AddPatchDialog extends StatefulWidget {
  const AddPatchDialog({super.key, required this.suggestedName});
  final String suggestedName;

  @override
  State<AddPatchDialog> createState() => _AddPatchDialogState();
}

class _AddPatchDialogState extends State<AddPatchDialog> {
  late final _name = TextEditingController(text: widget.suggestedName);
  final _raw = TextEditingController();
  String? _error;

  /// Big inputs bypass the TextField: laying out megabytes of text is slow.
  String? _bulk;
  static const _bulkThreshold = 150000;

  void _setRaw(String text) => setState(() {
        _error = null;
        if (text.length > _bulkThreshold) {
          _bulk = text;
          _raw.clear();
        } else {
          _bulk = null;
          _raw.text = text;
        }
      });

  @override
  void dispose() {
    _name.dispose();
    _raw.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Patches', extensions: ['patch', 'diff', 'txt']),
      XTypeGroup(label: 'Todos'),
    ]);
    if (file == null) return;
    _setRaw(await file.readAsString());
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null) return;
    _setRaw(data!.text!);
  }

  void _submit() {
    final raw = _bulk ?? _raw.text;
    if (raw.trim().isEmpty) {
      setState(() => _error = 'Pega o carga un patch');
      return;
    }
    if (!raw.contains('\n@@ ') && !raw.startsWith('@@ ') && !raw.contains('diff --git')) {
      setState(() => _error = 'Esto no parece un diff unificado (no hay hunks "@@")');
      return;
    }
    Navigator.pop(context, NewPatch(_name.text, raw));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: const Text('Agregar patch'),
      content: SizedBox(
        width: (size.width * 0.7).clamp(420.0, 1000.0),
        height: (size.height * 0.65).clamp(300.0, 800.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SizedBox(
              width: 160,
              child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre')),
            ),
            const Spacer(),
            OutlinedButton.icon(onPressed: _paste, icon: const Icon(Icons.content_paste, size: 16), label: const Text('Pegar')),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: _loadFile, icon: const Icon(Icons.folder_open, size: 16), label: const Text('Cargar archivo…')),
          ]),
          const SizedBox(height: 12),
          if (_bulk != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InputChip(
                avatar: const Icon(Icons.description_outlined, size: 16),
                label: Text('Patch grande cargado: ${'\n'.allMatches(_bulk!).length + 1} líneas, ${(_bulk!.length / 1024).toStringAsFixed(0)} KB'),
                onDeleted: () => setState(() => _bulk = null),
              ),
            ),
          Expanded(
            child: TextField(
              controller: _raw,
              autofocus: true,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: TextStyle(fontFamily: monoFamily, fontFamilyFallback: monoFallback, fontSize: 12.5),
              decoration: InputDecoration(
                hintText: 'Pega aquí la salida de git diff, git show o git format-patch…',
                errorText: _error,
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: const Text('Agregar')),
      ],
    );
  }
}
