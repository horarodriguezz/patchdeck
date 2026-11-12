import 'package:flutter/foundation.dart';

/// Global navigation: which review is open and whether the reviews sidebar
/// is expanded. The sidebar starts open and collapses when a review opens.
class ShellController extends ChangeNotifier {
  String? _openReviewId;
  bool _sidebarOpen = true;

  String? get openReviewId => _openReviewId;
  bool get sidebarOpen => _sidebarOpen;

  void openReview(String id) {
    _openReviewId = id;
    _sidebarOpen = false;
    notifyListeners();
  }

  void closeReview() {
    _openReviewId = null;
    _sidebarOpen = true;
    notifyListeners();
  }

  void toggleSidebar() {
    _sidebarOpen = !_sidebarOpen;
    notifyListeners();
  }
}
