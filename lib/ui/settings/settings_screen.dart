import 'package:flutter/material.dart';

import 'appearance_section.dart';
import 'labels_section.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: Row(children: [
        NavigationRail(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          labelType: NavigationRailLabelType.all,
          destinations: const [
            NavigationRailDestination(icon: Icon(Icons.palette_outlined), selectedIcon: Icon(Icons.palette), label: Text('Apariencia')),
            NavigationRailDestination(icon: Icon(Icons.label_outline), selectedIcon: Icon(Icons.label), label: Text('Etiquetas')),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _index == 0 ? const AppearanceSection() : const LabelsSection()),
      ]),
    );
  }
}
