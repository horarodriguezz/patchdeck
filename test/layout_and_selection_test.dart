import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:patchdeck/diff/diff_layout.dart';
import 'package:patchdeck/diff/diff_models.dart';
import 'package:patchdeck/diff/diff_parser.dart';
import 'package:patchdeck/models/app_settings.dart';
import 'package:patchdeck/models/review.dart';
import 'package:patchdeck/state/patch_model.dart';
import 'package:patchdeck/state/comment_format.dart';
import 'package:patchdeck/state/review_export.dart';
import 'package:patchdeck/state/selection_controller.dart';
import 'package:patchdeck/ui/workspace/files_tab.dart';

void main() {
  final parsed = parsePatch(File('test/fixtures/sample.patch').readAsStringSync());
  final entry = PatchEntry(id: 'p1', name: 'A', raw: '', createdAt: DateTime(2024));
  final model = PatchModel(entry, parsed);
  final metrics = DiffMetrics(13);

  DiffLayout build(DiffMode mode, {Map<LineKey, List<String>> comments = const {}, Set<int> collapsed = const {}}) =>
      buildDiffLayout(
        patchId: 'p1',
        patch: parsed,
        mode: mode,
        metrics: metrics,
        collapsedFiles: collapsed,
        commentsByLine: comments,
      );

  test('offsets are monotonic and indexAt is consistent', () {
    final l = build(DiffMode.unified);
    for (var i = 0; i < l.rows.length; i++) {
      expect(l.indexAt(l.offsets[i] + 0.5), i);
    }
    expect(l.rows.first.kind, RowKind.preamble);
  });

  test('split pairs deletions with additions', () {
    final l = build(DiffMode.split);
    final paired = l.rows.where((r) => r.kind == RowKind.line && r.file == 0 && r.a >= 0 && r.b >= 0 && r.a != r.b);
    expect(paired.length, 2); // two dels paired with first two adds
    final rightOnly = l.rows.where((r) => r.kind == RowKind.line && r.file == 0 && r.a < 0);
    expect(rightOnly.length, 2);
  });

  test('collapsing hides lines', () {
    final full = build(DiffMode.unified);
    final c = build(DiffMode.unified, collapsed: {0, 1});
    expect(c.rows.length, lessThan(full.rows.length));
    expect(c.rows.where((r) => r.kind == RowKind.line && r.file <= 1), isEmpty);
  });

  test('comment rows are placed after the last anchored line, once per file', () {
    final comments = {
      ('p1', 0, 0, 1): ['c1'],
      ('p1', 0, 0, 3): ['c1'],
      ('p1', 1, 0, 2): ['c1'],
    };
    final l = build(DiffMode.unified, comments: comments);
    final idx = [
      for (var i = 0; i < l.rows.length; i++)
        if (l.rows[i].kind == RowKind.comment) i,
    ];
    expect(idx.length, 2);
    final before = l.rows[idx.first - 1];
    expect((before.file, before.a), (0, 3));
  });

  test('anchors round-trip through PatchModel', () {
    const k = ('p1', 1, 0, 2);
    final a = model.anchorFor(k);
    expect(a.path, 'styles/app.css');
    expect(a.newLine, 11);
    expect(a.oldLine, isNull);
    expect(model.keyFor(a), k);
  });

  test('selection: click, drag range, ctrl add/remove, cross-file', () {
    final l = build(DiffMode.unified);
    final sel = SelectionController();
    int rowOf(int file, int line) => l.rows.indexWhere((r) => r.kind == RowKind.line && r.file == file && r.a == line);

    sel.begin(l, DiffMode.unified, rowOf(0, 1), Side.left, ctrl: false, shift: false);
    sel.dragTo(rowOf(0, 4));
    sel.end();
    expect(sel.selected.length, 4);

    // Dragging past the file boundary stays within the start file.
    sel.begin(l, DiffMode.unified, rowOf(0, 6), Side.left, ctrl: false, shift: false);
    sel.dragTo(rowOf(1, 2));
    sel.end();
    expect(sel.selected.every((k) => k.$2 == 0), isTrue);

    // Ctrl-click adds a line in another file.
    sel.begin(l, DiffMode.unified, rowOf(0, 0), Side.left, ctrl: false, shift: false);
    sel.end();
    sel.begin(l, DiffMode.unified, rowOf(1, 1), Side.left, ctrl: true, shift: false);
    sel.end();
    expect(sel.selected, {('p1', 0, 0, 0), ('p1', 1, 0, 1)});

    // Ctrl-click on a selected line removes it.
    sel.begin(l, DiffMode.unified, rowOf(1, 1), Side.left, ctrl: true, shift: false);
    sel.end();
    expect(sel.selected, {('p1', 0, 0, 0)});
  });

  test('patch naming sequence', () {
    expect(nextPatchName([]), 'A');
    expect(nextPatchName(['A', 'B']), 'C');
    expect(nextPatchName([for (var i = 0; i < 26; i++) String.fromCharCode(65 + i)]), 'AA');
    expect(nextPatchName(['A', 'C']), 'B');
  });

  test('comment copy format: tags + files + lines: text', () {
    final c = ReviewComment(
      id: 'c',
      anchors: [
        for (final n in [3, 4, 5, 9]) LineAnchor(patchId: 'p1', path: 'src/a.ts', newLine: n),
        const LineAnchor(patchId: 'p1', path: 'src/a.ts', oldLine: 2),
        const LineAnchor(patchId: 'p1', path: 'b.css', newLine: 7),
        const LineAnchor(patchId: 'p2', path: 'c.ts', newLine: 1),
      ],
      labelIds: ['bug', 'nit', 'missing'],
      text: ' Arreglar esto ',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );
    final labels = {for (final l in AppSettings.defaults().labels) l.id: l};
    final names = {'p1': 'A', 'p2': 'B'};
    String fmt(ReviewComment x, String t, [String? pid]) =>
        formatComment(x, labelById: (id) => labels[id], patchNames: names, patchId: pid, template: t);

    // Default: {{fileName + lines}}:  {{commentText}}
    expect(fmt(c, defaultCopyTemplate, 'p1'), 'a.ts L3-L5, L9, L2 (eliminada) · b.css L7:  Arreglar esto');
    const custom = '[{{commentTags}}] {{filePath + lines}}: {{commentText}}';
    expect(fmt(c, custom, 'p1'), '[bug, nit] src/a.ts L3-L5, L9, L2 (eliminada) · b.css L7: Arreglar esto');
    expect(fmt(c, custom), '[bug, nit] A: src/a.ts L3-L5, L9, L2 (eliminada) · b.css L7 | B: c.ts L1: Arreglar esto');
    // Spaces inside braces don't matter; unknown variables stay verbatim; fixed text is kept.
    expect(
      fmt(c, '{{ fileName+lines }} -> {{nope}} ({{patchName}}) {{lines}} {{fileName}} {{filePath}}', 'p2'),
      'c.ts L1 -> {{nope}} (B) L1 c.ts c.ts',
    );
    final dismissed = c.copyWith(dismissed: true);
    final other = c.copyWith(text: 'otro', labelIds: []);
    expect(
      formatComments([c, dismissed, other], labelById: (id) => labels[id], patchNames: names, patchId: 'p2'),
      'c.ts L1:  Arreglar esto\n\nc.ts L1:  otro',
    );
    final review = Review(
      id: 'r',
      title: 'R',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
      patches: [PatchEntry(id: 'p2', name: 'B', raw: '', createdAt: DateTime(2024))],
      comments: [c, dismissed],
    );
    expect(commentsForPatch(review, 'p2').length, 1);
    expect(exportAllCommentsText(review, (id) => labels[id]), 'Patch B\n\nc.ts L1:  Arreglar esto');
    expect(AppSettings.fromJson(AppSettings.defaults().copyWith(copyTemplate: custom).toJson()).copyTemplate, custom);
    expect(AppSettings.fromJson({}).copyTemplate, defaultCopyTemplate);
    expect(
      AppSettings.fromJson(AppSettings.defaults().copyWith(codeFontFamily: 'JetBrains Mono').toJson()).codeFontFamily,
      'JetBrains Mono',
    );
    expect(ReviewComment.fromJson(dismissed.toJson()).dismissed, isTrue);
  });

  test('whole-file keys: anchors, layout placement, ordering and copy format', () {
    final fk = fileKey('p1', 1);
    expect(fk.isFile, isTrue);
    expect(('p1', 1, 0, 0).isFile, isFalse);
    final a = model.anchorFor(fk);
    expect(a.isWholeFile, isTrue);
    expect(a.path, 'styles/app.css');
    expect(model.keyFor(a), fk);
    expect(model.keyFor(LineAnchor.fromJson(a.toJson())), fk);

    // Alone it sits right under the file header; with a line of the same
    // file it goes after that line, once.
    var l = build(
      DiffMode.unified,
      comments: {
        fk: ['c1'],
      },
    );
    var i = l.rows.indexWhere((r) => r.kind == RowKind.comment);
    expect(l.rows[i - 1].kind, RowKind.fileHeader);
    expect(l.rows[i - 1].file, 1);
    l = build(
      DiffMode.split,
      comments: {
        fk: ['c1'],
        ('p1', 1, 0, 1): ['c1'],
      },
    );
    expect(l.rows.where((r) => r.kind == RowKind.comment).length, 1);
    i = l.rows.indexWhere((r) => r.kind == RowKind.comment);
    expect(l.rows[i - 1].kind, RowKind.line);
    // Collapsed files hide it like any other comment.
    l = build(
      DiffMode.unified,
      comments: {
        fk: ['c1'],
      },
      collapsed: {1},
    );
    expect(l.rows.where((r) => r.kind == RowKind.comment), isEmpty);

    final c = ReviewComment(
      id: 'c',
      anchors: [a, model.anchorFor(('p1', 0, 0, 3))],
      labelIds: const [],
      text: 'x',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );
    expect(
      describeLocations(c.anchors, patchNames: const {'p1': 'A'}),
      'styles/app.css (archivo completo) · src/greet.ts L2',
    );
    expect(lineRanges([a, model.anchorFor(('p1', 1, 0, 3))]), '(archivo completo), L12');
  });

  test('selection: whole-file button toggles like ctrl+click', () {
    final l = build(DiffMode.unified);
    final s = SelectionController();
    final fk = fileKey('p1', 0);
    s.toggleFile(fk, ctrl: false);
    expect(s.selected, {fk});
    final firstLine = l.rows.indexWhere((r) => r.kind == RowKind.line && r.file == 1);
    s.begin(l, DiffMode.unified, firstLine, Side.left, ctrl: true, shift: false);
    s.end();
    expect(s.selected.length, 2);
    expect(s.selected.contains(fk), isTrue);
    s.toggleFile(fk, ctrl: true);
    expect(s.selected.contains(fk), isFalse);
    expect(s.selected.length, 1);
    s.toggleFile(fk, ctrl: true);
    expect(s.selected.length, 2);
    // Without ctrl it replaces the selection.
    s.toggleFile(fileKey('p1', 1), ctrl: false);
    expect(s.selected, {fileKey('p1', 1)});
  });

  test('file tree groups folders, compacts single-child chains and sorts folders first', () {
    DiffFile f(String p) => DiffFile(
      oldPath: p,
      newPath: p,
      status: FileStatus.modified,
      isBinary: false,
      hunks: const [],
      additions: 0,
      deletions: 0,
    );
    final tree = buildFileTree([f('README.md'), f('lib/ui/diff/a.dart'), f('lib/ui/diff/b.dart'), f('lib/main.dart')]);
    expect([for (final n in tree) n.name], ['lib', 'README.md']);
    final lib = tree.first;
    expect([for (final n in lib.children) n.name], ['ui/diff', 'main.dart']);
    expect([for (final n in lib.children.first.children) n.file], [1, 2]);
  });
}
