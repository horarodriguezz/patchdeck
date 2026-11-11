import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'theme/app_themes.dart';
import 'ui/home/home_screen.dart';

class PatchdeckApp extends StatelessWidget {
  const PatchdeckApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final theme = buildThemeData(themeSpecById(settings.settings.themeId));
        return MaterialApp(
          title: 'Patchdeck',
          debugShowCheckedModeBanner: false,
          theme: theme,
          themeAnimationDuration: Duration.zero,
          home: const HomeScreen(),
        );
      },
    );
  }
}
