import 'package:flutter/material.dart';

import 'app.dart';
import 'app_scope.dart';
import 'services/app_paths.dart';
import 'services/review_repository.dart';
import 'services/settings_repository.dart';
import 'services/system_fonts.dart';
import 'state/reviews_controller.dart';
import 'state/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final paths = AppPaths.fromEnvironment();
  final fonts = SystemFonts.detect(); // runs concurrently with settings loading
  final settingsRepo = SettingsRepository(paths);
  final reviewRepo = ReviewRepository(paths);
  final settings = SettingsController(settingsRepo, await settingsRepo.load());
  final reviews = ReviewsController(reviewRepo)..refresh();
  SystemFonts.current = await fonts;

  runApp(AppScope(
    settings: settings,
    reviews: reviews,
    reviewRepo: reviewRepo,
    child: const PatchdeckApp(),
  ));
}
