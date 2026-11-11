import 'package:flutter/material.dart';

import 'app.dart';
import 'app_scope.dart';
import 'services/app_paths.dart';
import 'services/review_repository.dart';
import 'services/settings_repository.dart';
import 'state/reviews_controller.dart';
import 'state/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final paths = AppPaths.fromEnvironment();
  final settingsRepo = SettingsRepository(paths);
  final reviewRepo = ReviewRepository(paths);
  final settings = SettingsController(settingsRepo, await settingsRepo.load());
  final reviews = ReviewsController(reviewRepo)..refresh();

  runApp(AppScope(
    settings: settings,
    reviews: reviews,
    reviewRepo: reviewRepo,
    child: const PatchdeckApp(),
  ));
}
