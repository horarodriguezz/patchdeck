import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../models/app_settings.dart';
import '../../models/label.dart';
import '../../models/review.dart';
import '../../state/comment_format.dart';
import '../../services/app_paths.dart';
import '../../services/system_fonts.dart';
import '../../theme/app_themes.dart';
import '../../version.dart';
import '../common/dialogs.dart';
import '../common/label_chip.dart';
import '../common/ui_kit.dart';
import 'label_editor_dialog.dart';
import 'theme_preview.dart';

enum SettingsPage {
  general('General', Icons.tune),
  editor('Editor de código', Icons.code),
  labels('Etiquetas', Icons.label_outline),
  copy('Copiar comentarios', Icons.content_copy),
  data('Datos y sistema', Icons.computer_outlined);

  const SettingsPage(this.title, this.icon);
  final String title;
  final IconData icon;
}

const settingsNav = [
  ('Preferencias', [SettingsPage.general, SettingsPage.editor, SettingsPage.labels, SettingsPage.copy]),
  ('Esta computadora', [SettingsPage.data]),
];

/// One searchable setting.
class _Entry {
  const _Entry(this.page, this.section, this.title, this.description, this.build, {this.keywords = ''});
  final SettingsPage page;
  final String section;
  final String title;
  final String? description;
  final String keywords;
  final Widget Function(BuildContext) build;

  bool matches(String q) {
    final s = q.toLowerCase();
    return '$title ${description ?? ''} $section $keywords ${page.title}'.toLowerCase().contains(s);
  }
}

final List<_Entry> _entries = [
  _Entry(
    SettingsPage.general,
    'Apariencia',
    'Tema',
    'Colores de la interfaz y del diff. El cambio se aplica al instante.',
    keywords: 'theme color oscuro claro dark light',
    (context) {
      final ctrl = AppScope.of(context).settings;
      final s = ctrl.settings;
      final spec = themeSpecById(s.themeId);
      return SettingsRow(
        title: 'Tema',
        description: 'Colores de la interfaz y del diff. El cambio se aplica al instante.',
        trailing: AppSelect<AppThemeSpec>(
          value: spec,
          options: appThemes,
          labelOf: (t) => t.name,
          leadingOf: (t) => ThemeSwatch(spec: t),
          onChanged: (t) => ctrl.setTheme(t.id),
        ),
        below: ThemePreview(spec: spec, fontSize: s.codeFontSize),
      );
    },
  ),
  _Entry(
    SettingsPage.general,
    'Apariencia',
    'Vista del diff por defecto',
    'Cómo se muestran los cambios al abrir un patch. También se cambia desde la barra de la review.',
    keywords: 'unificada dividida split unified',
    (context) {
      final ctrl = AppScope.of(context).settings;
      return SettingsRow(
        title: 'Vista del diff por defecto',
        description: 'Cómo se muestran los cambios al abrir un patch. También se cambia desde la barra de la review.',
        trailing: AppSegmented<DiffMode>(
          value: ctrl.settings.diffMode,
          options: DiffMode.values,
          labelOf: (m) => m == DiffMode.unified ? 'Unificada' : 'Dividida',
          onChanged: ctrl.setDiffMode,
        ),
      );
    },
  ),
  _Entry(
    SettingsPage.editor,
    'Código',
    'Fuente de código',
    'Fuente monoespaciada para el diff y los extractos. Vacío usa la del sistema.',
    keywords: 'font monospace tipografía',
    (context) => const SettingsRow(
      title: 'Fuente de código',
      description: 'Fuente monoespaciada para el diff y los extractos. Vacío usa la del sistema.',
      trailing: _CodeFontField(),
    ),
  ),
  _Entry(
    SettingsPage.editor,
    'Código',
    'Tamaño de fuente del código',
    'Se aplica al diff, los extractos y la vista previa.',
    keywords: 'size font tamaño',
    (context) {
      final ctrl = AppScope.of(context).settings;
      return SettingsRow(
        title: 'Tamaño de fuente del código',
        description: 'Se aplica al diff, los extractos y la vista previa.',
        trailing: AppSelect<double>(
          value: ctrl.settings.codeFontSize,
          options: const [11, 12, 13, 14, 15, 16, 18],
          labelOf: (v) => v == 13 ? 'Predeterminado · 13 px' : '${v.toStringAsFixed(0)} px',
          onChanged: ctrl.setFontSize,
        ),
      );
    },
  ),
  _Entry(
    SettingsPage.editor,
    'Código',
    'Resaltado de sintaxis',
    'JavaScript, TypeScript y CSS (también SCSS/LESS básico).',
    keywords: 'syntax highlight colores',
    (context) {
      final ctrl = AppScope.of(context).settings;
      return SettingsRow(
        title: 'Resaltado de sintaxis',
        description: 'JavaScript, TypeScript y CSS (también SCSS/LESS básico).',
        trailing: Switch(value: ctrl.settings.syntaxHighlight, onChanged: ctrl.setSyntaxHighlight),
      );
    },
  ),
  _Entry(
    SettingsPage.labels,
    'Etiquetas',
    'Etiquetas de comentarios',
    'Título, descripción y color. Se eligen al comentar.',
    keywords: 'labels tags color',
    (context) => const _LabelsEditor(),
  ),
  _Entry(
    SettingsPage.copy,
    'Formato',
    'Plantilla de copiado',
    'Cómo se copia cada comentario con «Copiar comentario» y «Copiar todos».',
    keywords: 'copy template formato plantilla clipboard portapapeles',
    (context) => const _CopyTemplateEditor(),
  ),
  _Entry(
    SettingsPage.data,
    'Almacenamiento',
    'Archivo de configuración',
    null,
    keywords: 'settings json path ruta',
    (context) => _PathRow(title: 'Archivo de configuración', path: AppPaths.fromEnvironment().settingsFile.path),
  ),
  _Entry(
    SettingsPage.data,
    'Almacenamiento',
    'Carpeta de reviews',
    null,
    keywords: 'data path ruta reviews',
    (context) => _PathRow(title: 'Carpeta de reviews', path: AppPaths.fromEnvironment().reviewsDir.path),
  ),
  _Entry(SettingsPage.data, 'Sistema', 'Fuentes detectadas', null, keywords: 'font sistema', (context) {
    final f = SystemFonts.current;
    return SettingsRow(
      title: 'Fuentes detectadas',
      description: 'Interfaz: ${f.ui ?? 'predeterminada'} · Código: ${f.mono ?? 'monospace'} (origen: ${f.source})',
    );
  }),
  _Entry(
    SettingsPage.data,
    'Sistema',
    'Versión',
    null,
    keywords: 'version acerca about',
    (context) => const SettingsRow(title: 'Versión', description: 'Patchdeck $appVersion'),
  ),
];

