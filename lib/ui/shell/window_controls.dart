import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Moves the window when its empty parts are dragged and toggles maximize
/// on double-click.
///
/// The gesture layer sits *behind* [child]: buttons in the bar win the hit
/// test, so they never wait for the double-tap timeout.
class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!_desktop) return child;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => windowManager.startDragging(),
            onDoubleTap: () async {
              if (await windowManager.isMaximized()) {
                windowManager.unmaximize();
              } else {
                windowManager.maximize();
              }
            },
          ),
        ),
        child,
      ],
    );
  }
}

bool get _desktop => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

/// Minimal minimize / maximize / close buttons for the custom title bar.
class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    try {
      windowManager.addListener(this);
      windowManager
          .isMaximized()
          .then((v) {
            if (mounted) setState(() => _maximized = v);
          })
          .catchError((_) {});
    } catch (_) {
      // No window plugin (tests).
    }
  }

  @override
  void dispose() {
    try {
      windowManager.removeListener(this);
    } catch (_) {}
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WinButton(icon: Icons.remove, tip: 'Minimizar', onTap: () => windowManager.minimize()),
        _WinButton(
          icon: _maximized ? Icons.filter_none : Icons.crop_square,
          iconSize: _maximized ? 12 : 14,
          tip: _maximized ? 'Restaurar' : 'Maximizar',
          onTap: () => _maximized ? windowManager.unmaximize() : windowManager.maximize(),
        ),
        _WinButton(icon: Icons.close, tip: 'Cerrar', onTap: () => windowManager.close(), danger: true),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _WinButton extends StatefulWidget {
  const _WinButton({
    required this.icon,
    required this.tip,
    required this.onTap,
    this.danger = false,
    this.iconSize = 15,
  });
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final bool danger;
  final double iconSize;

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hoverBg = widget.danger ? const Color(0xFFE5534B) : theme.colorScheme.onSurface.withValues(alpha: 0.08);
    final fg = _hover && widget.danger ? Colors.white : theme.colorScheme.onSurfaceVariant;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 34,
          height: 26,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: _hover ? hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(widget.icon, size: widget.iconSize, color: fg),
        ),
      ),
    );
  }
}
