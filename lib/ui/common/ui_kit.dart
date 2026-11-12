import 'package:flutter/material.dart';

/// shadcn-style select: a bordered button with the current value and a
/// chevron that opens a menu of options.
class AppSelect<T> extends StatelessWidget {
  const AppSelect({
    super.key,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.leadingOf,
    this.width = 240,
  });

  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final Widget Function(T)? leadingOf;
  final ValueChanged<T> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(minimumSize: WidgetStatePropertyAll(Size(width, 0))),
      menuChildren: [
        for (final o in options)
          MenuItemButton(
            leadingIcon: leadingOf?.call(o),
            trailingIcon: o == value ? Icon(Icons.check, size: 16, color: theme.colorScheme.onSurface) : null,
            onPressed: () => onChanged(o),
            child: Text(labelOf(o)),
          ),
      ],
      builder: (context, controller, _) => SizedBox(
        width: width,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 10, right: 6),
            minimumSize: const Size(0, 34),
          ),
          onPressed: () => controller.isOpen ? controller.close() : controller.open(),
          child: Row(
            children: [
              if (leadingOf != null) ...[leadingOf!(value), const SizedBox(width: 8)],
              Expanded(child: Text(labelOf(value), overflow: TextOverflow.ellipsis)),
              Icon(Icons.expand_more, size: 18, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section heading inside a settings page.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14.5)),
          ),
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(), children[i]],
        ],
      ),
    );
  }
}

/// "Title + description" on the left, a control on the right.
class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, required this.title, this.description, this.trailing, this.below});
  final String title;
  final String? description;
  final Widget? trailing;

  /// Optional full-width content under the row (e.g. a preview).
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                    if (description != null) ...[
                      const SizedBox(height: 3),
                      Text(description!, style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5, height: 1.4)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 24), trailing!],
            ],
          ),
          if (below != null) ...[const SizedBox(height: 12), below!],
        ],
      ),
    );
  }
}

/// Compact segmented control (shadcn "tabs" look).
class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
  });
  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            GestureDetector(
              onTap: () => onChanged(o),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: o == value ? theme.colorScheme.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: o == value
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    labelOf(o),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: o == value ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
