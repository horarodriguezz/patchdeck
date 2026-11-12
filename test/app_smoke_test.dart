import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:patchdeck/app.dart';
import 'package:patchdeck/app_scope.dart';
import 'package:patchdeck/models/app_settings.dart';
import 'package:patchdeck/services/app_paths.dart';
import 'package:patchdeck/services/review_repository.dart';
import 'package:patchdeck/services/settings_repository.dart';
import 'package:patchdeck/state/reviews_controller.dart';
import 'package:patchdeck/state/settings_controller.dart';
import 'package:patchdeck/state/shell_controller.dart';

void main() {
  testWidgets('home renders and opens settings', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('patchdeck_test');
    final paths = AppPaths(configDir: Directory('${tmp.path}/c'), dataDir: Directory('${tmp.path}/d'));
    final repo = ReviewRepository(paths);
    final reviews = ReviewsController(repo);
    await tester.runAsync(reviews.refresh);
    await tester.pumpWidget(
      AppScope(
        settings: SettingsController(SettingsRepository(paths), AppSettings.defaults()),
        reviews: reviews,
        reviewRepo: repo,
        shell: ShellController(),
        child: const PatchdeckApp(),
      ),
    );
    await tester.pump();
    expect(find.text('Ninguna review abierta'), findsOneWidget);
    expect(find.text('Todavía no hay reviews.'), findsOneWidget);
    await tester.tap(find.byTooltip('Menú').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configuración'));
    await tester.pumpAndSettle();
    expect(find.text('Medianoche'), findsOneWidget);
  });
}
