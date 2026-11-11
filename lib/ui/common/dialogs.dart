import 'package:flutter/material.dart';

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String label = 'Nombre',
  String confirm = 'Guardar',
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(confirm)),
      ],
    ),
  );
}

Future<bool> confirmDialog(BuildContext context, {required String title, required String message, String confirm = 'Eliminar'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r ?? false;
}

String formatDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}
