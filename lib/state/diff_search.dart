import 'package:flutter/foundation.dart';

import '../diff/diff_layout.dart';
import '../diff/diff_models.dart';
import 'workspace_controller.dart';

/// One occurrence of the query inside a code line.
class SearchMatch {
  const SearchMatch(this.key, this.start, this.end);
  final LineKey key;
  final int start;
  final int end;
}

/// A highlighted range of a line, as handed to the line renderer.
typedef SearchMark = ({int start, int end, bool current});

/// Ctrl+F search over the code lines of the visible patches.
///
/// Matches are kept in document order (patch tab order, then file, hunk,
/// line, column) so next / previous walk the review top to bottom.
class DiffSearchController extends ChangeNotifier {
  /// Past this many matches the search stops (huge patches, 1-char queries).
  static const int maxMatches = 5000;

  bool _open = false;
  String _query = '';
  bool _caseSensitive = false;
  List<SearchMatch> _matches = const [];
  Map<LineKey, List<int>> _byLine = const {};
  int _current = -1;
  bool _truncated = false;
  Object? _signature;

  /// Bumped every time the user asks to focus the search field (Ctrl+F).
  int focusRequest = 0;

  bool get isOpen => _open;
  String get query => _query;
  bool get caseSensitive => _caseSensitive;
  List<SearchMatch> get matches => _matches;
  int get current => _current;
  bool get truncated => _truncated;
  SearchMatch? get currentMatch => _current >= 0 && _current < _matches.length ? _matches[_current] : null;

  bool get _active => _open && _query.isNotEmpty;

  /// Opens (or refocuses) the bar. [prefill] replaces the query text shown
  /// in the field; the caller runs [setQuery] with it.
  void show({String? prefill}) {
    _open = true;
    if (prefill != null) this.prefill = prefill;
    focusRequest++;
    notifyListeners();
  }

  /// Text the field should show on its next focus request (see [show]).
  String? prefill;

  /// Makes the match at [key] / [start] the current one, if there is one.
  bool selectAt(LineKey key, int start) {
    final idx = _byLine[key];
    if (idx == null) return false;
    for (final i in idx) {
      if (_matches[i].start == start) {
        _current = i;
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  void hide() {
    if (!_open) return;
    _open = false;
    notifyListeners();
  }

  /// Highlight ranges for [key], or null when the line has no match.
  List<SearchMark>? marksFor(LineKey key) {
    if (!_active) return null;
    final idx = _byLine[key];
    if (idx == null) return null;
    return [for (final i in idx) (start: _matches[i].start, end: _matches[i].end, current: i == _current)];
  }

  void setQuery(WorkspaceController ws, String q) {
    if (q == _query) return;
    _query = q;
    _recompute(ws, resetCurrent: true);
  }

  void setCaseSensitive(WorkspaceController ws, bool v) {
    if (v == _caseSensitive) return;
    _caseSensitive = v;
    _recompute(ws, resetCurrent: true);
  }

  /// Re-runs the search if the visible patches (or their parses) changed.
  void sync(WorkspaceController ws) {
    if (!_active) return;
    if (_signatureOf(ws) == _signature) return;
    _recompute(ws, resetCurrent: false);
  }

  /// Moves to the next (or previous) match and returns it.
  SearchMatch? step(int dir) {
    if (_matches.isEmpty) return null;
    _current = _current < 0 ? (dir > 0 ? 0 : _matches.length - 1) : (_current + dir) % _matches.length;
    notifyListeners();
    return _matches[_current];
  }

  Object _signatureOf(WorkspaceController ws) => Object.hashAll([
    for (final id in ws.visiblePatchIds) ...[id, identityHashCode(ws.model(id))],
  ]);

  void _recompute(WorkspaceController ws, {required bool resetCurrent}) {
    final previous = currentMatch;
    _signature = _signatureOf(ws);
    final out = <SearchMatch>[];
    final byLine = <LineKey, List<int>>{};
    _truncated = false;
    final needle = _caseSensitive ? _query : _query.toLowerCase();
    if (needle.isNotEmpty) {
      outer:
      for (final pid in ws.visiblePatchIds) {
        final m = ws.model(pid);
        if (m == null) continue;
        final files = m.parsed.files;
        for (var f = 0; f < files.length; f++) {
          final hunks = files[f].hunks;
          for (var h = 0; h < hunks.length; h++) {
            final lines = hunks[h].lines;
            for (var i = 0; i < lines.length; i++) {
              final line = lines[i];
              if (line.kind == LineKind.noNewline) continue;
              final hay = _caseSensitive ? line.text : line.text.toLowerCase();
              var from = 0;
              while (true) {
                final at = hay.indexOf(needle, from);
                if (at < 0) break;
                final key = (pid, f, h, i);
                (byLine[key] ??= []).add(out.length);
                out.add(SearchMatch(key, at, at + needle.length));
                if (out.length >= maxMatches) {
                  _truncated = true;
                  break outer;
                }
                from = at + needle.length;
              }
            }
          }
        }
      }
    }
    _matches = out;
    _byLine = byLine;
    _current = -1;
    if (!resetCurrent && previous != null) {
      // Keep the cursor on the same occurrence when the result set changes.
      _current = out.indexWhere((m) => m.key == previous.key && m.start == previous.start);
    }
    notifyListeners();
  }
}
