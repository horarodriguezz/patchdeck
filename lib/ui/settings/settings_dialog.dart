import 'package:flutter/material.dart';

import '../../app_scope.dart';
import 'settings_pages.dart';

Future<void> showSettingsDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const SettingsDialog());

/// Settings popup: search + navigation on the left, rows on the right.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  SettingsPage _page = SettingsPage.general;
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final theme = Theme.of(context);
    final q = _query.text.trim();
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(32),
      child: SizedBox(
        width: (size.width * 0.78).clamp(720.0, 1040.0),
        height: (size.height * 0.82).clamp(500.0, 800.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 48,
              padding: const EdgeInsets.only(left: 18, right: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  Text('Configuración', style: theme.textTheme.titleSmall?.copyWith(fontSize: 14.5)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Cerrar',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 230,
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      border: Border(right: BorderSide(color: theme.dividerColor)),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                      children: [
                        TextField(
                          controller: _query,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'Buscar',
                            prefixIcon: Icon(Icons.search, size: 17),
                            prefixIconConstraints: BoxConstraints(minWidth: 32),
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                        const SizedBox(height: 16),
                        for (final group in settingsNav) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                            child: Text(group.$1, style: theme.textTheme.bodySmall),
                          ),
                          for (final page in group.$2)
                            _NavItem(
                              icon: page.icon,
                              label: page.title,
                              selected: q.isEmpty && page == _page,
                              onTap: () => setState(() {
                                _page = page;
                                _query.clear();
                              }),
                            ),
                          const SizedBox(height: 14),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListenableBuilder(
                      listenable: AppScope.of(context).settings,
                      builder: (context, _) => ListView(
                        padding: const EdgeInsets.fromLTRB(32, 22, 32, 32),
                        children: q.isEmpty ? buildSettingsPage(context, _page) : buildSearchResults(context, q),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? theme.colorScheme.onSurface.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