List<Widget> buildSettingsPage(BuildContext context, SettingsPage page) {
  final theme = Theme.of(context);
  final entries = _entries.where((e) => e.page == page).toList();
  final sections = <String, List<_Entry>>{};
  for (final e in entries) {
    (sections[e.section] ??= []).add(e);
  }
  return [
    Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Text(page.title, style: theme.textTheme.titleMedium?.copyWith(fontSize: 17)),
    ),
    for (final s in sections.entries)
      sections.length == 1 && page == SettingsPage.labels
          ? s.value.single.build(context)
          : SettingsSection(title: s.key, children: [for (final e in s.value) e.build(context)]),
  ];
}

List<Widget> buildSearchResults(BuildContext context, String q) {
  final theme = Theme.of(context);
  final hits = _entries.where((e) => e.matches(q)).toList();
  if (hits.isEmpty) {
    return [
      Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(child: Text('Nada coincide con "$q"', style: theme.textTheme.bodySmall)),
      ),
    ];
  }
  final groups = <String, List<_Entry>>{};
  for (final e in hits) {
    (groups['${e.page.title} › ${e.section}'] ??= []).add(e);
  }
  return [
    for (final g in groups.entries)
      SettingsSection(title: g.key, children: [for (final e in g.value) e.build(context)]),
  ];
}

class _CodeFontField extends StatefulWidget {
  const _CodeFontField();

  @override
  State<_CodeFontField> createState() => _CodeFontFieldState();
}

class _CodeFontFieldState extends State<_CodeFontField> {
  late final _ctrl = TextEditingController(text: AppScope.of(context).settings.settings.codeFontFamily);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final system = SystemFonts.current.mono ?? 'monospace';
    return SizedBox(
      width: 240,
      child: TextField(
        controller: _ctrl,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(hintText: '$system (sistema)'),
        onChanged: AppScope.of(context).settings.setCodeFont,
      ),
    );
  }
}

class _PathRow extends StatelessWidget {
  const _PathRow({required this.title, required this.path});
  final String title;
  final String path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SettingsRow(
      title: title,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: SelectableText(
              path,
              maxLines: 1,
              style: TextStyle(
                fontFamily: monoFamily,
                fontFamilyFallback: monoFallback,
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Copiar ruta',
            icon: const Icon(Icons.content_copy, size: 15),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: path));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ruta copiada'), width: 260));
            },
          ),
        ],
      ),
    );
  }
}

class _LabelsEditor extends StatelessWidget {
  const _LabelsEditor();

