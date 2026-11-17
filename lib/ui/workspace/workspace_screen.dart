import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../models/app_settings.dart';
import '../../models/review.dart';
import '../../state/code_selection.dart';
import '../../state/diff_search.dart';
import '../../state/review_export.dart';
import '../../state/selection_controller.dart';
import '../../state/workspace_controller.dart';
import '../comments/comment_actions.dart';
import '../common/dialogs.dart';
import '../common/markdown_panel.dart';
import '../diff/comment_callbacks.dart';
import '../diff/comment_composer.dart';
import '../diff/panes_view.dart';
import '../finalize/finalize_screen.dart';
import '../shell/title_bar.dart';

import 'add_patch_dialog.dart';
import 'left_panel.dart';
import 'patch_tab_bar.dart';
import 'search_bar.dart';
import 'side_panel.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key, required this.reviewId});
  final String reviewId;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  WorkspaceController? _ws;
  final SelectionController _selection = SelectionController();
  final DiffSearchController _search = DiffSearchController();
  final CodeSelection _codeSelection = CodeSelection();
  bool _notFound = false;
  bool _finalizing = false;
  late final AppScope _scope = AppScope.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ws == null && !_notFound) _load();
  }

  Future<void> _load() async {
    final scope = _scope;
    final review = await scope.reviewRepo.load(widget.reviewId);
    if (!mounted) return;
    if (review == null) {
      setState(() => _notFound = true);
      return;
    }
    final ws = WorkspaceController(
      repo: scope.reviewRepo,
      review: review,
      highlight: scope.settings.settings.syntaxHighlight,
      // Keep the sidebar (titles, counts) in sync with saved changes.
      onSaved: scope.reviews.refresh,
    );
    scope.settings.addListener(_onSettings);
    ws.addListener(_onWorkspace);
    setState(() => _ws = ws);
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  /// Keeps search results in sync with the visible patches.
  void _onWorkspace() => _search.sync(_ws!);

  /// Opens the search; a single-line code selection becomes the query and
  /// the search lands on that very occurrence.
  void _openSearch(WorkspaceController ws) {
    final sel = _codeSelection.text;
    if (sel.isNotEmpty && !sel.contains('\n') && sel.trim().isNotEmpty) {
      _search.show(prefill: sel);
      _search.setQuery(ws, sel);
      _search.sync(ws);
      final key = _codeSelection.startKey;
      if (key == null || !_search.selectAt(key, _codeSelection.startCol)) {
        final m = _search.step(1);
        if (m != null) ws.reveal(m.key, ifNeeded: true);
      }
      return;
    }
    _search.show();
    _search.sync(ws);
  }

  /// Global workspace shortcuts. A keyboard handler (rather than Shortcuts)
  /// so they work wherever the focus is, including inside the text editors.
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || _ws == null || _finalizing || !mounted) return false;
    final hk = HardwareKeyboard.instance;
    if (!hk.isControlPressed || hk.isShiftPressed || hk.isAltPressed || hk.isMetaPressed) return false;
    // Not while a dialog or menu is on top.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final ws = _ws!;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.keyF:
        if (ws.patches.isEmpty) return false;
        _openSearch(ws);
      case LogicalKeyboardKey.keyB:
        ws.toggleLeft();
      case LogicalKeyboardKey.keyL:
        ws.toggleRight();
      default:
        return false;
    }
    return true;
  }

  void _onSettings() => _ws?.setHighlight(_scope.settings.settings.syntaxHighlight);

  @override
  void dispose() {
    final scope = _scope;
    HardwareKeyboard.instance.removeHandler(_onKey);
    scope.settings.removeListener(_onSettings);
    final ws = _ws;
    if (ws != null) {
      ws.removeListener(_onWorkspace);
      ws.flush().then((_) => scope.reviews.refresh());
      ws.dispose();
    }
    _selection.dispose();
    _search.dispose();
    _codeSelection.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- actions

  Future<void> _addPatch() async {
    final ws = _ws!;
    final r = await showDialog<NewPatch>(
      context: context,
      builder: (_) => AddPatchDialog(suggestedName: ws.suggestedPatchName),
    );
    if (r != null) ws.addPatch(r.name, r.raw);
  }

  Future<void> _renamePatch(PatchEntry p) async {
    final name = await promptText(context, title: 'Renombrar patch', initial: p.name);
    if (name != null) _ws!.renamePatch(p.id, name);
  }

  Future<void> _deletePatch(PatchEntry p) async {
    final n = _ws!.comments.where((c) => c.anchors.any((a) => a.patchId == p.id)).length;
    final ok = await confirmDialog(
      context,
      title: 'Eliminar patch ${p.name}',
      message: n == 0 ? '¿Eliminar este patch?' : '¿Eliminar este patch? $n comentario(s) apuntan a sus líneas.',
    );
    if (!ok) return;
    _selection.removeWhere((k) => k.$1 == p.id);
    _ws!.removePatch(p.id);
  }

  void _editComment(ReviewComment c) => _selection.setSelection(_ws!.keysFor(c), editing: c.id);

  CommentCallbacks _callbacks() {
    final actions = CommentActions(context, _ws!);
    return CommentCallbacks(
      edit: _editComment,
      delete: (c) => actions.delete(
        c,
        afterDelete: () {
          if (_selection.editingCommentId == c.id) _selection.clear();
        },
      ),
      copy: (c, patchId) => actions.copyOne(c, patchId: patchId),
      toggleDismissed: actions.toggleDismissed,
    );
  }

  void _openFinalize() {
    _selection.clear();
    setState(() => _finalizing = true);
  }

  void _openInDiff(ReviewComment c, String patchId) {
    final ws = _ws!;
    setState(() => _finalizing = false);
    final k = ws.firstKeyOf(c, patchId) ?? ws.firstKeyOf(c);
    if (k != null) ws.reveal(k);
    _selection.setSelection(ws.keysFor(c), editing: c.id);
  }

  Future<void> _renameReview() async {
    final t = await promptText(context, title: 'Renombrar review', initial: _ws!.review.title, label: 'Título');
    if (t != null) _ws!.rename(t);
  }

  void _copyMarkdown() {
    final settings = AppScope.of(context).settings;
    Clipboard.setData(ClipboardData(text: exportReviewMarkdown(_ws!.review, settings.labelById)));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Resumen en Markdown copiado al portapapeles'),
        behavior: SnackBarBehavior.floating,
        width: 420,
      ),
    );
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (_notFound) {
      return const Column(
        children: [
          AppTopBar(),
          Expanded(child: Center(child: Text('No se encontró la review'))),
        ],
      );
    }
    final ws = _ws;
    if (ws == null) {
      return const Column(
        children: [
          AppTopBar(),
          Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }
    final settings = _scope.settings;

    if (_finalizing) {
      return FinalizeScreen(
        workspace: ws,
        onClose: () => setState(() => _finalizing = false),
        onOpenInDiff: _openInDiff,
      );
    }

    return ListenableBuilder(
      listenable: Listenable.merge([ws, settings]),
      builder: (context, _) {
        final mode = settings.settings.diffMode;
        final theme = Theme.of(context);
        return CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _selection.clear},
          child: Focus(
            autofocus: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTopBar(
                  title: Tooltip(
                    message: 'Renombrar',
                    child: InkWell(
                      onTap: _renameReview,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Text(ws.review.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ),
                  actions: [
                    SegmentedButton<DiffMode>(
                      showSelectedIcon: false,
                      style: ButtonStyle(
                        visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                        textStyle: WidgetStatePropertyAll(theme.textTheme.labelMedium),
                        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
                      ),
                      segments: const [
                        ButtonSegment(
                          value: DiffMode.unified,
                          icon: Icon(Icons.view_agenda_outlined, size: 15),
                          label: Text('Unificada'),
                        ),
                        ButtonSegment(
                          value: DiffMode.split,
                          icon: Icon(Icons.vertical_split_outlined, size: 15),
                          label: Text('Dividida'),
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged: (s) => settings.setDiffMode(s.first),
                    ),
                    const SizedBox(width: 6),
                    TitleBarIconButton(
                      tooltip: 'Buscar (Ctrl+F)',
                      icon: const Icon(Icons.search),
                      onPressed: ws.patches.isEmpty ? null : () => _openSearch(ws),
                    ),
                    TitleBarIconButton(
                      tooltip: 'Copiar resumen (Markdown)',
                      icon: const Icon(Icons.ios_share),
                      onPressed: _copyMarkdown,
                    ),
                    TitleBarIconButton(
                      tooltip: ws.leftOpen
                          ? 'Ocultar contexto y comentarios (Ctrl+B)'
                          : 'Mostrar contexto y comentarios (Ctrl+B)',
                      selected: ws.leftOpen,
                      icon: Icon(ws.leftOpen ? Icons.forum : Icons.forum_outlined),
                      onPressed: ws.toggleLeft,
                    ),
                    TitleBarIconButton(
                      tooltip: ws.rightOpen ? 'Ocultar notas (Ctrl+L)' : 'Mostrar notas (Ctrl+L)',
                      selected: ws.rightOpen,
                      icon: Icon(ws.rightOpen ? Icons.sticky_note_2 : Icons.sticky_note_2_outlined),
                      onPressed: ws.toggleRight,
                    ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                        textStyle: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: _openFinalize,
                      icon: const Icon(Icons.task_alt, size: 16),
                      label: const Text('Finalizar review'),
                    ),
                  ],
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LeftPanel(workspace: ws, selection: _selection),
                      Expanded(child: _center(ws, mode)),
                      SidePanel(
                        header: const PanelTitle(icon: Icons.sticky_note_2_outlined, title: 'Notas'),
                        rail: SimpleRail(
                          icon: Icons.sticky_note_2_outlined,
                          title: 'Notas',
                          onTap: ws.toggleRight,
                          isLeft: false,
                        ),
                        side: AxisDirection.right,
                        open: ws.rightOpen,
                        onToggle: ws.toggleRight,
                        initialWidth: 320,
                        child: MarkdownPanel(
                          initialText: ws.review.notesMarkdown,
                          onChanged: ws.setNotes,
                          hint: 'Tus anotaciones libres (Markdown)',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _center(WorkspaceController ws, DiffMode mode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PatchTabBar(workspace: ws, onAdd: _addPatch, onRename: _renamePatch, onDelete: _deletePatch),
        ListenableBuilder(
          listenable: _search,
          builder: (context, _) => _search.isOpen && ws.patches.isNotEmpty
              ? DiffSearchBar(search: _search, workspace: ws)
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: ws.patches.isEmpty
              ? _NoPatches(onAdd: _addPatch)
              : Stack(
                  children: [
                    Positioned.fill(
                      child: PanesView(
                        workspace: ws,
                        selection: _selection,
                        mode: mode,
                        callbacks: _callbacks(),
                        search: _search,
                        codeSelection: _codeSelection,
                      ),
                    ),
                    ListenableBuilder(
                      listenable: _selection,
                      builder: (context, _) {
                        if (_selection.isEmpty) return const SizedBox.shrink();
                        return Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 760),
                              // Hidden (not removed, so typed text survives a
                              // Ctrl+drag) while a range is being dragged.
                              child: Offstage(
                                offstage: _selection.isDragging,
                                child: CommentComposer(
                                  key: ValueKey('composer-${_selection.session}'),
                                  workspace: ws,
                                  selection: _selection,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _NoPatches extends StatelessWidget {
  const _NoPatches({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.difference_outlined, size: 56, color: muted),
          const SizedBox(height: 12),
          Text('Esta review no tiene patches', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Agrega la salida de git diff / git format-patch. Cada patch se abre en su propia pestaña.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Agregar patch')),
        ],
      ),
    );
  }
}
