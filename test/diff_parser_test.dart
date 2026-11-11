import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:patchdeck/diff/diff_models.dart';
import 'package:patchdeck/diff/diff_parser.dart';

void main() {
  final raw = File('test/fixtures/sample.patch').readAsStringSync();

  test('parses files, statuses and stats', () {
    final p = parsePatch(raw);
    expect(p.files.map((f) => f.path), ['src/greet.ts', 'styles/app.css', 'new.txt', 'logo.png', 'gone.js']);
    expect(p.files[0].status, FileStatus.modified);
    expect(p.files[2].status, FileStatus.renamed);
    expect(p.files[2].oldPath, 'old.txt');
    expect(p.files[3].status, FileStatus.added);
    expect(p.files[3].isBinary, isTrue);
    expect(p.files[4].status, FileStatus.deleted);
    expect(p.files[0].additions, 4);
    expect(p.files[0].deletions, 2);
    expect(p.preamble, contains('Subject: [PATCH] Improve greeting'));
    expect(p.preamble, isNot(contains('2.43.0')));
  });

  test('line numbers follow hunk headers', () {
    final h = parsePatch(raw).files[1].hunks.single;
    expect(h.oldStart, 10);
    expect(h.section, 'body {');
    final ctx = h.lines.first;
    expect((ctx.kind, ctx.oldNo, ctx.newNo), (LineKind.context, 10, 10));
    final add = h.lines.firstWhere((l) => l.kind == LineKind.add);
    expect((add.oldNo, add.newNo), (null, 11));
  });

  test('removed line starting with "--" is content, not a header', () {
    final lines = parsePatch(raw).files[4].hunks.single.lines;
    expect(lines.where((l) => l.kind == LineKind.del).map((l) => l.text), ['const a = 1;', '-- not a header']);
    expect(lines.last.kind, LineKind.noNewline);
  });

  test('plain diff -u without git header', () {
    const plain = '--- a.txt\t2024-01-01\n+++ b.txt\t2024-01-02\n@@ -1 +1 @@\n-x\n+y\n';
    final p = parsePatch(plain);
    expect(p.files.single.oldPath, 'a.txt');
    expect(p.files.single.newPath, 'b.txt');
    expect(p.files.single.hunks.single.lines.length, 2);
  });

  test('CRLF input and tabs', () {
    const crlf = 'diff --git a/x b/x\r\n--- a/x\r\n+++ b/x\r\n@@ -1 +1 @@\r\n-\ta\r\n+\tb\r\n';
    final l = parsePatch(crlf).files.single.hunks.single.lines;
    expect(l.map((e) => e.text), ['    a', '    b']);
  });

  test('highlighting is attached only for known languages', () {
    final p = parsePatch(raw);
    expect(p.files[0].hunks.first.lines[1].spans, isNotNull);
    expect(parsePatch(raw, highlight: false).files[0].hunks.first.lines[1].spans, isNull);
  });

  test('large patch parses fast', () {
    final b = StringBuffer();
    for (var f = 0; f < 200; f++) {
      b.writeln('diff --git a/f$f.ts b/f$f.ts\n--- a/f$f.ts\n+++ b/f$f.ts\n@@ -1,500 +1,500 @@');
      for (var i = 0; i < 500; i++) {
        b.writeln(i.isEven ? '-const v$i = "old"; // x' : '+const v$i = `new`; /* y */');
      }
    }
    final sw = Stopwatch()..start();
    final p = parsePatch(b.toString());
    sw.stop();
    expect(p.files.length, 200);
    expect(sw.elapsedMilliseconds, lessThan(3000));
  });
}
