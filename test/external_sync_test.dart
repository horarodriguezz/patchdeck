import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:patchdeck/models/app_settings.dart';
import 'package:patchdeck/models/label.dart';
import 'package:patchdeck/models/review.dart';
import 'package:patchdeck/services/app_paths.dart';
import 'package:patchdeck/services/review_repository.dart';
import 'package:patchdeck/services/settings_repository.dart';
import 'package:patchdeck/state/reviews_controller.dart';
import 'package:patchdeck/state/settings_controller.dart';
import 'package:patchdeck/state/sync_merge.dart';
import 'package:patchdeck/state/workspace_controller.dart';

/// Changes written by other processes (the MCP server in `mcp/`) while the
/// app is running: watcher, index and three-way merges.

final _raw = File('test/fixtures/sample.patch').readAsStringSync();

ReviewComment _comment(String id, String text, {DateTime? at, List<String> labels = const []}) => ReviewComment(
  id: id,
  anchors: [const LineAnchor(patchId: 'p1', path: 'src/greet.ts', newLine: 2)],
  labelIds: labels,
  text: text,
  createdAt: DateTime(2024),
  updatedAt: at ?? DateTime(2024),
);

Review _review({List<ReviewComment>? comments, String notes = ''}) => Review(
  id: 'r1',
  title: 'Review',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
  notesMarkdown: notes,
  patches: [PatchEntry(id: 'p1', name: 'A', raw: _raw, createdAt: DateTime(2024))],
  comments: comments ?? [],
);

/// What another process sees: a fresh copy read from JSON.
Review _copy(Review r) => Review.fromJson(r.toJson());

Future<T> _next<T>(Stream<T> s) => s.first.timeout(const Duration(seconds: 5));

Future<AppPaths> _tempPaths() async {
  final dir = await Directory.systemTemp.createTemp('patchdeck_sync');
  addTearDown(() => dir.delete(recursive: true));
  return AppPaths(configDir: Directory('${dir.path}/config'), dataDir: Directory('${dir.path}/data'));
}

