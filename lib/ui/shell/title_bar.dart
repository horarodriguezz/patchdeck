import 'package:flutter/material.dart';

import '../../app_scope.dart';
import 'shell_buttons.dart';
import 'window_controls.dart';

/// Height of the custom title bar (the native one is hidden).
const double kTitleBarHeight = 40;

/// Thin title bar for the content area: optional shell buttons (when the
/// reviews sidebar is collapsed), a title, actions and the window buttons.
/// Empty space drags the window; double-click maximizes.
class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key, this.title, this.actions = const []});

  final Widget? title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shell = AppScope.of(context).shell;
    return Container(
      height: kTitleBarHeight,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: WindowDragArea(
        child: Row(
          children: [
            ListenableBuilder(
              listenable: shell,
              builder: (context, _) => AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: shell.sidebarOpen
                    ? const SizedBox(width: 10)
                    : const Padding(padding: EdgeInsets.only(left: 6, right: 6), child: ShellButtons()),
              ),
            ),
            if (title != null)
              Flexible(
                child: DefaultTextStyle.merge(
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  child: title!,
                ),
              ),
            const Spacer(),
            ...actions,
            const SizedBox(width: 6),
            const WindowControls(),
          ],
        ),
      ),
    );
  }
}

/// Compact icon button sized for the title bar.
class TitleBarIconButton extends StatelessWidget {
  const TitleBarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });
  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: selected,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        minimumSize: const Size(32, 30),
        fixedSize: const Size(32, 30),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        foregroundColor: theme.colorScheme.onSurfaceVariant,
      ),
      icon: icon,
    );
  }
}
