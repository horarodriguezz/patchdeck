import 'package:flutter/material.dart';

import 'appearance_section.dart';
import 'labels_section.dart';

Future<void> showSettingsDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const SettingsDialog());

/// Settings popup: Appearance and Labels.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final theme = Theme.of(context);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      backgroundColor: theme.scaffoldBackgroundColor,
      insetPadding: const EdgeInsets.all(32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: SizedBox(
        width: (size.width * 0.8).clamp(640.0, 1040.0),
        height: (size.height * 0.8).clamp(480.0, 760.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 48,
              padding: const EdgeInsets.only(left: 20, right: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  Text('Configuración', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Cerrar',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: (i) => setState(() => _index = i),
                    labelType: NavigationRailLabelType.all,
                    backgroundColor: theme.colorScheme.surface,
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.palette_outlined),
                        selectedIcon: Icon(Icons.palette),
                        label: Text('Apariencia'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.label_outline),
                        selectedIcon: Icon(Icons.label),
                        label: Text('Etiquetas'),
                      ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: _index == 0 ? const AppearanceSection() : const LabelsSection()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
