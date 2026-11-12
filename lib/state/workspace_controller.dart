import 'dart:async';

import 'package:flutter/foundation.dart';

import '../diff/diff_layout.dart';
import '../diff/diff_parser.dart';
import '../models/app_settings.dart';
import '../models/ids.dart';
import '../models/review.dart';
import '../services/review_repository.dart';
import 'patch_model.dart';

/// Owns one open review: its patches (parsed lazily, off-thread), comments,
/// markdown panels and per-pane view state. Persists with a short debounce.
class WorkspaceController extends ChangeNotifier {
  WorkspaceController({required this.repo, required this.review, required this.highlight}) {
    for (final p in review.patches) {
      _parse(p);
    }
    if (review.patches.isNotEmpty) _visible.add(review.patches.first.id);
  }

  final ReviewRepository repo;
  final Review review;
  bool highlight;

  final Map<String, PatchModel> _models = {};
  final Map<String, Future<void>> _parsing = {};
  final List<String> _visible = [];
  final Map<String, Set<int>> _collapsed = {};
  final Map<String, _LayoutCacheEntry> _layoutCache = {};
  int _commentsVersion = 0;
  Timer? _saveTimer;
  bool _disposed = false;

  bool leftOpen = false;
  bool rightOpen = true;

  /// 0 = context, 1 = comments.
  int leftTab = 0;

  /// A line a pane should scroll to on its next build (see [reveal]).
  LineKey? _pendingReveal;

  // ---------------------------------------------------------------- patches

