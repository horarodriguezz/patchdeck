import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../common/dialogs.dart';
import '../settings/settings_dialog.dart';
import 'title_bar.dart';

/// ≡ menu (new review, settings) + reviews-sidebar toggle.
class ShellButtons extends StatelessWidget {
  const ShellButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MenuAnchor(
          alignmentOffset: const Offset(0, 4),
          menuChildren: [
            MenuItemButton(
              leadingIcon: const Icon(Icons.add, size: 18),
              onPressed: () => createReview(context),
              child: const Text('Nueva review'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.settings_outlined, size: 18),
              onPressed: () => showSettingsDialog(context),
              child: const Text('Configuración'),
            ),
          ],
          builder: (context, controller, _) => TitleBarIconButton(
            tooltip: 'Menú',
            icon: const Icon(Icons.menu),
            onPressed: () => controller.isOpen ? controller.close() : controller.open(),
          ),
        ),
        ListenableBuilder(
          listenable: shell,
          builder: (context, _) => TitleBarIconButton(
            tooltip: shell.sidebarOpen ? 'Ocultar reviews' : 'Mostrar reviews',
            // Panel-on-the-left glyph.
            icon: Transform.flip(flipX: true, child: const Icon(Icons.view_sidebar_outlined)),
            onPressed: shell.toggleSidebar,
          ),
        ),
      ],
    );
  }
}

Future<void> createReview(BuildContext context) async {
  final scope = AppScope.of(context);
  final title = await promptText(context, title: 'Nueva review', label: 'Título', confirm: 'Crear');
  if (title == null) return;
  final review = await scope.reviews.create(title);
  scope.shell.openReview(review.id);
}
