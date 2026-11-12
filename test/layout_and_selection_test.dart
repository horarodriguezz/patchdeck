import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:patchdeck/diff/diff_layout.dart';
import 'package:patchdeck/diff/diff_parser.dart';
import 'package:patchdeck/models/app_settings.dart';
import 'package:patchdeck/models/review.dart';
import 'package:patchdeck/state/patch_model.dart';
import 'package:patchdeck/state/comment_format.dart';
import 'package:patchdeck/state/review_export.dart';
import 'package:patchdeck/state/selection_controller.dart';

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
}
