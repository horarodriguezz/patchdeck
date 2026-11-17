import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/diff_search.dart';
import '../../state/workspace_controller.dart';

/// Slim Ctrl+F bar above the diff panes.
///
/// `Enter` / `Shift+Enter` go to the next / previous match, `Esc` closes.
class DiffSearchBar extends StatefulWidget {
  const DiffSearchBar({super.key, required this.search, required this.workspace});

  final DiffSearchController search;
  final WorkspaceController workspace;

  @override
  State<DiffSearchBar> createState() => _DiffSearchBarState();
}

class _DiffSearchBarState extends State<DiffSearchBar> {
  late final TextEditingController _text = TextEditingController(text: widget.search.query);
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  int _focusRequest = -1;

  @override
  void initState() {
    super.initState();
    widget.search.addListener(_onSearch);
    _onSearch();
  }

  @override
  void dispose() {
    widget.search.removeListener(_onSearch);
    _debounce?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onSearch() {
    final s = widget.search;
    if (s.focusRequest != _focusRequest) {
      _focusRequest = s.focusRequest;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focus.requestFocus();
        _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
      });
    }
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 140), () {
      widget.search.setQuery(widget.workspace, v);
      // Jump to the first match as you type.
      _go(1, fromTyping: true);
    });
  }

  void _flush() {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      widget.search.setQuery(widget.workspace, _text.text);
    }
  }

  void _go(int dir, {bool fromTyping = false}) {
    if (!fromTyping) _flush();
    final s = widget.search;
    if (fromTyping && s.matches.isEmpty) return;
    final m = s.step(dir);
    if (m != null) widget.workspace.reveal(m.key, ifNeeded: true);
  }

  void _close() {
    _debounce?.cancel();
    widget.search.hide();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        const SingleActivator(LogicalKeyboardKey.enter): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.enter, shift: true): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.numpadEnter, shift: true): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.f3): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.f3, shift: true): () => _go(-1),
      },
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: ListenableBuilder(
          listenable: widget.search,
          builder: (context, _) {
            final s = widget.search;
            final n = s.matches.length;
            final status = s.query.isEmpty
                ? ''
                : n == 0
                ? 'Sin resultados'
                : '${s.current < 0 ? '–' : s.current + 1} de $n${s.truncated ? '+' : ''}';
            return Row(
              children: [
                Icon(Icons.search, size: 18, color: muted),
                const SizedBox(width: 8),
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    onChanged: _onChanged,
                    // Enter is handled by the shortcuts above; keep the focus.
                    onEditingComplete: () {},
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Buscar en los patches visibles',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 110,
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      color: n == 0 && s.query.isNotEmpty ? theme.colorScheme.error : muted,
                    ),
                  ),
                ),
                _BarButton(
                  tooltip: 'Coincidir mayúsculas',
                  selected: s.caseSensitive,
                  onPressed: () {
                    _flush();
                    s.setCaseSensitive(widget.workspace, !s.caseSensitive);
                  },
                  child: const Text('Aa', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                _BarButton(
                  tooltip: 'Anterior (Shift+Enter)',
                  onPressed: n == 0 && !(_debounce?.isActive ?? false) ? null : () => _go(-1),
                  child: const Icon(Icons.keyboard_arrow_up, size: 18),
                ),
                _BarButton(
                  tooltip: 'Siguiente (Enter)',
                  onPressed: n == 0 && !(_debounce?.isActive ?? false) ? null : () => _go(1),
                  child: const Icon(Icons.keyboard_arrow_down, size: 18),
                ),
                const Spacer(),
                _BarButton(tooltip: 'Cerrar (Esc)', onPressed: _close, child: const Icon(Icons.close, size: 16)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({required this.tooltip, required this.onPressed, required this.child, this.selected = false});
  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withValues(alpha: 0.16) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: IconTheme.merge(
            data: IconThemeData(
              color: enabled ? (selected ? scheme.primary : scheme.onSurfaceVariant) : scheme.outline,
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: selected ? scheme.primary : scheme.onSurfaceVariant),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
