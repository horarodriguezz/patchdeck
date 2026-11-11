import 'dart:io';

import '../models/review.dart';
import 'app_paths.dart';
import 'json_store.dart';

/// One JSON file per review plus a small index used by the home screen.
class ReviewRepository {
  ReviewRepository(this.paths);
  final AppPaths paths;

  List<ReviewSummary>? _index;

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
    final json = await JsonStore.read(paths.reviewFile(id));
    return json is Map<String, dynamic> ? Review.fromJson(json) : null;
  }

  Future<void> save(Review review) async {
    await JsonStore.write(paths.reviewFile(review.id), review.toJson(), pretty: false);
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
    final idx = await list();
    idx.removeWhere((s) => s.id == id);
    _index = idx;
    await _writeIndex();
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