void main() {
  group('mergeReviewInto', () {
    test('remote additions arrive, unsaved local edits stay', () {
      final base = _review(comments: [_comment('c1', 'uno')], notes: 'base');
      final local = _copy(base);
      final snapshot = ReviewSnapshot.of(local);
      // Local: edits notes and adds c2. Remote: adds c3, marks a file as viewed.
      local
        ..notesMarkdown = 'local'
        ..comments.add(_comment('c2', 'local'));
      final remote = _copy(base)
        ..comments.add(_comment('c3', 'remoto'))
        ..viewedFiles.add('p1|gone.js')
        ..contextMarkdown = 'contexto remoto';

      mergeReviewInto(local, snapshot, remote);
      expect(local.comments.map((c) => c.id), ['c1', 'c3', 'c2']);
      expect(local.notesMarkdown, 'local');
      expect(local.contextMarkdown, 'contexto remoto');
      expect(local.viewedFiles, {'p1|gone.js'});
    });

    test('deletions on either side win over an untouched copy', () {
      final base = _review(comments: [_comment('c1', 'a'), _comment('c2', 'b')]);
      final local = _copy(base);
      final snapshot = ReviewSnapshot.of(local);
      local.comments.removeWhere((c) => c.id == 'c1');
      final remote = _copy(base)..comments.removeWhere((c) => c.id == 'c2');
      mergeReviewInto(local, snapshot, remote);
      expect(local.comments, isEmpty);
    });

    test('both edited the same comment: the newest wins', () {
      final base = _review(comments: [_comment('c1', 'a')]);
      final local = _copy(base);
      final snapshot = ReviewSnapshot.of(local);
      local.comments[0] = _comment('c1', 'local', at: DateTime(2025, 1, 1));
      final remote = _copy(base);
      remote.comments[0] = _comment('c1', 'remoto', at: DateTime(2025, 1, 2), labels: ['bug']);
      mergeReviewInto(local, snapshot, remote);
      expect(local.comments.single.text, 'remoto');
      expect(local.comments.single.labelIds, ['bug']);
    });
  });

  group('mergeSettings', () {
    ReviewLabel l(String id, String title) => ReviewLabel(id: id, title: title, color: 0xFF000000);
    final base = AppSettings.defaults().copyWith(labels: [l('a', 'A'), l('b', 'B')]);

    test('remote label changes merge with a local theme change', () {
      final local = base.copyWith(themeId: 'forest');
      final remote = base.copyWith(labels: [l('b', 'B2'), l('a', 'A'), l('c', 'C')]);
      final m = mergeSettings(base: base, local: local, remote: remote);
      expect(m.themeId, 'forest');
      expect(m.labels.map((x) => '${x.id}:${x.title}'), ['b:B2', 'a:A', 'c:C']);
    });

    test('local reorder and delete are kept, remote additions go last', () {
      final local = base.copyWith(labels: [l('b', 'B')]);
      final remote = base.copyWith(labels: [l('a', 'A'), l('b', 'B'), l('c', 'C')], themeId: 'sand');
      final m = mergeSettings(base: base, local: local, remote: remote);
      expect(m.labels.map((x) => x.id), ['b', 'c']);
      expect(m.themeId, 'sand');
    });
  });

  group('watching the data directory', () {
    test('external writes are reported and indexed; own writes are not', () async {
      final paths = await _tempPaths();
      final app = ReviewRepository(paths);
      addTearDown(app.dispose);
      await app.watch();

      final events = <ReviewChange>[];
      final sub = app.changes.listen(events.add);
      addTearDown(sub.cancel);

      await app.save(_review());
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(events, isEmpty, reason: 'our own save is not an external change');

      // Another process (its own repository instance) adds a comment.
      final other = ReviewRepository(paths);
      final r = (await other.load('r1'))!..comments.add(_comment('c9', 'desde MCP'));
      final changed = _next(app.changes);
      await other.save(r);
      final c = await changed;
      expect(c.id, 'r1');
      expect(c.review!.comments.single.text, 'desde MCP');
      expect((await app.list()).single.commentCount, 1);

      // A brand-new review shows up in the index.
      final created = _next(app.changes);
      await other.save(Review(id: 'r2', title: 'Nueva', createdAt: DateTime(2025), updatedAt: DateTime(2025)));
      expect((await created).id, 'r2');
      expect((await app.list()).map((s) => s.id), containsAll(['r1', 'r2']));
    });

    test('an open workspace picks up external comments and keeps local edits', () async {
      final paths = await _tempPaths();
      final repo = ReviewRepository(paths);
      addTearDown(repo.dispose);
      await repo.save(_review(comments: [_comment('c1', 'uno')]));
      await repo.watch();

      final ws = WorkspaceController(repo: repo, review: (await repo.load('r1'))!, highlight: false);
      addTearDown(ws.dispose);
      for (var i = 0; i < 200 && ws.model('p1') == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      ws.setNotes('notas locales sin guardar');

      final external = ReviewRepository(paths);
      final r = (await external.load('r1'))!
        ..comments.add(_comment('c2', 'de Claude', labels: ['bug']))
        ..viewedFiles.add('p1|gone.js');
      final notified = Completer<void>();
      void listener() {
        if (ws.comments.length == 2 && !notified.isCompleted) notified.complete();
      }

      ws.addListener(listener);
      await external.save(r);
      await notified.future.timeout(const Duration(seconds: 5));
      ws.removeListener(listener);

      expect(ws.comments.map((c) => c.text), ['uno', 'de Claude']);
      expect(ws.review.notesMarkdown, 'notas locales sin guardar');
      final gone = ws.model('p1')!.parsed.files.indexWhere((f) => f.path == 'gone.js');
      expect(ws.collapsedFiles('p1'), contains(gone), reason: 'viewed elsewhere → collapsed here');

      await ws.flush();
      final onDisk = (await ReviewRepository(paths).load('r1'))!;
      expect(onDisk.comments.map((c) => c.id), ['c1', 'c2']);
      expect(onDisk.notesMarkdown, 'notas locales sin guardar');
    });

    test('saving merges a change the watcher has not reported yet', () async {
      final paths = await _tempPaths();
      final repo = ReviewRepository(paths); // not watching
      await repo.save(_review());
      final ws = WorkspaceController(repo: repo, review: (await repo.load('r1'))!, highlight: false);
      addTearDown(ws.dispose);

      final external = ReviewRepository(paths);
      await Future<void>.delayed(const Duration(milliseconds: 20)); // distinct mtime
      await external.save((await external.load('r1'))!..comments.add(_comment('c2', 'externo')));

      ws.rename('Título local');
      await ws.flush();
      final onDisk = (await ReviewRepository(paths).load('r1'))!;
      expect(onDisk.title, 'Título local');
      expect(onDisk.comments.single.text, 'externo');
    });

    test('renaming from the sidebar reaches the open workspace', () async {
      final paths = await _tempPaths();
      final repo = ReviewRepository(paths);
      addTearDown(repo.dispose);
      await repo.save(_review());
      final reviews = ReviewsController(repo);
      addTearDown(reviews.dispose);
      final ws = WorkspaceController(repo: repo, review: (await repo.load('r1'))!, highlight: false);
      addTearDown(ws.dispose);

      await reviews.rename('r1', 'Desde la barra');
      await Future<void>.delayed(Duration.zero);
      expect(ws.review.title, 'Desde la barra');
      ws.setNotes('x'); // a later save must not bring the old title back
      await ws.flush();
      expect((await ReviewRepository(paths).load('r1'))!.title, 'Desde la barra');
    });

    test('labels created in settings.json by another process appear in the app', () async {
      final paths = await _tempPaths();
      final repo = SettingsRepository(paths);
      addTearDown(repo.dispose);
      final settings = SettingsController(repo, await repo.load());
      addTearDown(settings.dispose);
      await repo.watch();

      final external = SettingsRepository(paths);
      final s = await external.load();
      final changed = _next(repo.changes);
      await external.save(
        s.copyWith(
          labels: [
            ...s.labels,
            ReviewLabel(id: 'mcp', title: 'refactor', color: 0xFF2EA39C),
          ],
        ),
      );
      await changed;
      expect(settings.labelById('mcp')?.title, 'refactor');

      // A later local edit keeps it.
      settings.setTheme('forest');
      await settings.flush();
      final onDisk = await SettingsRepository(paths).load();
      expect(onDisk.themeId, 'forest');
      expect(onDisk.labels.map((l) => l.id), contains('mcp'));
    });
  });
}
