import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../diff/diff_layout.dart';
import '../../models/app_settings.dart';
import '../../models/label.dart';
import '../../models/review.dart';
import '../../state/patch_model.dart';
import '../../state/selection_controller.dart';
import '../../state/workspace_controller.dart';
import '../../theme/app_themes.dart';
import '../../theme/diff_theme.dart';
import 'diff_rows.dart';
import 'line_cell.dart';

/// Virtualized diff renderer.
///
/// All rows have a known height (see [DiffLayout]) and are built lazily via
/// `itemExtentBuilder`, so only what is on screen exists as widgets. Range
/// selection maps pointer positions to rows with a binary search over the
/// precomputed offsets, which also makes edge auto-scrolling trivial.
class DiffView extends StatefulWidget {
  const DiffView({
    super.key,
    required this.workspace,
    required this.selection,
    required this.model,
    required this.layout,
    required this.mode,
    required this.metrics,
    required this.controller,
    required this.horizontalScroll,
    required this.onEditComment,
    required this.onDeleteComment,
  });

  final WorkspaceController workspace;
  final SelectionController selection;
  final PatchModel model;
  final DiffLayout layout;
  final DiffMode mode;
  final DiffMetrics metrics;
  final ScrollController controller;
  final bool horizontalScroll;
  final void Function(ReviewComment) onEditComment;
  final void Function(ReviewComment) onDeleteComment;

