import 'package:flutter/foundation.dart';

import '../diff/diff_layout.dart';

/// The code text currently selected with the mouse, shared by every pane of
/// the workspace: only one pane holds a selection at a time, and Ctrl+F uses
/// it to prefill the search.
class CodeSelection extends ChangeNotifier {
  Object? _owner;
  String _text = '';
  LineKey? _startKey;
  int _startCol = 0;

  Object? get owner => _owner;
  String get text => _text;
  bool get isEmpty => _text.isEmpty;

  /// Line and column where the selection starts (to land the search on it).
  LineKey? get startKey => _startKey;
  int get startCol => _startCol;

  /// [owner] takes over: other panes drop their highlight when notified.
  void claim(Object owner) {
    if (identical(_owner, owner)) return;
    _owner = owner;
    _text = '';
    _startKey = null;
    notifyListeners();
  }

  void publish(Object owner, String text, LineKey? startKey, int startCol) {
    _owner = owner;
    _text = text;
    _startKey = startKey;
    _startCol = startCol;
    notifyListeners();
  }

  void release(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _text = '';
    _startKey = null;
    notifyListeners();
  }
}