  Future<void> _edit(BuildContext context, ReviewLabel? label) async {
    final ctrl = AppScope.of(context).settings;
    final r = await showDialog<ReviewLabel>(
      context: context,
      builder: (_) => LabelEditorDialog(initial: label),
    );
    if (r == null) return;
    ctrl.upsertLabel(id: label?.id, title: r.title, description: r.description, color: r.color);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = AppScope.of(context).settings;
    final theme = Theme.of(context);
    final labels = ctrl.labels;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsRow(
          title: 'Etiquetas de comentarios',
          description: 'Título, descripción y color. Se eligen al comentar. Arrastra para reordenar.',
          trailing: OutlinedButton.icon(
            onPressed: () => _edit(context, null),
            icon: const Icon(Icons.add),
            label: const Text('Nueva etiqueta'),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: labels.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Sin etiquetas todavía.', style: theme.textTheme.bodySmall),
                )
              : ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: labels.length,
                  onReorder: ctrl.reorderLabel,
                  proxyDecorator: (child, _, _) =>
                      Material(color: theme.colorScheme.surface, elevation: 4, child: child),
                  itemBuilder: (context, i) {
                    final l = labels[i];
                    return Container(
                      key: ValueKey(l.id),
                      decoration: BoxDecoration(
                        border: i == 0 ? null : Border(top: BorderSide(color: theme.dividerColor)),
                      ),
                      padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: i,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.grab,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.drag_indicator, size: 16, color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 150,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: LabelChip(label: l),
                            ),
                          ),
                          Expanded(
                            child: Text(l.description, style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5)),
                          ),
                          IconButton(
                            tooltip: 'Editar',
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            onPressed: () => _edit(context, l),
                          ),
                          IconButton(
                            tooltip: 'Eliminar',
                            icon: const Icon(Icons.delete_outline, size: 16),
                            onPressed: () async {
                              if (await confirmDialog(
                                context,
                                title: 'Eliminar etiqueta',
                                message: '¿Eliminar "${l.title}"?',
                              )) {
                                ctrl.deleteLabel(l.id);
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CopyTemplateEditor extends StatefulWidget {
  const _CopyTemplateEditor();

  @override
  State<_CopyTemplateEditor> createState() => _CopyTemplateEditorState();
}

class _CopyTemplateEditorState extends State<_CopyTemplateEditor> {
  late final _ctrl = TextEditingController(text: AppScope.of(context).settings.settings.copyTemplate);
  final _focus = FocusNode();

  static final _sample = [
    ReviewComment(
      id: 's1',
      anchors: [
        for (final n in [2, 3]) LineAnchor(patchId: 'p', path: 'src/components/greet.ts', newLine: n),
        const LineAnchor(patchId: 'p', path: 'styles/app.css', newLine: 11),
      ],
      labelIds: const ['bug', 'nit'],
      text: 'Falta validar que name no sea vacío.',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    ),
    ReviewComment(
      id: 's2',
      anchors: const [LineAnchor(patchId: 'p', path: 'src/store.ts', oldLine: 40)],
      labelIds: const ['question'],
      text: '¿Por qué se elimina este caché?',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    ),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _set(String v) => AppScope.of(context).settings.setCopyTemplate(v);

  void _insert(String variable) {
    final text = _ctrl.text;
    final sel = _ctrl.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final ins = '{{$variable}}';
    _ctrl.value = TextEditingValue(
      text: text.replaceRange(start, end, ins),
      selection: TextSelection.collapsed(offset: start + ins.length),
    );
    _focus.requestFocus();
    _set(_ctrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = AppScope.of(context).settings;
    final mono = TextStyle(fontFamily: monoFamily, fontFamilyFallback: monoFallback, fontSize: 12.5);
    final preview = formatComments(
      _sample,
      labelById: settings.labelById,
      patchNames: const {'p': 'A'},
      template: settings.settings.copyTemplate,
    );
    final isDefault = settings.settings.copyTemplate == defaultCopyTemplate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsRow(
          title: 'Plantilla de copiado',
          description:
              'Cómo se copia cada comentario con «Copiar comentario» y «Copiar todos» (separados por una línea '
              'en blanco). Escribe texto fijo entre las variables; los denegados nunca se copian.',
          trailing: TextButton.icon(
            onPressed: isDefault
                ? null
                : () {
                    _ctrl.text = defaultCopyTemplate;
                    _set(defaultCopyTemplate);
                  },
            icon: const Icon(Icons.restart_alt),
            label: const Text('Restablecer'),
          ),
        ),
        TextField(
          controller: _ctrl,
          focusNode: _focus,
          minLines: 1,
          maxLines: 4,
          style: mono.copyWith(fontSize: 13),
          decoration: const InputDecoration(hintText: defaultCopyTemplate),
          onChanged: _set,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Insertar:', style: theme.textTheme.bodySmall),
            for (final (name, help) in copyTemplateVariables)
              Tooltip(
                message: help,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: mono.copyWith(fontSize: 12),
                  ),
                  onPressed: () => _insert(name),
                  child: Text('{{$name}}'),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Text('Vista previa', style: theme.textTheme.bodySmall),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.dividerColor),
          ),
          child: SelectableText(preview.isEmpty ? '(vacío)' : preview, style: mono.copyWith(height: 1.5)),
        ),
      ],
    );
  }
}
