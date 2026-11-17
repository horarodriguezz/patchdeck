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
import '../../diff/diff_models.dart';
import 'comment_callbacks.dart';
import '../../state/code_selection.dart';
import '../../state/diff_search.dart';
import '../../state/patch_model.dart';
import '../../state/selection_controller.dart';
import '../../state/workspace_controller.dart';
import '../../theme/app_themes.dart';
import '../../theme/diff_theme.dart';
import 'diff_rows.dart';
import 'h_scrollbar.dart';
import 'code_text.dart';
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
    required this.codeSelection,
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
  final CodeSelection codeSelection;

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

  // Geometry of the last build, used to map pointer positions to text.
  double _viewWidth = 0;
  double _numberWidth = 0;
  TextStyle _codeStyle = const TextStyle();
  bool _stickyShown = false;

  /// Mouse text selection (rows of [DiffView.layout], columns in the line).
  _TextSel? _sel;
  bool _textDragging = false;
  final ValueNotifier<int> _selVersion = ValueNotifier(0);
  final FocusNode _focus = FocusNode(debugLabel: 'diff-text');
  DateTime _lastDown = DateTime(0);
  int _clicks = 0;
  int _lastDownRow = -1;

  @override
  void initState() {
    super.initState();
    widget.search.addListener(_onSearch);
    widget.codeSelection.addListener(_onCodeSelection);
  }

  @override
  void didUpdateWidget(DiffView old) {
    super.didUpdateWidget(old);
    if (old.search != widget.search) {
      old.search.removeListener(_onSearch);
      widget.search.addListener(_onSearch);
    }
    if (old.codeSelection != widget.codeSelection) {
      old.codeSelection.removeListener(_onCodeSelection);
      widget.codeSelection.addListener(_onCodeSelection);
    }
    // Row indices are only meaningful for the layout they were taken from.
    if (!identical(old.layout, widget.layout) && _sel != null) _clearTextSelection(notify: false);
  }

  @override
  void dispose() {
    widget.search.removeListener(_onSearch);
    widget.codeSelection.removeListener(_onCodeSelection);
    widget.codeSelection.release(this);
    _autoScroll?.cancel();
    _hx.dispose();
    _selVersion.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------- text selection

  /// Another pane took the selection: drop ours.
  void _onCodeSelection() {
    if (_sel != null && !identical(widget.codeSelection.owner, this)) {
      _sel = null;
      _selVersion.value++;
    }
  }

  void _clearTextSelection({bool notify = true}) {
    _sel = null;
    _textDragging = false;
    if (notify) _selVersion.value++;
    widget.codeSelection.release(this);
  }

  /// The line shown at [row] on [side], or null (not a code line / empty side).
  DiffLine? _lineAt(int row, Side side) {
    if (row < 0 || row >= widget.layout.rows.length) return null;
    final k = widget.layout.keyAt(row, side, widget.mode);
    if (k == null) return null;
    final l = widget.model.lineFor(k);
    return l.kind == LineKind.noNewline ? null : l;
  }

  /// Left edge of [side]'s code text, in DiffView coordinates.
  double _codeLeft(Side side) {
    final unified = widget.mode == DiffMode.unified;
    final gutter = unified ? _numberWidth * 2 + 36 : _numberWidth + 36;
    if (unified || side == Side.left) return gutter;
    return (_viewWidth - 1) / 2 + 1 + gutter;
  }

  /// Column of [line] under horizontal position [x] (measured, so it works
  /// with any glyph width).
  int _colAt(DiffLine line, double x) {
    if (x <= 0) return 0;
    var text = line.text;
    if (text.length > maxRenderedChars) text = text.substring(0, maxRenderedChars);
    final tp = TextPainter(
      text: TextSpan(text: text, style: _codeStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final pos = tp.getPositionForOffset(Offset(x, tp.height / 2)).offset;
    tp.dispose();
    return pos.clamp(0, text.length);
  }

  /// (row, column) under [p] on [side]; rows that aren't code lines map to
  /// column 0, which the text extraction treats as the start of that row.
  (int, int) _posAt(Offset p, Side side) {
    final c = widget.controller;
    final rows = widget.layout.rows;
    var row = widget.layout.indexAt(p.dy + (c.hasClients ? c.offset : 0));
    if (row < 0) row = 0;
    if (row >= rows.length) row = rows.length - 1;
    final line = _lineAt(row, side);
    if (line == null) return (row, 0);
    return (row, _colAt(line, p.dx - _codeLeft(side) + _hx.value));
  }

  /// Side of the split view under [x] (unified: always left).
  Side _sideAt(double x) => widget.mode == DiffMode.unified || x < (_viewWidth - 1) / 2 ? Side.left : Side.right;

  bool _inCode(Offset p, Side side) => p.dx >= _codeLeft(side);

  void _onPointerDown(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.mouse && e.buttons == kSecondaryMouseButton) {
      if (_sel != null && !_sel!.isEmpty) _showContextMenu(e.position);
      return;
    }
    if (e.buttons != kPrimaryButton) return;
    // The gutter "+" handled this press (line selection for comments).
    if (_dragging) {
      if (_sel != null) _clearTextSelection();
      return;
    }
    final p = e.localPosition;
    if (_stickyShown && p.dy < FileHeaderRow.boxHeight) return;
    final side = _sideAt(p.dx);
    final (row, col) = _posAt(p, side);
    final line = _lineAt(row, side);
    if (line == null || !_inCode(p, side)) {
      if (_sel != null) _clearTextSelection();
      return;
    }
    _focus.requestFocus();

    // Double click selects a word, triple click the whole line.
    final now = DateTime.now();
    _clicks = now.difference(_lastDown) < const Duration(milliseconds: 400) && row == _lastDownRow ? _clicks + 1 : 1;
    _lastDown = now;
    _lastDownRow = row;

    widget.codeSelection.claim(this);
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final current = _sel;
    if (shift && current != null && current.side == side) {
      _sel = current.withFocus(row, col);
    } else if (_clicks == 2) {
      final (s, en) = _wordAt(line.text, col);
      _sel = _TextSel(side, row, s, row, en);
    } else if (_clicks >= 3) {
      _sel = _TextSel(side, row, 0, row, line.text.length + 1);
    } else {
      _sel = _TextSel(side, row, col, row, col);
    }
    _textDragging = _clicks == 1;
    _selVersion.value++;
    if (!_textDragging) _publish();
  }

  (int, int) _wordAt(String text, int col) {
    bool isWord(int i) => i >= 0 && i < text.length && RegExp(r'[\w$]').hasMatch(text[i]);
    if (!isWord(col) && isWord(col - 1)) col--;
    if (!isWord(col)) return (col, (col + 1).clamp(0, text.length));
    var s = col, e = col;
    while (isWord(s - 1)) {
      s--;
    }
    while (isWord(e)) {
      e++;
    }
    return (s, e);
  }

  void _updateTextDrag() {
    final p = _lastPointer;
    final sel = _sel;
    if (p == null || sel == null) return;
    final (row, col) = _posAt(p, sel.side);
    final next = sel.withFocus(row, col);
    if (next.focusRow == sel.focusRow && next.focusCol == sel.focusCol) return;
    _sel = next;
    _selVersion.value++;
  }

  /// Selected text, lines joined with "\n" (only lines of the anchor side).
  String _selectedText() {
    final sel = _sel;
    if (sel == null || sel.isEmpty) return '';
    final (sr, sc, er, ec) = sel.ordered;
    final out = <String>[];
    var any = false;
    for (var r = sr; r <= er; r++) {
      final line = _lineAt(r, sel.side);
      if (line == null) continue;
      final len = line.text.length;
      final s = r == sr ? sc.clamp(0, len) : 0;
      final e = r == er ? ec.clamp(0, len) : len;
      out.add(line.text.substring(s, e < s ? s : e));
      any = true;
    }
    if (!any) return '';
    // A selection that ends past the last line's text includes its newline.
    final last = _lineAt(er, sel.side);
    if (last != null && ec > last.text.length) out.add('');
    return out.join('\n');
  }

  void _publish() {
    final sel = _sel;
    if (sel == null) return;
    final (sr, sc, _, _) = sel.ordered;
    final text = _selectedText();
    final key = widget.layout.keyAt(sr, sel.side, widget.mode);
    widget.codeSelection.publish(this, text, key, sc);
  }

  /// Highlight range for [row] on [side], or null.
  ({int start, int end})? _selFor(int row, Side side) {
    final sel = _sel;
    if (sel == null || sel.isEmpty || sel.side != side) return null;
    final (sr, sc, er, ec) = sel.ordered;
    if (row < sr || row > er) return null;
    final line = _lineAt(row, side);
    if (line == null) return null;
    final len = line.text.length;
    final s = row == sr ? sc : 0;
    // Rows before the last one include their line break.
    final e = row == er ? ec : len + 1;
    if (e <= s) return null;
    return (start: s, end: e);
  }

  Future<void> _copySelection() async {
    final text = _selectedText();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _showContextMenu(Offset global) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final local = overlay.globalToLocal(global);
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(local.dx, local.dy, overlay.size.width - local.dx, 0),
      items: const [
        PopupMenuItem(value: 'copy', height: 34, child: Text('Copiar (Ctrl+C)')),
        PopupMenuItem(value: 'search', height: 34, child: Text('Buscar selección (Ctrl+F)')),
      ],
    );
    if (v == 'copy') {
      await _copySelection();
    } else if (v == 'search') {
      final text = _selectedText().split('\n').first;
      if (text.trim().isEmpty) return;
      widget.search.show(prefill: text);
      widget.search.setQuery(widget.workspace, text);
      final key = widget.codeSelection.startKey;
      if (key == null || !widget.search.selectAt(key, widget.codeSelection.startCol)) {
        final m = widget.search.step(1);
        if (m != null) widget.workspace.reveal(m.key, ifNeeded: true);
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final hk = HardwareKeyboard.instance;
    final ctrl = hk.isControlPressed || hk.isMetaPressed;
    if (ctrl && e.logicalKey == LogicalKeyboardKey.keyC && _sel != null && !_sel!.isEmpty) {
      _copySelection();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape && _sel != null) {
      _clearTextSelection();
      // Let the workspace clear the line selection too.
      return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
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
        _stickyShown = false;
        if (!c.hasClients || layout.rows.isEmpty) return const SizedBox.shrink();
        final offset = c.offset;
        final row = layout.indexAt(offset);
        if (row < 0) return const SizedBox.shrink();
        final f = layout.rows[row].file;
        if (f < 0) return const SizedBox.shrink();
        final headerTop = layout.offsets[layout.fileRow[f]] + FileHeaderRow.topGap;
        if (offset <= headerTop) return const SizedBox.shrink();
        _stickyShown = true;
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
    if (!_dragging && !_textDragging) return;
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
    if (_textDragging) {
      _updateTextDrag();
      return;
    }
    final p = _lastPointer;
    if (p == null || !widget.controller.hasClients) return;
    final y = p.dy + widget.controller.offset;
    widget.selection.dragTo(widget.layout.indexAt(y));
  }

  void _endDrag([PointerEvent? _]) {
    if (_textDragging) {
      _textDragging = false;
      _autoScroll?.cancel();
      _autoDir = 0;
      if (_sel != null && _sel!.isEmpty) {
        _clearTextSelection();
      } else {
        _publish();
      }
      return;
    }
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
              textSelection: _selFor(i, Side.left),
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
                  textSelection: _selFor(i, Side.left),
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
                  textSelection: _selFor(i, Side.right),
                ),
              ),
            ],
          );
      }
    }

    final list = ListenableBuilder(
      listenable: Listenable.merge([widget.selection, widget.search, _selVersion]),
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
        _viewWidth = c.maxWidth;
        _numberWidth = numberWidth;
        _codeStyle = codeStyle;
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

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerSignal: _onPointerSignal,
        onPointerPanZoomUpdate: _onPanZoom,
        onPointerMove: _onPointerMove,
        onPointerUp: _endDrag,
        onPointerCancel: _endDrag,
        child: ColoredBox(color: context.diffTheme.codeBg, child: body),
      ),
    );
  }
}

/// Anchor (where the press started) and focus (where the pointer is) of a
/// text selection on one side of the diff.
class _TextSel {
  const _TextSel(this.side, this.anchorRow, this.anchorCol, this.focusRow, this.focusCol);
  final Side side;
  final int anchorRow, anchorCol, focusRow, focusCol;

  bool get isEmpty => anchorRow == focusRow && anchorCol == focusCol;

  _TextSel withFocus(int row, int col) => _TextSel(side, anchorRow, anchorCol, row, col);

  /// (startRow, startCol, endRow, endCol) in document order.
  (int, int, int, int) get ordered {
    final forward = anchorRow < focusRow || (anchorRow == focusRow && anchorCol <= focusCol);
    return forward ? (anchorRow, anchorCol, focusRow, focusCol) : (focusRow, focusCol, anchorRow, anchorCol);
  }
}
