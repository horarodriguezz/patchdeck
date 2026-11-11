import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../models/app_settings.dart';
import '../../models/review.dart';
import '../../state/review_export.dart';
import '../../state/selection_controller.dart';
import '../../state/workspace_controller.dart';
import '../common/dialogs.dart';
import '../common/markdown_panel.dart';
import '../diff/comment_composer.dart';
import '../diff/panes_view.dart';
import 'add_patch_dialog.dart';
import 'patch_tab_bar.dart';
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
  bool _notFound = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ws == null && !_notFound) _load();
  }

  Future<void> _load() async {
    final scope = AppScope.of(context);
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
    );
    scope.settings.addListener(_onSettings);
    setState(() => _ws = ws);
  }

  void _onSettings() => _ws?.setHighlight(AppScope.of(context).settings.settings.syntaxHighlight);

  @override
  void dispose() {
    final scope = AppScope.of(context);
    scope.settings.removeListener(_onSettings);
    final ws = _ws;
    if (ws != null) {
      ws.flush().then((_) => scope.reviews.refresh());
      ws.dispose();
    }
    _selection.dispose();
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

  void _deleteComment(ReviewComment c) {
    final ws = _ws!;
    final index = ws.comments.indexOf(c);
    ws.deleteComment(c.id);
    if (_selection.editingCommentId == c.id) _selection.clear();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Comentario eliminado'),
        behavior: SnackBarBehavior.floating,
        width: 360,
        action: SnackBarAction(label: 'Deshacer', onPressed: () => ws.restoreComment(c, index)),
      ));
  }

  Future<void> _renameReview() async {
    final t = await promptText(context, title: 'Renombrar review', initial: _ws!.review.title, label: 'Título');
    if (t != null) _ws!.rename(t);
  }

  void _copyMarkdown() {
    final settings = AppScope.of(context).settings;
    Clipboard.setData(ClipboardData(text: exportReviewMarkdown(_ws!.review, settings.labelById)));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Resumen en Markdown copiado al portapapeles'),
      behavior: SnackBarBehavior.floating,
      width: 420,
    ));
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (_notFound) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('No se encontró la review')));
    }
    final ws = _ws;
    if (ws == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final settings = AppScope.of(context).settings;

    return ListenableBuilder(
      listenable: Listenable.merge([ws, settings]),
      builder: (context, _) {
        final mode = settings.settings.diffMode;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _selection.clear,
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: AppBar(
                titleSpacing: 0,
                title: InkWell(
                  onTap: _renameReview,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text(ws.review.title),
                  ),
                ),
                actions: [
                  SegmentedButton<DiffMode>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: DiffMode.unified, icon: Icon(Icons.view_agenda_outlined, size: 16), label: Text('Unificada')),
                      ButtonSegment(value: DiffMode.split, icon: Icon(Icons.vertical_split_outlined, size: 16), label: Text('Dividida')),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) => settings.setDiffMode(s.first),
                  ),
                  const SizedBox(width: 8),
                  IconButton(tooltip: 'Copiar resumen (Markdown)', icon: const Icon(Icons.ios_share), onPressed: _copyMarkdown),
                  IconButton(
                    tooltip: ws.leftOpen ? 'Ocultar contexto' : 'Mostrar contexto',
                    icon: Icon(ws.leftOpen ? Icons.view_sidebar : Icons.view_sidebar_outlined),
                    onPressed: ws.toggleLeft,
                  ),
                  IconButton(
                    tooltip: ws.rightOpen ? 'Ocultar notas' : 'Mostrar notas',
                    icon: Transform.flip(flipX: true, child: Icon(ws.rightOpen ? Icons.view_sidebar : Icons.view_sidebar_outlined)),
                    onPressed: ws.toggleRight,
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SidePanel(
                  title: 'Contexto',
                  icon: Icons.description_outlined,
                  side: AxisDirection.left,
                  open: ws.leftOpen,
                  onToggle: ws.toggleLeft,
                  child: MarkdownPanel(
                    initialText: ws.review.contextMarkdown,
                    onChanged: ws.setContext,
                    hint: 'Pega aquí la descripción del PR, el ticket, requisitos… (Markdown)',
                  ),
                ),
                Expanded(child: _center(ws, mode)),
                SidePanel(
                  title: 'Notas',
                  icon: Icons.sticky_note_2_outlined,
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
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _center(WorkspaceController ws, DiffMode mode) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PatchTabBar(workspace: ws, onAdd: _addPatch, onRename: _renamePatch, onDelete: _deletePatch),
      Expanded(
        child: ws.patches.isEmpty
            ? _NoPatches(onAdd: _addPatch)
            : Stack(children: [
                Positioned.fill(
                  child: PanesView(
                    workspace: ws,
                    selection: _selection,
                    mode: mode,
                    onEditComment: _editComment,
                    onDeleteComment: _deleteComment,
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
                          child: CommentComposer(
                            key: ValueKey('composer-${_selection.session}'),
                            workspace: ws,
                            selection: _selection,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ]),
      ),
    ]);
  }
}

class _NoPatches extends StatelessWidget {
  const _NoPatches({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.difference_outlined, size: 56, color: muted),
        const SizedBox(height: 12),
        Text('Esta review no tiene patches', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text('Agrega la salida de git diff / git format-patch. Cada patch se abre en su propia pestaña.', style: TextStyle(color: muted)),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Agregar patch')),
      ]),
    );
  }
}
