import 'package:flutter/widgets.dart';

import 'services/review_repository.dart';
import 'state/reviews_controller.dart';
import 'state/shell_controller.dart';
import 'state/settings_controller.dart';

/// Dependency container available to the whole widget tree.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.settings,
    required this.reviews,
    required this.reviewRepo,
    required this.shell,
    required super.child,
  });

  final SettingsController settings;
  final ReviewsController reviews;
  final ReviewRepository reviewRepo;
  final ShellController shell;

  static AppScope of(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
