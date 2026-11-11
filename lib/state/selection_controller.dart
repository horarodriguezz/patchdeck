import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../diff/diff_layout.dart';
import '../models/app_settings.dart';

class _Drag {
  _Drag(this.layout, this.mode, this.startRow, this.side, this.base, this.removing);
  final DiffLayout layout;
  final DiffMode mode;
  final int startRow;
  final Side side;
  final Set<LineKey> base;
  final bool removing;
  int lastRow = -1;
}

/// Line selection shared by every pane of the workspace, so one comment can
/// target lines in several files and even several patches.
///
/// * click `+`          → select that line only
/// * drag `+`           → select a contiguous range (within a file)
/// * ctrl+click / drag  → add to (or remove from) the current selection
/// * shift+click        → extend from the last clicked line
class SelectionController extends ChangeNotifier {
  final LinkedHashSet<LineKey> _selected = LinkedHashSet();
  _Drag? _drag;
  (DiffLayout, int, Side)? _lastClick;

  /// Set when the composer is editing an existing comment.
  String? editingCommentId;

  /// Bumped whenever the selection goes from empty to non-empty or the
  /// edited comment changes, so the composer can reset itself.
  int session = 0;

  Set<LineKey> get selected => _selected;
  bool get isEmpty => _selected.isEmpty;
  bool get isDragging => _drag != null;
  bool isSelected(LineKey k) => _selected.contains(k);

  void begin(DiffLayout layout, DiffMode mode, int row, Side side, {required bool ctrl, required bool shift}) {
    final key = layout.keyAt(row, side, mode);
    if (key == null) return;
    final wasEmpty = _selected.isEmpty;
    if (editingCommentId != null && !ctrl) {
      editingCommentId = null;
      session++;
    }
    final last = _lastClick;
    if (shift && last != null && identical(last.$1, layout) && layout.rows[last.$2].file == layout.rows[row].file) {
      _selected.addAll(layout.keysInRange(last.$2, row, last.$3, mode));
      if (wasEmpty) session++;
      notifyListeners();
      return;
    }
    final base = ctrl ? Set.of(_selected) : <LineKey>{};
    final removing = ctrl && _selected.contains(key);
    _drag = _Drag(layout, mode, row, side, base, removing);
    _lastClick = (layout, row, side);
    _apply(row);
    if (wasEmpty) session++;
  }

  void dragTo(int row) {
    final d = _drag;
    if (d == null || row < 0 || row >= d.layout.rows.length || row == d.lastRow) return;
    _apply(row);
  }

  void end() => _drag = null;

  void _apply(int row) {
    final d = _drag!;
    d.lastRow = row;
    final range = d.layout.keysInRange(d.startRow, row, d.side, d.mode);
    _selected
      ..clear()
      ..addAll(d.base);
    if (d.removing) {
      _selected.removeAll(range);
    } else {
      _selected.addAll(range);
    }
    if (_selected.isEmpty) editingCommentId = null;
    notifyListeners();
  }

  void setSelection(Iterable<LineKey> keys, {String? editing}) {
    _selected
      ..clear()
      ..addAll(keys);
    editingCommentId = editing;
    session++;
    notifyListeners();
  }

  /// Drops keys that belong to a patch that no longer exists / was re-laid out.
  void removeWhere(bool Function(LineKey) test) {
    final before = _selected.length;
    _selected.removeWhere(test);
    if (_selected.length != before) notifyListeners();
  }

  void clear() {
    if (_selected.isEmpty && editingCommentId == null) return;
    _selected.clear();
    editingCommentId = null;
    _drag = null;
    notifyListeners();
  }
}
