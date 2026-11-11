import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../theme/app_themes.dart';

/// Free-form markdown area with Edit / Preview modes.
class MarkdownPanel extends StatefulWidget {
  const MarkdownPanel({super.key, required this.initialText, required this.onChanged, required this.hint});

  final String initialText;
  final ValueChanged<String> onChanged;
  final String hint;

  @override
  State<MarkdownPanel> createState() => _MarkdownPanelState();
}

class _MarkdownPanelState extends State<MarkdownPanel> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initialText);
  late bool _preview = widget.initialText.isNotEmpty;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: false, label: Text('Editar'), icon: Icon(Icons.edit_outlined, size: 16)),
              ButtonSegment(value: true, label: Text('Vista previa'), icon: Icon(Icons.visibility_outlined, size: 16)),
            ],
            selected: {_preview},
            onSelectionChanged: (s) => setState(() => _preview = s.first),
          ),
        ),
        const Divider(),
        Expanded(
          child: _preview
              ? (_ctrl.text.trim().isEmpty
                  ? Center(child: Text('Nada por aquí todavía', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)))
                  : Markdown(
                      data: _ctrl.text,
                      selectable: true,
                      padding: const EdgeInsets.all(14),
                      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                        code: TextStyle(fontFamily: monoFamily, fontFamilyFallback: monoFallback, fontSize: 12.5, backgroundColor: theme.colorScheme.surfaceContainerHigh),
                        codeblockDecoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ))
              : Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    controller: _ctrl,
                    onChanged: widget.onChanged,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(fontFamily: monoFamily, fontFamilyFallback: monoFallback, fontSize: 13, height: 1.45),
                    decoration: InputDecoration(hintText: widget.hint, contentPadding: const EdgeInsets.all(10)),
                  ),
                ),
        ),
      ],
    );
  }
}
