import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patchdeck/app.dart';
import 'package:patchdeck/app_scope.dart';
import 'package:patchdeck/diff/diff_models.dart';
import 'package:patchdeck/models/app_settings.dart';
import 'package:patchdeck/models/review.dart';
import 'package:patchdeck/services/app_paths.dart';
import 'package:patchdeck/services/review_repository.dart';
import 'package:patchdeck/services/settings_repository.dart';
import 'package:patchdeck/state/diff_search.dart';
import 'package:patchdeck/state/reviews_controller.dart';
import 'package:patchdeck/state/settings_controller.dart';
import 'package:patchdeck/state/shell_controller.dart';
import 'package:patchdeck/state/workspace_controller.dart';
import 'package:patchdeck/ui/diff/code_text.dart';
import 'package:patchdeck/ui/diff/diff_rows.dart';
import 'package:patchdeck/ui/diff/diff_view.dart';
import 'package:patchdeck/ui/workspace/search_bar.dart';

final _raw = File('test/fixtures/sample.patch').readAsStringSync();

Future<WorkspaceController> _workspace(ReviewRepository repo, Review r) async {
  final ws = WorkspaceController(repo: repo, review: r, highlight: false);
  for (var i = 0; i < 200 && ws.model(r.patches.first.id) == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return ws;
}

Review _review() => Review(
  id: 'r1',
  title: 'Review',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  patches: [PatchEntry(id: 'p1', name: 'A', raw: _raw, createdAt: DateTime(2024))],
);

Future<ShellController> _pumpWorkspace(WidgetTester tester, Size size) async {
  // Short window so the small fixture patch scrolls.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // The test font (Ahem) is wider than real fonts: ignore overflow stripes.
  final onError = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    onError?.call(d);
  };
  addTearDown(() => FlutterError.onError = onError);
  final tmp = Directory.systemTemp.createTempSync('patchdeck_ws');
  final paths = AppPaths(configDir: Directory('${tmp.path}/c'), dataDir: Directory('${tmp.path}/d'));
  final repo = ReviewRepository(paths);
  await tester.runAsync(() => repo.save(_review()));
  final reviews = ReviewsController(repo);
  await tester.runAsync(reviews.refresh);
  final shell = ShellController()..openReview('r1');
  await tester.pumpWidget(
    AppScope(
      settings: SettingsController(SettingsRepository(paths), AppSettings.defaults()),
      reviews: reviews,
      reviewRepo: repo,
      shell: shell,
      child: const PatchdeckApp(),
    ),
  );
  // Load + parse happen off the fake clock.
  for (var i = 0; i < 50 && find.byType(FileHeaderRow).evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  return shell;
}

void main() {
  test('viewed files persist, collapse, and survive a reload', () async {
    final dir = await Directory.systemTemp.createTemp('patchdeck_viewed');
    final repo = ReviewRepository(AppPaths(configDir: dir, dataDir: dir));
    final ws = await _workspace(repo, _review());
    expect(ws.viewedCount('p1'), 0);
    ws.setViewed('p1', 0, true);
    expect(ws.isViewed('p1', 0), isTrue);
    expect(ws.collapsedFiles('p1'), contains(0));
    expect(ws.viewedCount('p1'), 1);
    await ws.flush();

    final again = Review.fromJson(ws.review.toJson());
    final ws2 = await _workspace(repo, again);
    expect(ws2.isViewed('p1', 0), isTrue);
    expect(ws2.collapsedFiles('p1'), contains(0), reason: 'viewed files start collapsed');

    ws2.setViewed('p1', 0, false);
    expect(ws2.collapsedFiles('p1'), isNot(contains(0)));
    ws2.removePatch('p1');
    expect(ws2.review.viewedFiles, isEmpty);
    ws.dispose();
    ws2.dispose();
  });

  test('search finds matches in order and wraps around', () async {
    final dir = await Directory.systemTemp.createTemp('patchdeck_search');
    final repo = ReviewRepository(AppPaths(configDir: dir, dataDir: dir));
    final ws = await _workspace(repo, _review());
    final s = DiffSearchController()..show();
    s.setQuery(ws, 'e');
    expect(s.matches, isNotEmpty);
    for (var i = 1; i < s.matches.length; i++) {
      final a = s.matches[i - 1], b = s.matches[i];
      final ka = a.key, kb = b.key;
      final cmp = [ka.$2 - kb.$2, ka.$3 - kb.$3, ka.$4 - kb.$4, a.start - b.start].firstWhere((d) => d != 0);
      expect(cmp, lessThan(0));
    }
    expect(s.step(1), same(s.matches.first));
    expect(s.step(-1), same(s.matches.last));
    expect(s.marksFor(s.matches.last.key)!.any((m) => m.current), isTrue);

    final upper = s.matches.length;
    s.setCaseSensitive(ws, true);
    s.setQuery(ws, 'E');
    expect(s.matches.length, lessThan(upper));
    s.hide();
    expect(s.marksFor(s.matches.isEmpty ? ('p1', 0, 0, 0) : s.matches.first.key), isNull);
    ws.dispose();
  });

  test('code span splits syntax segments at match boundaries', () {
    const line = DiffLine(LineKind.add, null, 1, 'const foo = foo;');
    final span = buildCodeSpan(
      line,
      const TextStyle(),
      const [],
      marks: const [(start: 6, end: 9, current: false), (start: 12, end: 15, current: true)],
    );
    final parts = [for (final c in span.children!) (c as TextSpan).text];
    expect(parts.join(), 'const foo = foo;');
    expect(parts, ['const ', 'foo', ' = ', 'foo', ';']);
    final current = span.children![3] as TextSpan;
    expect(current.style!.backgroundColor, isNotNull);
  });

  testWidgets('Ctrl+F searches, Ctrl+B / Ctrl+L toggle panels, headers stick and can be marked viewed', (tester) async {
    final shell = await _pumpWorkspace(tester, const Size(1440, 480));
    expect(find.byType(FileHeaderRow), findsWidgets);

    // Panels.
    expect(find.text('Notas'), findsWidgets);
    final notesBefore = find.byTooltip('Ocultar notas (Ctrl+L)').evaluate().length;
    expect(notesBefore, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Mostrar notas (Ctrl+L)'), findsOneWidget);
    expect(find.byTooltip('Mostrar contexto y comentarios (Ctrl+B)'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Ocultar contexto y comentarios (Ctrl+B)'), findsOneWidget);

    // Search.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Buscar en los patches visibles'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'return');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'^1 de \d+$')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'^2 de \d+$')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Buscar en los patches visibles'), findsNothing);

    // Sticky header: scroll into the second file and check a pinned copy exists.
    final list = tester.widget<Scrollable>(
      find.descendant(of: find.byType(DiffView), matching: find.byType(Scrollable)).first,
    );
    final c = list.controller!;
    expect(c.position.maxScrollExtent, greaterThan(300));
    c.jumpTo(300);
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is FileHeaderRow && w.sticky), findsOneWidget);
    c.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is FileHeaderRow && w.sticky), findsNothing);

    // Viewed checkbox collapses the file.
    expect(find.textContaining('0/'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('1/'), findsOneWidget);

    shell.closeReview();
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  });

  testWidgets('code text can be selected, copied and sent to the search', (tester) async {
    final shell = await _pumpWorkspace(tester, const Size(1440, 800));
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    Finder lineText(String text) => find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == text);
    const line = 'export function greet(name: string): string {';
    final rect = tester.getRect(lineText(line));
    final cw = rect.width / line.length;
    Offset at(Rect r, int col) => Offset(r.left + (col + 0.5) * cw, r.center.dy);
    Offset boundary(Rect r, int col) => Offset(r.left + col * cw + 1, r.center.dy);

    // Double click selects the word.
    final word = at(rect, line.indexOf('greet') + 2);
    await tester.tapAt(word);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(word);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(clipboard, 'greet');

    // Ctrl+F prefills the search and lands on the selected occurrence
    // (case-insensitive: "Greeting" and the deleted line come before it).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.descendant(of: find.byType(DiffSearchBar), matching: find.byType(TextField)),
    );
    expect(field.controller!.text, 'greet');
    expect(find.text('3 de 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Dragging across lines copies them joined by newlines.
    // (wait out the double-click window so this press isn't a triple click)
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 450)));
    final next = tester.getRect(lineText('  /* say hi'));
    final g = await tester.startGesture(boundary(rect, 7));
    await tester.pump();
    await g.moveTo(boundary(next, 6));
    await tester.pump();
    await g.up();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(clipboard, 'function greet(name: string): string {\n  /* s');

    shell.closeReview();
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  });

  test('code span paints the selection and the selected line break', () {
    const line = DiffLine(LineKind.add, null, 1, 'abc');
    final span = buildCodeSpan(line, const TextStyle(), const [], selection: (start: 1, end: 4));
    final parts = [for (final c in span.children!) (c as TextSpan).text];
    expect(parts, ['a', 'bc', ' ']);
    expect((span.children![1] as TextSpan).style!.backgroundColor, isNotNull);
  });
}
