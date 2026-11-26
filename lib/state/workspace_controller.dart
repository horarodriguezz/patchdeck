import 'dart:async';

import 'package:flutter/foundation.dart';

import '../diff/diff_layout.dart';
import '../diff/diff_parser.dart';
import '../models/app_settings.dart';
import '../models/ids.dart';
import '../models/review.dart';
import '../services/review_repository.dart';
import 'patch_model.dart';
import 'sync_merge.dart';

/// Owns one open review: its patches (parsed lazily, off-thread), comments,
/// markdown panels and per-pane view state. Persists with a short debounce.
class WorkspaceController extends ChangeNotifier {
  WorkspaceController({required this.repo, required this.review, required this.highlight, this.onSaved}) {
    for (final p in review.patches) {
      _parse(p);
    }
    if (review.patches.isNotEmpty) _visible.add(review.patches.first.id);
    _base = ReviewSnapshot.of(review);
    // Changes made by other processes (the MCP server) while it's open.
    _external = repo.changes.listen((c) {
      final fresh = c.review;
      if (c.id == review.id && fresh != null && !_disposed) applyExternal(fresh);
    });
  }

  final ReviewRepository repo;
  final Review review;

  /// Called after each persisted save (e.g. to refresh the reviews list).
  final VoidCallback? onSaved;
  bool highlight;

  final Map<String, PatchModel> _models = {};
  final Map<String, Future<void>> _parsing = {};
  final List<String> _visible = [];
  final Map<String, Set<int>> _collapsed = {};
  final Set<String> _collapsedInit = {};
  final Map<String, _LayoutCacheEntry> _layoutCache = {};
  int _commentsVersion = 0;
  Timer? _saveTimer;
  bool _disposed = false;

  /// What the file looked like the last time we read or wrote it.
  late ReviewSnapshot _base;
  StreamSubscription<ReviewChange>? _external;

  bool leftOpen = false;
  bool rightOpen = true;

  /// 0 = context, 1 = comments, 2 = files.
  int leftTab = 0;

