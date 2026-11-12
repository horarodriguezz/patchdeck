import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:patchdeck/models/review.dart';
import 'package:patchdeck/services/app_paths.dart';
import 'package:patchdeck/services/json_store.dart';
import 'package:patchdeck/services/review_repository.dart';

void main() {
  test('atomic write replaces an existing file (also on Windows)', () async {
    final dir = await Directory.systemTemp.createTemp('patchdeck_store');
    final f = File('${dir.path}/a.json');
    await JsonStore.write(f, {'v': 1});
    await JsonStore.write(f, {'v': 2});
    expect(await JsonStore.read(f), {'v': 2});
    expect(File('${f.path}.tmp').existsSync(), isFalse);
  });

  test('review repository round trip and index', () async {
    final dir = await Directory.systemTemp.createTemp('patchdeck_repo');
    final repo = ReviewRepository(AppPaths(configDir: dir, dataDir: dir));
    final r = Review(id: 'r1', title: 'Uno', createdAt: DateTime(2024), updatedAt: DateTime(2024));
    await repo.save(r);
    r.title = 'Dos';
    await repo.save(r);
    expect((await repo.list()).single.title, 'Dos');
    expect((await ReviewRepository(AppPaths(configDir: dir, dataDir: dir)).load('r1'))!.title, 'Dos');
    await repo.delete('r1');
    expect(await repo.list(), isEmpty);
  });
}
