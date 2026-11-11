import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/app_settings.dart';
import '../../theme/app_themes.dart';

class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final s = ctrl.settings;
        final theme = Theme.of(context);
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Tema', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final t in appThemes)
                _ThemeCard(spec: t, selected: t.id == s.themeId, onTap: () => ctrl.setTheme(t.id)),
            ]),
            const SizedBox(height: 28),
            Text('Editor de código', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tamaño de fuente'),
              subtitle: Slider(
                value: s.codeFontSize,
                min: 10,
                max: 20,
                divisions: 10,
                label: s.codeFontSize.toStringAsFixed(0),
                onChanged: ctrl.setFontSize,
              ),
              trailing: Text('${s.codeFontSize.toStringAsFixed(0)} px'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Vista por defecto'),
              trailing: SegmentedButton<DiffMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: DiffMode.unified, label: Text('Unificada')),
                  ButtonSegment(value: DiffMode.split, label: Text('Dividida')),
                ],
                selected: {s.diffMode},
                onSelectionChanged: (v) => ctrl.setDiffMode(v.first),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Resaltado de sintaxis'),
              subtitle: const Text('JavaScript, TypeScript y CSS'),
              value: s.syntaxHighlight,
              onChanged: ctrl.setSyntaxHighlight,
            ),
          ],
        );
      },
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.spec, required this.selected, required this.onTap});
  final AppThemeSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = spec.diff;
    Widget bar(Color bg, double w, [Color? fg]) => Container(
          height: 8,
          width: w,
          margin: const EdgeInsets.only(bottom: 5),
          decoration: BoxDecoration(color: fg ?? bg, borderRadius: BorderRadius.circular(2)),
        );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 170,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
              width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 86,
            color: d.codeBg,
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              bar(d.keyword, 60),
              Container(color: d.delBg, child: bar(d.delBg, 110, d.string)),
              Container(color: d.addBg, child: bar(d.addBg, 90, d.function)),
              bar(d.comment, 70),
            ]),
          ),
          Container(
            color: spec.surface,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              Expanded(child: Text(spec.name, style: TextStyle(color: spec.text, fontWeight: FontWeight.w600))),
              if (selected) Icon(Icons.check_circle, size: 18, color: spec.primary),
            ]),
          ),
        ]),
      ),
    );
  }
}
