import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/review.dart';
import '../common/dialogs.dart';
import 'shell_buttons.dart';
import 'title_bar.dart';
import 'window_controls.dart';

/// Global list of reviews (like a chat app's conversation list). Always part
/// of the shell; slides in/out with an eased width animation.
class ReviewsSidebar extends StatefulWidget {
  const ReviewsSidebar({super.key});

  static const double width = 280;

  @override
  State<ReviewsSidebar> createState() => _ReviewsSidebarState();
}

class _ReviewsSidebarState extends State<ReviewsSidebar> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final CurvedAnimation _curve;
  final _query = TextEditingController();
  late final _shell = AppScope.of(context).shell;

  @override
  void initState() {
    super.initState();
    final shell = _shell;
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
      value: shell.sidebarOpen ? 1 : 0,
    );
    _curve = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    shell.addListener(_sync);
  }

  void _sync() {
    final open = _shell.sidebarOpen;
    open ? _anim.forward() : _anim.reverse();
  }

  @override
  void dispose() {
    _shell.removeListener(_sync);
    _curve.dispose();
    _anim.dispose();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = RepaintBoundary(child: _content(context));
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final t = _curve.value;
        if (t == 0) return const SizedBox.shrink();
        return Container(
          width: ReviewsSidebar.width * t,
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            border: Border(right: BorderSide(color: theme.dividerColor)),
          ),
          clipBehavior: Clip.hardEdge,
          child: OverflowBox(
            alignment: Alignment.centerRight,
            minWidth: ReviewsSidebar.width,
            maxWidth: ReviewsSidebar.width,
            child: Opacity(opacity: Curves.easeIn.transform(t), child: child),
          ),
        );
      },
      child: content,
    );
  }

  Widget _content(BuildContext context) {
    final scope = AppScope.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: kTitleBarHeight,
          child: WindowDragArea(
            child: Row(
              children: [
                const SizedBox(width: 6),
                const ShellButtons(),
                const Spacer(),
                Text(
                  'Patchdeck',
                  style: TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: _SidebarAction(icon: Icons.add, label: 'Nueva review', onTap: () => createReview(context)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
          child: TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Buscar',
              prefixIcon: const Icon(Icons.search, size: 18),
              prefixIconConstraints: const BoxConstraints(minWidth: 34),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              fillColor: theme.colorScheme.surface,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Text(
            'Reviews',
            style: TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: Listenable.merge([scope.reviews, scope.shell]),
            builder: (context, _) {
              if (scope.reviews.loading) return const SizedBox.shrink();
              final q = _query.text.trim().toLowerCase();
              final items = [
                for (final r in scope.reviews.items)
                  if (q.isEmpty || r.title.toLowerCase().contains(q)) r,
              ];
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    q.isEmpty ? 'Todavía no hay reviews.' : 'Sin resultados.',
                    style: TextStyle(color: muted, fontSize: 12.5),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                itemCount: items.length,
                itemBuilder: (context, i) =>
                    _ReviewTile(summary: items[i], selected: items[i].id == scope.shell.openReviewId),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SidebarAction extends StatelessWidget {
  const _SidebarAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontSize: 13.5)),
          ],
        ),
      ),
    );
  }
}

class _ReviewTile extends StatefulWidget {
  const _ReviewTile({required this.summary, required this.selected});
  final ReviewSummary summary;
  final bool selected;

  @override
  State<_ReviewTile> createState() => _ReviewTileState();
}

class _ReviewTileState extends State<_ReviewTile> {
  bool _hover = false;

  Future<void> _rename() async {
    final scope = AppScope.of(context);
    final t = await promptText(context, title: 'Renombrar review', initial: widget.summary.title, label: 'Título');
    if (t != null && t.trim().isNotEmpty) await scope.reviews.rename(widget.summary.id, t.trim());
  }

  Future<void> _delete() async {
    final scope = AppScope.of(context);
    final ok = await confirmDialog(
      context,
      title: 'Eliminar review',
      message: '¿Eliminar "${widget.summary.title}"? Esta acción no se puede deshacer.',
    );
    if (!ok) return;
    if (scope.shell.openReviewId == widget.summary.id) scope.shell.closeReview();
    await scope.reviews.delete(widget.summary.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final s = widget.summary;
    final meta = [
      if (s.patchNames.isNotEmpty) s.patchNames.join(' · '),
      if (s.commentCount > 0) '${s.commentCount} ${s.commentCount == 1 ? 'comentario' : 'comentarios'}',
      relativeTime(s.updatedAt),
    ].join('  ·  ');
    final bg = widget.selected
        ? theme.colorScheme.primary.withValues(alpha: 0.13)
        : (_hover ? theme.colorScheme.onSurface.withValues(alpha: 0.05) : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => AppScope.of(context).shell.openReview(s.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: muted),
                        ),
                      ],
                    ),
                  ),
                  Visibility(
                    visible: _hover || widget.selected,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: PopupMenuButton<String>(
                      tooltip: 'Acciones',
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.more_horiz, color: muted),
                      onSelected: (v) => v == 'rename' ? _rename() : _delete(),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                        PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
