import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../diff/diff_layout.dart';
import '../../models/app_settings.dart';
import '../../models/label.dart';
import '../../models/review.dart';
import 'comment_callbacks.dart';
import '../../state/diff_search.dart';
import '../../state/patch_model.dart';
import '../../state/selection_controller.dart';
import '../../state/workspace_controller.dart';
import '../../theme/app_themes.dart';
import '../../theme/diff_theme.dart';
import 'diff_rows.dart';
import 'h_scrollbar.dart';
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
    required this.callbacks,
    required this.search,
  });

  final WorkspaceController workspace;
  final SelectionController selection;
  final PatchModel model;
  final DiffLayout layout;
  final DiffMode mode;
  final DiffMetrics metrics;
  final ScrollController controller;
  final CommentCallbacks callbacks;
  final DiffSearchController search;

  @override
  State<DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends State<DiffView> {
  /// Horizontal offset of the code columns (not a Scrollable: both split
  /// sides read the same value, so they always scroll together).
  final ValueNotifier<double> _hx = ValueNotifier(0);
  double _maxHx = 0;
  double _codeWidth = 0;
  double _charWidth = 8;
  Timer? _autoScroll;
  double _autoDir = 0;
  Offset? _lastPointer;
  bool _dragging = false;

  int _cacheVersion = -1;
  Map<String, int> _commentsPerPath = const {};

  SearchMatch? _lastMatch;

  @override
  void initState() {
    super.initState();
    widget.search.addListener(_onSearch);
  }

  @override
  void didUpdateWidget(DiffView old) {
    super.didUpdateWidget(old);
    if (old.search != widget.search) {
      old.search.removeListener(_onSearch);
      widget.search.addListener(_onSearch);
    }
  }

  @override
  void dispose() {
    widget.search.removeListener(_onSearch);
    _autoScroll?.cancel();
    _hx.dispose();
    super.dispose();
  }

  /// Scrolls the code horizontally so the active search match is visible.
  void _onSearch() {
    final m = widget.search.currentMatch;
    if (m == null || identical(m, _lastMatch) || m.key.$1 != widget.model.id) {
      _lastMatch = m;
      return;
    }
    _lastMatch = m;
    if (_maxHx <= 0 || _codeWidth <= 0) return;
    final left = m.start * _charWidth;
    final right = m.end * _charWidth;
    const margin = 48.0;
    var x = _hx.value;
    if (left < x + margin) {
      x = left - margin;
    } else if (right > x + _codeWidth - margin) {
      x = right - _codeWidth + margin;
    }
    _hx.value = x.clamp(0.0, _maxHx);
  }

  // ---------------------------------------------------------- file headers

  /// Toggling from the pinned header jumps back to the file's top, so the
  /// user doesn't lose their place when a long file collapses under them.
  void _afterHeaderChange(int file, bool fromSticky) {
    if (!fromSticky) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = widget.controller;
      if (!mounted || !c.hasClients) return;
      final l = widget.layout;
      if (file >= l.fileRow.length) return;
      c.jumpTo(l.offsets[l.fileRow[file]].clamp(0.0, c.position.maxScrollExtent));
    });
  }

  Widget _fileHeader(int f, Map<String, int> counts, Set<int> collapsed, {bool sticky = false}) {
    final file = widget.model.parsed.files[f];
    final pid = widget.model.id;
    final ws = widget.workspace;
    return FileHeaderRow(
      file: file,
      sticky: sticky,
      collapsed: collapsed.contains(f),
      commentCount: counts[file.path] ?? 0,
      viewed: ws.isViewed(pid, f),
      onToggle: () {
        ws.toggleFile(pid, f);
        _afterHeaderChange(f, sticky);
      },
      onViewedChanged: (v) {
        ws.setViewed(pid, f, v);
        _afterHeaderChange(f, sticky);
      },
    );
  }

  /// The header of the file at the top of the viewport, pinned while its
  /// own row is scrolled out; the next header pushes it up.
  Widget _stickyHeader(Map<String, int> counts, Set<int> collapsed) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final layout = widget.layout;
        if (!c.hasClients || layout.rows.isEmpty) return const SizedBox.shrink();
        final offset = c.offset;
        final row = layout.indexAt(offset);
        if (row < 0) return const SizedBox.shrink();
        final f = layout.rows[row].file;
        if (f < 0) return const SizedBox.shrink();
        final headerTop = layout.offsets[layout.fileRow[f]] + FileHeaderRow.topGap;
        if (offset <= headerTop) return const SizedBox.shrink();
        var dy = 0.0;
        if (f + 1 < layout.fileRow.length) {
          final nextTop = layout.offsets[layout.fileRow[f + 1]] + FileHeaderRow.topGap;
          dy = math.min(0.0, nextTop - offset - FileHeaderRow.boxHeight);
        }
        return ClipRect(
          child: Transform.translate(offset: Offset(0, dy), child: _fileHeader(f, counts, collapsed, sticky: true)),
        );
      },
    );
  }

  // ------------------------------------------------------- horizontal scroll

  /// Shift+wheel (or a horizontal wheel/trackpad delta) scrolls the code.
  /// At the edges the event is left unclaimed so it chains to the outer pane
  /// strip, which keeps Shift+wheel working to move between patches.
  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || _maxHx <= 0) return;
    var dx = e.scrollDelta.dx;
    if (dx == 0 && HardwareKeyboard.instance.isShiftPressed) dx = e.scrollDelta.dy;
    if (dx == 0) return;
    final next = (_hx.value + dx).clamp(0.0, _maxHx);
    if (next == _hx.value) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (_) {
      _hx.value = (_hx.value + dx).clamp(0.0, _maxHx);
    });
  }

  void _onPanZoom(PointerPanZoomUpdateEvent e) {
    final d = e.panDelta;
    if (_maxHx <= 0 || d.dx.abs() <= d.dy.abs()) return;
    _hx.value = (_hx.value - d.dx).clamp(0.0, _maxHx);
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
        final paths = <String>{
          for (final a in c.anchors)
            if (a.patchId == widget.model.id) a.path,
        };
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
    final search = widget.search;

    Widget buildRow(BuildContext context, int i) {
      final row = layout.rows[i];
      switch (row.kind) {
        case RowKind.preamble:
          return PreambleRow(text: widget.model.parsed.preamble, style: codeStyle);
        case RowKind.fileHeader:
          return _fileHeader(row.file, counts, collapsed);
        case RowKind.notice:
          return NoticeRow(file: widget.model.parsed.files[row.file]);
        case RowKind.hunk:
          return HunkRow(hunk: widget.model.parsed.files[row.file].hunks[row.hunk], style: codeStyle);
        case RowKind.gap:
          return const SizedBox.shrink();
        case RowKind.comment:
          final c = widget.workspace.comment(row.commentId!);
          if (c == null) return const SizedBox.shrink();
          final labels = <ReviewLabel>[for (final id in c.labelIds) ?settings.labelById(id)];
          return CommentRow(
            comment: c,
            labels: labels,
            summary: _commentSummary(c),
            indent: codeIndent,
            onEdit: () => widget.callbacks.edit(c),
            onDelete: () => widget.callbacks.delete(c),
            onCopy: () => widget.callbacks.copy(c, widget.model.id),
            onToggleDismissed: () => widget.callbacks.toggleDismissed(c),
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
              hOffset: _hx,
              marks: search.marksFor(key),
            );
          }
          final lk = row.a >= 0 ? (pid, row.file, row.hunk, row.a) : null;
          final rk = row.b >= 0 ? (pid, row.file, row.hunk, row.b) : null;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                  hOffset: _hx,
                  marks: lk == null ? null : search.marksFor(lk),
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
                  hOffset: _hx,
                  // A context line appears on both sides; highlight it once.
                  marks: rk == null || rk == lk ? null : search.marksFor(rk),
                ),
              ),
            ],
          );
      }
    }

    final list = ListenableBuilder(
      listenable: Listenable.merge([widget.selection, widget.search]),
      builder: (context, _) => ListView.builder(
        controller: widget.controller,
        padding: const EdgeInsets.only(bottom: 280),
        itemCount: layout.rows.length,
        itemExtentBuilder: (i, _) => i < layout.rows.length ? layout.extent(i) : null,
        addAutomaticKeepAlives: false,
        itemBuilder: buildRow,
      ),
    );

    // Explicit scrollbar only (the platform default would add a duplicate).
    final noAutoBars = ScrollConfiguration.of(context).copyWith(scrollbars: false);
    final charWidth = monoCharWidth(codeStyle);
    final gutter = unified ? numberWidth * 2 + 36 : numberWidth + 36;

    final body = LayoutBuilder(
      builder: (context, c) {
        final codeWidth = (unified ? c.maxWidth : (c.maxWidth - 1) / 2) - gutter;
        final contentWidth = math.min(layout.maxLineChars, 2000) * charWidth + 32;
        _maxHx = math.max(0.0, contentWidth - codeWidth);
        _codeWidth = codeWidth;
        _charWidth = charWidth;
        if (_hx.value > _maxHx) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _hx.value = math.min(_hx.value, _maxHx));
        }
        return Stack(
          children: [
            Positioned.fill(
              child: Scrollbar(
                controller: widget.controller,
                // The pinned header sits under the scrollbar thumb.
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ScrollConfiguration(behavior: noAutoBars, child: list),
                    ),
                    Positioned(top: 0, left: 0, right: 0, child: _stickyHeader(counts, collapsed)),
                  ],
                ),
              ),
            ),
            if (_maxHx > 0)
              Positioned(
                left: unified ? gutter : 0,
                right: 14,
                bottom: 0,
                child: unified
                    ? HScrollBar(offset: _hx, maxOffset: _maxHx, viewport: codeWidth)
                    : Row(
                        children: [
                          // In split view one thumb per side, both bound to the same offset.
                          SizedBox(width: gutter),
                          Expanded(
                            child: HScrollBar(offset: _hx, maxOffset: _maxHx, viewport: codeWidth),
                          ),
                          SizedBox(width: gutter + 1),
                          Expanded(
                            child: HScrollBar(offset: _hx, maxOffset: _maxHx, viewport: codeWidth),
                          ),
                        ],
                      ),
              ),
          ],
        );
      },
    );

    return Listener(
      onPointerSignal: _onPointerSignal,
      onPointerPanZoomUpdate: _onPanZoom,
      onPointerMove: _onPointerMove,
      onPointerUp: _endDrag,
      onPointerCancel: _endDrag,
      child: ColoredBox(color: context.diffTheme.codeBg, child: body),
    );
  }
}
