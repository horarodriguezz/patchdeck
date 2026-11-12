import 'package:flutter/foundation.dart';

import '../models/ids.dart';
import '../models/review.dart';
import '../services/review_repository.dart';

class ReviewsController extends ChangeNotifier {
  ReviewsController(this.repo);

  final ReviewRepository repo;
  List<ReviewSummary> _items = const [];
  bool _loading = true;

  List<ReviewSummary> get items => _items;
  bool get loading => _loading;

  Future<void> refresh() async {
    _items = await repo.list();
    _loading = false;
    notifyListeners();
  }

  Future<Review> create(String title) async {
    final now = DateTime.now();
    final r = Review(
      id: newId(),
      title: title.trim().isEmpty ? 'Review sin título' : title.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await repo.save(r);
    await refresh();
    return r;
  }

  Future<void> rename(String id, String title) async {
    final r = await repo.load(id);
    if (r == null) return;
    r
      ..title = title
      ..updatedAt = DateTime.now();
    await repo.save(r);
    await refresh();
  }

  Future<void> delete(String id) async {
    await repo.delete(id);
    await refresh();
  }
}