  List<PatchEntry> get patches => review.patches;
  List<String> get visiblePatchIds => _visible;
  PatchModel? model(String patchId) => _models[patchId];
  PatchEntry? entry(String id) {
    for (final p in review.patches) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _parse(PatchEntry p) {
    _parsing[p.id] = parsePatchAsync(p.raw, highlight: highlight).then((parsed) {
      if (_disposed) return;
      final current = entry(p.id);
      if (current == null) return;
      _models[p.id] = PatchModel(current, parsed);
      _parsing.remove(p.id);
      _layoutCache.remove(p.id);
      notifyListeners();
    });
  }

  /// Re-parse everything (e.g. when syntax highlighting is toggled).
  void setHighlight(bool v) {
    if (v == highlight) return;
    highlight = v;
    for (final p in review.patches) {
      _parse(p);
    }
  }

  PatchEntry addPatch(String name, String raw) {
    final p = PatchEntry(id: newId(), name: name.trim().isEmpty ? nextPatchName(patches.map((e) => e.name)) : name.trim(), raw: raw, createdAt: DateTime.now());
    review.patches.add(p);
    _parse(p);
    _visible
      ..clear()
      ..add(p.id);
    _changed();
    return p;
  }

  String get suggestedPatchName => nextPatchName(patches.map((e) => e.name));

  void renamePatch(String id, String name) {
    final i = review.patches.indexWhere((p) => p.id == id);
    if (i < 0 || name.trim().isEmpty) return;
    review.patches[i] = review.patches[i].copyWith(name: name.trim());
    _models[id]?.entry = review.patches[i];
    _changed();
  }

  void removePatch(String id) {
    review.patches.removeWhere((p) => p.id == id);
    _models.remove(id);
    _collapsed.remove(id);
    _layoutCache.remove(id);
    _visible.remove(id);
    if (_visible.isEmpty && review.patches.isNotEmpty) _visible.add(review.patches.first.id);
    // Drop anchors pointing at the removed patch; drop comments left empty.
    for (var i = review.comments.length - 1; i >= 0; i--) {
      final c = review.comments[i];
      final anchors = [for (final a in c.anchors) if (a.patchId != id) a];
      if (anchors.isEmpty) {
        review.comments.removeAt(i);
      } else if (anchors.length != c.anchors.length) {
        review.comments[i] = c.copyWith(anchors: anchors);
      }
    }
    _commentsVersion++;
    _changed();
  }

  void reorderPatch(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    review.patches.insert(newIndex, review.patches.removeAt(oldIndex));
    _visible.sort((a, b) => _patchIndex(a).compareTo(_patchIndex(b)));
    _changed();
  }

  int _patchIndex(String id) => review.patches.indexWhere((p) => p.id == id);

  /// Plain click shows a single patch; ctrl+click toggles it side by side.
  void showPatch(String id, {bool additive = false}) {
    if (additive) {
      if (_visible.contains(id)) {
        if (_visible.length > 1) _visible.remove(id);
      } else {
        _visible.add(id);
        _visible.sort((a, b) => _patchIndex(a).compareTo(_patchIndex(b)));
      }
    } else {
      _visible
        ..clear()
        ..add(id);
    }
    notifyListeners();
  }

  // --------------------------------------------------------------- layout

  Set<int> collapsedFiles(String patchId) => _collapsed[patchId] ?? const {};

  void toggleFile(String patchId, int file) {
    final s = _collapsed.putIfAbsent(patchId, () => {});
    if (!s.remove(file)) s.add(file);
    _layoutCache.remove(patchId);
    notifyListeners();
  }

  void setAllCollapsed(String patchId, bool collapsed) {
    final m = _models[patchId];
    if (m == null) return;
    _collapsed[patchId] = collapsed ? {for (var i = 0; i < m.parsed.files.length; i++) i} : {};
    _layoutCache.remove(patchId);
    notifyListeners();
  }

  /// Cached: rebuilt only when the mode, font, collapsed set or comments change.
  DiffLayout? layout(String patchId, DiffMode mode, DiffMetrics metrics) {
    final m = _models[patchId];
    if (m == null) return null;
    final c = _layoutCache[patchId];
    if (c != null && c.mode == mode && c.fontSize == metrics.fontSize && c.commentsVersion == _commentsVersion) {
      return c.layout;
    }
    final l = buildDiffLayout(
      patchId: patchId,
      patch: m.parsed,
      mode: mode,
      metrics: metrics,
      collapsedFiles: collapsedFiles(patchId),
      commentsByLine: _commentsByLine(m),
    );
    _layoutCache[patchId] = _LayoutCacheEntry(mode, metrics.fontSize, _commentsVersion, l);
    return l;
  }

  Map<LineKey, List<String>> _commentsByLine(PatchModel m) {
    final out = <LineKey, List<String>>{};
    for (final c in review.comments) {
      for (final a in c.anchors) {
        if (a.patchId != m.id) continue;
        final k = m.keyFor(a);
        if (k != null) (out[k] ??= []).add(c.id);
      }
    }
    return out;
  }

  /// Line keys that have at least one comment (for the gutter marker).
  Set<LineKey> commentedKeys(String patchId) {
    final c = _layoutCache[patchId];
    if (c != null && c.commentsVersion == _commentsVersion && c.commented != null) return c.commented!;
    final m = _models[patchId];
    if (m == null) return const {};
    final s = _commentsByLine(m).keys.toSet();
    if (c != null && c.commentsVersion == _commentsVersion) c.commented = s;
    return s;
  }

  // -------------------------------------------------------------- comments

  int get commentsVersion => _commentsVersion;
  List<ReviewComment> get comments => review.comments;

  ReviewComment? comment(String id) {
    for (final c in review.comments) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<LineAnchor> anchorsFor(Iterable<LineKey> keys) {
    final out = <LineAnchor>[];
    for (final k in keys) {
      final m = _models[k.$1];
      if (m != null) out.add(m.anchorFor(k));
    }
    return out;
  }

  List<LineKey> keysFor(ReviewComment c) {
    final out = <LineKey>[];
    for (final a in c.anchors) {
      final k = _models[a.patchId]?.keyFor(a);
      if (k != null) out.add(k);
    }
    return out;
  }

  void addComment(Iterable<LineKey> keys, List<String> labelIds, String text) {
    final now = DateTime.now();
    review.comments.add(ReviewComment(
      id: newId(),
      anchors: anchorsFor(keys),
      labelIds: labelIds,
      text: text,
      createdAt: now,
      updatedAt: now,
    ));
    _commentsVersion++;
    _changed();
  }

  void updateComment(String id, Iterable<LineKey> keys, List<String> labelIds, String text) {
    final i = review.comments.indexWhere((c) => c.id == id);
    if (i < 0) return;
    review.comments[i] = review.comments[i].copyWith(anchors: anchorsFor(keys), labelIds: labelIds, text: text);
    _commentsVersion++;
    _changed();
  }

  void restoreComment(ReviewComment c, int index) {
    review.comments.insert(index.clamp(0, review.comments.length), c);
    _commentsVersion++;
    _changed();
  }

  void setDismissed(String id, bool dismissed) {
    final i = review.comments.indexWhere((c) => c.id == id);
    if (i < 0) return;
    review.comments[i] = review.comments[i].copyWith(dismissed: dismissed);
    _commentsVersion++;
    _changed();
  }

  /// Edits labels / text without touching the anchors (used outside the diff).
  void updateCommentContent(String id, List<String> labelIds, String text) {
    final i = review.comments.indexWhere((c) => c.id == id);
    if (i < 0) return;
    review.comments[i] = review.comments[i].copyWith(labelIds: labelIds, text: text);
    _commentsVersion++;
    _changed();
  }

  /// Comments touching [patchId], ordered by where they first appear in it.
  List<ReviewComment> commentsInPatch(String patchId, {bool includeDismissed = true}) {
    final m = _models[patchId];
    final withPos = <(ReviewComment, int)>[];
    for (final c in review.comments) {
      if (!includeDismissed && c.dismissed) continue;
      var best = -1;
      for (final a in c.anchors) {
        if (a.patchId != patchId) continue;
        final k = m?.keyFor(a);
        final pos = k == null ? 1 << 50 : (k.$2 << 40) | (k.$3 << 20) | k.$4;
        if (best < 0 || pos < best) best = pos;
      }
      if (best >= 0) withPos.add((c, best));
    }
    withPos.sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final e in withPos) e.$1];
  }

