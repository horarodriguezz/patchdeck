import 'dart:async';
import 'dart:io';

import '../models/review.dart';
import 'app_paths.dart';
import 'dir_watcher.dart';
import 'json_store.dart';

/// A review file that changed on disk because of another process (e.g. the
/// Patchdeck MCP server). [review] is null when the file was deleted.
typedef ReviewChange = ({String id, Review? review});

/// One JSON file per review plus a small index used by the home screen.
class ReviewRepository {
  ReviewRepository(this.paths);
  final AppPaths paths;

  List<ReviewSummary>? _index;

  /// Stamp of each review file as we last read or wrote it.
  final Map<String, FileStamp?> _known = {};
  DirWatcher? _watcher;
  final StreamController<ReviewChange> _changes = StreamController.broadcast();

  static final RegExp _idRe = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  /// External changes (only emitted after [watch]).
  Stream<ReviewChange> get changes => _changes.stream;

  Future<List<ReviewSummary>> list() async {
    if (_index != null) return List.of(_index!);
    final json = await JsonStore.read(paths.reviewsIndex);
    if (json is List) {
      _index = [for (final e in json) ReviewSummary.fromJson((e as Map).cast<String, dynamic>())];
    } else {
      _index = await _rebuildIndex();
    }
    _sort();
    return List.of(_index!);
  }

  Future<Review?> load(String id) async {
    final file = paths.reviewFile(id);
    final stamp = await JsonStore.stamp(file);
    final json = await JsonStore.read(file);
    _known[id] = stamp;
    return json is Map<String, dynamic> ? Review.fromJson(json) : null;
  }

  Future<void> save(Review review) async {
    final file = paths.reviewFile(review.id);
    await JsonStore.write(file, review.toJson(), pretty: false);
    _known[review.id] = await JsonStore.stamp(file);
    final idx = await list();
    idx.removeWhere((s) => s.id == review.id);
    idx.add(review.summary);
    _index = idx;
    _sort();
    await _writeIndex();
  }

  Future<void> delete(String id) async {
    final f = paths.reviewFile(id);
    if (await f.exists()) await f.delete();
    _known.remove(id);
    final idx = await list();
    idx.removeWhere((s) => s.id == id);
    _index = idx;
    await _writeIndex();
  }

  /// Whether the file changed since we last read or wrote it.
  Future<bool> changedOnDisk(String id) async {
    final now = await JsonStore.stamp(paths.reviewFile(id));
    return now != _known[id];
  }

  /// Starts watching the reviews directory for changes made by other
  /// processes; they keep the index up to date and are reported on [changes].
  Future<void> watch() async {
    if (_watcher != null) return;
    final w = _watcher = DirWatcher(paths.reviewsDir, accept: (name) => name.endsWith('.json') && name != 'index.json');
    w.changes.listen((path) {
      final name = DirWatcher.baseName(path);
      _onFileChanged(name.substring(0, name.length - 5));
    });
    await w.start();
  }

  Future<void> _onFileChanged(String id) async {
    if (!_idRe.hasMatch(id)) return;
    final stamp = await JsonStore.stamp(paths.reviewFile(id));
    if (stamp != null && _known.containsKey(id) && stamp == _known[id]) return; // our own write
    final idx = await list();
    if (stamp == null) {
      final had = idx.any((s) => s.id == id);
      _known.remove(id);
      if (!had) return;
      _index = idx..removeWhere((s) => s.id == id);
      await _writeIndex();
      _emit((id: id, review: null));
      return;
    }
    final review = await load(id);
    if (review == null) return;
    idx.removeWhere((s) => s.id == id);
    idx.add(review.summary);
    _index = idx;
    _sort();
    await _writeIndex();
    _emit((id: id, review: review));
  }

  /// Reports a change made through this repository by someone other than the
  /// open workspace (e.g. renaming from the sidebar) so the workspace merges it.
  void announce(Review review) => _emit((id: review.id, review: Review.fromJson(review.toJson())));

  void _emit(ReviewChange c) {
    if (!_changes.isClosed) _changes.add(c);
  }

  Future<void> dispose() async {
    await _watcher?.dispose();
    _watcher = null;
    await _changes.close();
  }

  void _sort() => _index!.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<void> _writeIndex() => JsonStore.write(paths.reviewsIndex, [for (final s in _index!) s.toJson()]);

  Future<List<ReviewSummary>> _rebuildIndex() async {
    final dir = paths.reviewsDir;
    if (!await dir.exists()) return [];
    final out = <ReviewSummary>[];
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.json') || e.path.endsWith('index.json')) continue;
      final json = await JsonStore.read(e);
      if (json is Map<String, dynamic>) out.add(Review.fromJson(json).summary);
    }
    return out;
  }
}