  /// A line a pane should scroll to on its next build (see [reveal]).
  LineKey? _pendingReveal;
  bool _pendingRevealIfNeeded = false;
  String? _pendingRevealComment;

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
      // Files already marked as viewed start collapsed (GitHub behaviour).
      if (!_collapsedInit.contains(p.id)) {
        _collapsedInit.add(p.id);
        final s = _collapsed.putIfAbsent(p.id, () => {});
        for (var f = 0; f < parsed.files.length; f++) {
          if (review.viewedFiles.contains(Review.viewedKey(p.id, parsed.files[f].path))) s.add(f);
        }
      }
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
    final p = PatchEntry(
      id: newId(),
      name: name.trim().isEmpty ? nextPatchName(patches.map((e) => e.name)) : name.trim(),
      raw: raw,
      createdAt: DateTime.now(),
    );
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
    review.viewedFiles.removeWhere((k) => k.startsWith('$id|'));
    if (_visible.isEmpty && review.patches.isNotEmpty) _visible.add(review.patches.first.id);
    // Drop anchors pointing at the removed patch; drop comments left empty.
    for (var i = review.comments.length - 1; i >= 0; i--) {
      final c = review.comments[i];
      final anchors = [
        for (final a in c.anchors)
          if (a.patchId != id) a,
      ];
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

  // ---------------------------------------------------------------- viewed

  bool isViewed(String patchId, int file) {
    final m = _models[patchId];
    if (m == null || file < 0 || file >= m.parsed.files.length) return false;
    return review.viewedFiles.contains(Review.viewedKey(patchId, m.parsed.files[file].path));
  }

  int viewedCount(String patchId) {
    final m = _models[patchId];
    if (m == null) return 0;
    var n = 0;
    for (final f in m.parsed.files) {
      if (review.viewedFiles.contains(Review.viewedKey(patchId, f.path))) n++;
    }
    return n;
  }

  /// Marking a file as viewed collapses it; unmarking expands it again.
  void setViewed(String patchId, int file, bool viewed) {
    final m = _models[patchId];
    if (m == null || file < 0 || file >= m.parsed.files.length) return;
    final key = Review.viewedKey(patchId, m.parsed.files[file].path);
    final changed = viewed ? review.viewedFiles.add(key) : review.viewedFiles.remove(key);
    if (!changed) return;
    final s = _collapsed.putIfAbsent(patchId, () => {});
    viewed ? s.add(file) : s.remove(file);
    _layoutCache.remove(patchId);
    _changed();
  }

  /// Cached: rebuilt only when the mode, font, collapsed set or comments
  /// change, or when [commentWidth] (the text width of inline comments,
  /// measured by [commentExtent]) changes and the patch has comments.
  DiffLayout? layout(
    String patchId,
    DiffMode mode,
    DiffMetrics metrics, {
    double commentWidth = 0,
    double Function(ReviewComment comment, double width)? commentExtent,
  }) {
    final m = _models[patchId];
    if (m == null) return null;
    final c = _layoutCache[patchId];
    if (c != null &&
        c.mode == mode &&
        c.fontSize == metrics.fontSize &&
        c.commentsVersion == _commentsVersion &&
        (c.commentWidth == commentWidth || !c.layout.hasComments)) {
      return c.layout;
    }
    final l = buildDiffLayout(
      patchId: patchId,
      patch: m.parsed,
      mode: mode,
      metrics: metrics,
      collapsedFiles: collapsedFiles(patchId),
      commentsByLine: _commentsByLine(m),
      commentExtent: commentExtent == null
          ? null
          : (id) {
              final cm = comment(id);
              return cm == null ? DiffMetrics.comment : commentExtent(cm, commentWidth);
            },
    );
    _layoutCache[patchId] = _LayoutCacheEntry(mode, metrics.fontSize, _commentsVersion, commentWidth, l);
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
    review.comments.add(
      ReviewComment(
        id: newId(),
        anchors: anchorsFor(keys),
        labelIds: labelIds,
        text: text,
        createdAt: now,
        updatedAt: now,
      ),
    );
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
        // +1 so whole-file keys (-1) sort first within their file.
        final pos = k == null ? 1 << 50 : (k.$2 << 40) | ((k.$3 + 1) << 20) | (k.$4 + 1);
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
          (k.$1 == best.$1 &&
              (k.$2 < best.$2 || (k.$2 == best.$2 && (k.$3 < best.$3 || (k.$3 == best.$3 && k.$4 < best.$4)))))) {
        best = k;
      }
    }
    return best;
  }

  /// Makes the line's patch visible, expands its file and asks the pane to
  /// scroll there. With [ifNeeded] the pane only scrolls if the line is off
  /// screen; with [commentId] it scrolls to that comment's inline card.
  void reveal(LineKey k, {bool ifNeeded = false, String? commentId}) {
    if (!_visible.contains(k.$1)) {
      _visible
        ..clear()
        ..add(k.$1);
    }
    if (_collapsed[k.$1]?.remove(k.$2) ?? false) _layoutCache.remove(k.$1);
    _pendingReveal = k;
    _pendingRevealIfNeeded = ifNeeded;
    _pendingRevealComment = commentId;
    notifyListeners();
  }

  (LineKey, bool, String?)? takeReveal(String patchId) {
    final k = _pendingReveal;
    if (k == null || k.$1 != patchId) return null;
    _pendingReveal = null;
    return (k, _pendingRevealIfNeeded, _pendingRevealComment);
  }

  /// Jumps to file [file] of [patchId] (expanding it).
  void revealFile(String patchId, int file) => reveal(fileKey(patchId, file));

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

  /// Opens the left panel on [tab]; if it is already showing it, closes it.
  void toggleLeftTab(int tab) {
    if (leftOpen && leftTab == tab) {
      leftOpen = false;
      notifyListeners();
    } else {
      openLeftTab(tab);
    }
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

  // ------------------------------------------------------- external changes

  /// Merges a version of this review written by another process (e.g. the
  /// MCP server) into the open one: comments, patches, labels, notes… show up
  /// without reopening it, and unsaved local edits are kept.
  void applyExternal(Review fresh) {
    final viewedBefore = Set.of(review.viewedFiles);
    mergeReviewInto(review, _base, fresh);
    _base = ReviewSnapshot.of(fresh);
    _syncPatches();
    _syncViewedCollapse(viewedBefore);
    _commentsVersion++;
    _layoutCache.clear();
    notifyListeners();
  }

  /// Parses added / changed patches and forgets removed ones.
  void _syncPatches() {
    final ids = {for (final p in review.patches) p.id};
    _models.removeWhere((id, _) => !ids.contains(id));
    _collapsed.removeWhere((id, _) => !ids.contains(id));
    _collapsedInit.removeWhere((id) => !ids.contains(id));
    _visible.removeWhere((id) => !ids.contains(id));
    for (final p in review.patches) {
      final m = _models[p.id];
      if (m == null) {
        if (!_parsing.containsKey(p.id)) _parse(p);
      } else if (m.entry.raw != p.raw) {
        _models.remove(p.id);
        _parse(p);
      } else {
        m.entry = p;
      }
    }
    if (_visible.isEmpty && review.patches.isNotEmpty) _visible.add(review.patches.first.id);
  }

  /// Files marked / unmarked as viewed elsewhere collapse / expand here too.
  void _syncViewedCollapse(Set<String> before) {
    final now = review.viewedFiles;
    if (now.length == before.length && now.containsAll(before)) return;
    for (final m in _models.values) {
      final s = _collapsed.putIfAbsent(m.id, () => {});
      for (var f = 0; f < m.parsed.files.length; f++) {
        final key = Review.viewedKey(m.id, m.parsed.files[f].path);
        final was = before.contains(key), is_ = now.contains(key);
        if (is_ && !was) s.add(f);
        if (was && !is_) s.remove(f);
      }
    }
  }

  // ----------------------------------------------------------- persistence

  void _changed() {
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    review.updatedAt = DateTime.now();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    // Someone else wrote the file since we last synced: merge before saving so
    // their changes aren't overwritten (the watcher may not have fired yet).
    if (await repo.changedOnDisk(review.id)) {
      final fresh = await repo.load(review.id);
      if (fresh != null && !_disposed) applyExternal(fresh);
    }
    await repo.save(review);
    _base = ReviewSnapshot.of(review);
    onSaved?.call();
  }

  Future<void> flush() async {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      await _save();
    }
  }

  bool isParsing(String id) => _parsing.containsKey(id);

  @override
  void dispose() {
    _disposed = true;
    _external?.cancel();
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      repo.save(review);
    }
    super.dispose();
  }
}

class _LayoutCacheEntry {
  _LayoutCacheEntry(this.mode, this.fontSize, this.commentsVersion, this.commentWidth, this.layout);
  final DiffMode mode;
  final double fontSize;
  final int commentsVersion;
  final double commentWidth;
  final DiffLayout layout;
  Set<LineKey>? commented;
}