  /// First line of [c] inside [patchId] (or anywhere if null).
  LineKey? firstKeyOf(ReviewComment c, [String? patchId]) {
    LineKey? best;
    for (final k in keysFor(c)) {
      if (patchId != null && k.$1 != patchId) continue;
      if (best == null ||
          (k.$1 == best.$1 && (k.$2 < best.$2 || (k.$2 == best.$2 && (k.$3 < best.$3 || (k.$3 == best.$3 && k.$4 < best.$4)))))) {
        best = k;
      }
    }
    return best;
  }

  /// Makes the line's patch visible, expands its file and asks the pane to
  /// scroll there.
  void reveal(LineKey k) {
    if (!_visible.contains(k.$1)) {
      _visible
        ..clear()
        ..add(k.$1);
    }
    if (_collapsed[k.$1]?.remove(k.$2) ?? false) _layoutCache.remove(k.$1);
    _pendingReveal = k;
    notifyListeners();
  }

  LineKey? takeReveal(String patchId) {
    final k = _pendingReveal;
    if (k == null || k.$1 != patchId) return null;
    _pendingReveal = null;
    return k;
  }

  void deleteComment(String id) {
    review.comments.removeWhere((c) => c.id == id);
    _commentsVersion++;
    _changed();
  }

  // -------------------------------------------------------- side panels

  void setContext(String md) {
    review.contextMarkdown = md;
    _scheduleSave();
  }

  void setNotes(String md) {
    review.notesMarkdown = md;
    _scheduleSave();
  }

  void toggleLeft() {
    leftOpen = !leftOpen;
    notifyListeners();
  }

  void openLeftTab(int tab) {
    leftTab = tab;
    leftOpen = true;
    notifyListeners();
  }

  void setLeftTab(int tab) {
    leftTab = tab;
    notifyListeners();
  }

  void toggleRight() {
    rightOpen = !rightOpen;
    notifyListeners();
  }

  void rename(String title) {
    if (title.trim().isEmpty) return;
    review.title = title.trim();
    _changed();
  }

  // ----------------------------------------------------------- persistence

  void _changed() {
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    review.updatedAt = DateTime.now();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () => repo.save(review));
  }

  Future<void> flush() async {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      await repo.save(review);
    }
  }

  bool isParsing(String id) => _parsing.containsKey(id);

  @override
  void dispose() {
    _disposed = true;
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      repo.save(review);
    }
    super.dispose();
  }
}

class _LayoutCacheEntry {
  _LayoutCacheEntry(this.mode, this.fontSize, this.commentsVersion, this.layout);
  final DiffMode mode;
  final double fontSize;
  final int commentsVersion;
  final DiffLayout layout;
  Set<LineKey>? commented;
}