  @override
  State<DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends State<DiffView> {
  final ScrollController _h = ScrollController();
  Timer? _autoScroll;
  double _autoDir = 0;
  Offset? _lastPointer;
  bool _dragging = false;

  int _cacheVersion = -1;
  Map<String, int> _commentsPerPath = const {};

  @override
  void dispose() {
    _autoScroll?.cancel();
    _h.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- selection

  void _beginSelection(int row, Side side) {
    widget.selection.begin(
      widget.layout,
      widget.mode,
      row,
      side,
      ctrl: HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
    );
    _dragging = widget.selection.isDragging;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_dragging) return;
    _lastPointer = e.localPosition;
    _updateDrag();
    final h = context.size?.height ?? 0;
    const edge = 36.0;
    final y = e.localPosition.dy;
    final dir = y < edge ? -1.0 : (y > h - edge ? 1.0 : 0.0);
    if (dir != _autoDir) {
      _autoDir = dir;
      _autoScroll?.cancel();
      if (dir != 0) {
        _autoScroll = Timer.periodic(const Duration(milliseconds: 16), (_) {
          final c = widget.controller;
          if (!c.hasClients) return;
          final pos = c.position;
          final next = (c.offset + _autoDir * widget.metrics.lineHeight).clamp(0.0, pos.maxScrollExtent);
          if (next != c.offset) {
            c.jumpTo(next);
            _updateDrag();
          }
        });
      }
    }
  }

  void _updateDrag() {
    final p = _lastPointer;
    if (p == null || !widget.controller.hasClients) return;
    final y = p.dy + widget.controller.offset;
    widget.selection.dragTo(widget.layout.indexAt(y));
  }

  void _endDrag([PointerEvent? _]) {
    if (!_dragging) return;
    _dragging = false;
    _autoScroll?.cancel();
    _autoDir = 0;
    widget.selection.end();
  }

  // ------------------------------------------------------------- building

  Map<String, int> _commentCounts() {
    final v = widget.workspace.commentsVersion;
    if (v != _cacheVersion) {
      _cacheVersion = v;
      final out = <String, int>{};
      for (final c in widget.workspace.comments) {
        final paths = <String>{for (final a in c.anchors) if (a.patchId == widget.model.id) a.path};
        for (final p in paths) {
          out[p] = (out[p] ?? 0) + 1;
        }
      }
      _commentsPerPath = out;
    }
    return _commentsPerPath;
  }

  String _commentSummary(ReviewComment c) {
    final files = <String>{for (final a in c.anchors) '${a.patchId}|${a.path}'}.length;
    final patches = <String>{for (final a in c.anchors) a.patchId}.length;
    final parts = ['${c.anchors.length} ${c.anchors.length == 1 ? 'línea' : 'líneas'}'];
    if (files > 1) parts.add('$files archivos');
    if (patches > 1) parts.add('$patches patches');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final layout = widget.layout;
    final codeStyle = TextStyle(
      fontFamily: monoFamily,
      fontFamilyFallback: monoFallback,
      fontSize: m.fontSize,
      height: 1.2,
    );
    final numberWidth = m.charWidth * 5 + 12;
    final settings = AppScope.of(context).settings;
    final commented = widget.workspace.commentedKeys(widget.model.id);
    final counts = _commentCounts();
    final collapsed = widget.workspace.collapsedFiles(widget.model.id);
    final unified = widget.mode == DiffMode.unified;
    final codeIndent = unified ? numberWidth * 2 + 36 : numberWidth + 36;
    final dividerColor = context.diffTheme.border;

    Widget buildRow(BuildContext context, int i) {
      final row = layout.rows[i];
      switch (row.kind) {
        case RowKind.preamble:
          return PreambleRow(text: widget.model.parsed.preamble, style: codeStyle);
        case RowKind.fileHeader:
          final file = widget.model.parsed.files[row.file];
          return FileHeaderRow(
            file: file,
            collapsed: collapsed.contains(row.file),
            commentCount: counts[file.path] ?? 0,
            onToggle: () => widget.workspace.toggleFile(widget.model.id, row.file),
          );
        case RowKind.notice:
          return NoticeRow(file: widget.model.parsed.files[row.file]);
        case RowKind.hunk:
          return HunkRow(hunk: widget.model.parsed.files[row.file].hunks[row.hunk], style: codeStyle);
        case RowKind.gap:
          return const SizedBox.shrink();
        case RowKind.comment:
          final c = widget.workspace.comment(row.commentId!);
          if (c == null) return const SizedBox.shrink();
          final labels = <ReviewLabel>[
            for (final id in c.labelIds)
              ?settings.labelById(id),
          ];
          return CommentRow(
            comment: c,
            labels: labels,
            summary: _commentSummary(c),
            indent: codeIndent,
            onEdit: () => widget.onEditComment(c),
            onDelete: () => widget.onDeleteComment(c),
          );
        case RowKind.line:
          final hunk = widget.model.parsed.files[row.file].hunks[row.hunk];
          final pid = widget.model.id;
          if (unified) {
            final key = (pid, row.file, row.hunk, row.a);
            return LineCell(
              line: hunk.lines[row.a],
              side: Side.left,
              showOld: true,
              showNew: true,
              selected: widget.selection.isSelected(key),
              commented: commented.contains(key),
              numberWidth: numberWidth,
              codeStyle: codeStyle,
              onGutterDown: (s) => _beginSelection(i, s),
            );
          }
          final lk = row.a >= 0 ? (pid, row.file, row.hunk, row.a) : null;
          final rk = row.b >= 0 ? (pid, row.file, row.hunk, row.b) : null;
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: LineCell(
                line: row.a >= 0 ? hunk.lines[row.a] : null,
                side: Side.left,
                showOld: true,
                showNew: false,
                selected: lk != null && widget.selection.isSelected(lk),
                commented: lk != null && commented.contains(lk),
                numberWidth: numberWidth,
                codeStyle: codeStyle,
                onGutterDown: (s) => _beginSelection(i, s),
              ),
            ),
            SizedBox(width: 1, child: ColoredBox(color: dividerColor)),
            Expanded(
              child: LineCell(
                line: row.b >= 0 ? hunk.lines[row.b] : null,
                side: Side.right,
                showOld: false,
                showNew: true,
                selected: rk != null && widget.selection.isSelected(rk),
                commented: rk != null && commented.contains(rk),
                numberWidth: numberWidth,
                codeStyle: codeStyle,
                onGutterDown: (s) => _beginSelection(i, s),
              ),
            ),
          ]);
      }
    }

    final list = ListenableBuilder(
      listenable: widget.selection,
      builder: (context, _) => ListView.builder(
        controller: widget.controller,
        padding: const EdgeInsets.only(bottom: 280),
        itemCount: layout.rows.length,
        itemExtentBuilder: (i, _) => i < layout.rows.length ? layout.extent(i) : null,
        addAutomaticKeepAlives: false,
        itemBuilder: buildRow,
      ),
    );

    // Explicit scrollbars only (the platform default would add duplicates).
    final noAutoBars = ScrollConfiguration.of(context).copyWith(scrollbars: false);
    Widget body;
    if (widget.horizontalScroll) {
      body = LayoutBuilder(builder: (context, c) {
        final contentWidth = codeIndent + math.min(layout.maxLineChars, 2000) * m.charWidth + 48;
        final width = math.max(c.maxWidth, contentWidth);
        return Scrollbar(
          controller: widget.controller,
          notificationPredicate: (n) => n.depth == 1 && n.metrics.axis == Axis.vertical,
          child: Scrollbar(
            controller: _h,
            notificationPredicate: (n) => n.depth == 0 && n.metrics.axis == Axis.horizontal,
            child: ScrollConfiguration(
              behavior: noAutoBars,
              child: SingleChildScrollView(
                controller: _h,
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: width, height: c.maxHeight, child: list),
              ),
            ),
          ),
        );
      });
    } else {
      body = Scrollbar(
        controller: widget.controller,
        child: ScrollConfiguration(behavior: noAutoBars, child: list),
      );
    }

    return Listener(
      onPointerMove: _onPointerMove,
      onPointerUp: _endDrag,
      onPointerCancel: _endDrag,
      child: ColoredBox(color: context.diffTheme.codeBg, child: body),
    );
  }
}
