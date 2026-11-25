import assert from 'node:assert/strict';
import { promises as fs, readFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { filePath, parsePatch } from '../src/diff.js';
import { lineRanges } from '../src/format.js';
import { nextPatchName, Patchdeck } from '../src/ops.js';
import { makePaths, pathsFromEnv } from '../src/paths.js';
import { Store, UserError } from '../src/store.js';

const here = path.dirname(fileURLToPath(import.meta.url));
// dist/test/ → repo root
const sample = readFileSync(path.join(here, '..', '..', '..', 'test', 'fixtures', 'sample.patch'), 'utf8');

async function setup() {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'patchdeck-mcp-'));
  const paths = makePaths(path.join(dir, 'config'), path.join(dir, 'data'));
  return { dir, paths, pd: new Patchdeck(new Store(paths)) };
}

test('parser matches the Dart parser on the fixture', () => {
  const p = parsePatch(sample);
  assert.deepEqual(p.files.map(filePath), ['src/greet.ts', 'styles/app.css', 'new.txt', 'logo.png', 'gone.js']);
  assert.equal(p.files[2]!.status, 'renamed');
  assert.equal(p.files[2]!.oldPath, 'old.txt');
  assert.equal(p.files[3]!.isBinary, true);
  assert.equal(p.files[4]!.status, 'deleted');
  assert.equal(p.files[0]!.additions, 4);
  assert.equal(p.files[0]!.deletions, 2);
  assert.match(p.preamble, /Subject: \[PATCH\] Improve greeting/);
  assert.doesNotMatch(p.preamble, /2\.43\.0/);
  const css = p.files[1]!.hunks[0]!;
  assert.equal(css.section, 'body {');
  assert.deepEqual(css.lines[0], { kind: 'context', old: 10, new: 10, text: '  margin: 0;' });
  const gone = p.files[4]!.hunks[0]!.lines;
  assert.deepEqual(
    gone.filter((l) => l.kind === 'del').map((l) => l.text),
    ['const a = 1;', '-- not a header'],
  );
  assert.equal(gone[gone.length - 1]!.kind, 'noNewline');
});

test('plain diff -u and CRLF', () => {
  const plain = parsePatch('--- a.txt\t2024-01-01\n+++ b.txt\t2024-01-02\n@@ -1 +1 @@\n-x\n+y\n');
  assert.equal(plain.files[0]!.oldPath, 'a.txt');
  assert.equal(plain.files[0]!.newPath, 'b.txt');
  const crlf = parsePatch('diff --git a/x b/x\r\n--- a/x\r\n+++ b/x\r\n@@ -1 +1 @@\r\n-a\r\n+b\r\n');
  assert.equal(crlf.files[0]!.hunks[0]!.lines.length, 2);
});

test('paths follow XDG and Windows conventions', () => {
  const linux = pathsFromEnv({ HOME: '/home/u', XDG_DATA_HOME: '/data' }, 'linux');
  assert.equal(linux.settingsFile, '/home/u/.config/patchdeck/settings.json');
  assert.equal(linux.reviewFile('abc'), '/data/patchdeck/reviews/abc.json');
  const over = pathsFromEnv({ HOME: '/h', PATCHDECK_DATA_DIR: '/x' }, 'linux');
  assert.equal(over.reviewsIndex, path.join('/x', 'reviews', 'index.json'));
});

test('patch names and line ranges match the app', () => {
  assert.equal(nextPatchName([]), 'A');
  assert.equal(nextPatchName(['A', 'B']), 'C');
  assert.equal(nextPatchName([...'ABCDEFGHIJKLMNOPQRSTUVWXYZ']), 'AA');
  assert.equal(
    lineRanges([{ patch: 'p', path: 'f', new: 2 }, { patch: 'p', path: 'f', new: 3 }, { patch: 'p', path: 'f', old: 7 }]),
    'L2-L3, L7 (eliminada)',
  );
});

test('review lifecycle writes files the app can read', async () => {
  const { paths, pd } = await setup();
  const { id } = await pd.createReview({ title: 'PR 42', context: 'Descripción' });
  const added = await pd.addPatch({ review: 'PR 42', diff: sample });
  assert.equal(added.name, 'A');
  assert.equal(added.files.length, 5);

  // Range on the new side includes the interleaved deleted lines (like dragging in the UI).
  const c = await pd.addComment({
    review: id,
    text: 'Falta validar name',
    labels: ['bug', 'Pregunta'],
    locations: [{ path: 'src/greet.ts', line: 1, end_line: 3 }],
  });
  assert.deepEqual(
    c.anchors.map((a) => [a.old, a.new]),
    [
      [1, 1],
      [2, undefined],
      [3, undefined],
      [undefined, 2],
      [undefined, 3],
    ],
  );
  assert.equal(c.location, 'src/greet.ts L1-L3, L2-L3 (eliminadas)');
  assert.deepEqual(c.labels.map((l) => l.id), ['bug', 'question']);

  // Whole file + a deleted line + another file, in one comment.
  const multi = await pd.addComment({
    review: id,
    text: 'Varios',
    locations: [
      { path: 'gone.js' },
      { path: 'styles/app.css', line: 11, side: 'old' },
      { path: 'b/styles/app.css', line: 10 },
    ],
  });
  assert.deepEqual(multi.anchors, [
    { patch: 'A', path: 'gone.js' },
    { patch: 'A', path: 'styles/app.css', old: 11 },
    { patch: 'A', path: 'styles/app.css', old: 10, new: 10 },
  ]);

  // On-disk format: compact review, pretty index, Dart-style timestamps.
  const raw = await fs.readFile(paths.reviewFile(id), 'utf8');
  assert.ok(!raw.includes('\n  '), 'review files are written compact, like the app');
  const json = JSON.parse(raw);
  assert.equal(json.version, 1);
  assert.equal(json.context, 'Descripción');
  assert.equal(json.comments[0].labels[0], 'bug');
  assert.equal(json.comments[0].dismissed, undefined);
  assert.match(json.updatedAt, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}$/);
  const index = JSON.parse(await fs.readFile(paths.reviewsIndex, 'utf8'));
  assert.deepEqual(index[0].patches, ['A']);
  assert.equal(index[0].comments, 2);

  // Edit, dismiss, view, export.
  await pd.updateComment({ review: id, comment_id: c.id, remove_labels: ['question'], add_labels: ['nit'], dismissed: true });
  const listed = await pd.listComments({ review: id, label: 'nit' });
  assert.equal(listed.length, 1);
  assert.equal(listed[0]!.dismissed, true);
  assert.equal((await pd.listComments({ review: id, include_dismissed: false })).length, 1);

  await pd.setFileViewed({ review: id, path: 'gone.js', viewed: true });
  const r = await pd.getReview(id);
  assert.equal(r.patches[0]!.files.find((f) => f.path === 'gone.js')!.viewed, true);

  const md = await pd.exportReview({ review: id });
  assert.match(md, /^# PR 42\n\n## Contexto\n\nDescripción\n\n## Patch A\n\n- \*\*gone\.js \(archivo completo\)/);
  assert.doesNotMatch(md, /Falta validar/); // dismissed comments are not exported
  const text = await pd.exportReview({ review: id, format: 'comments' });
  assert.equal(text, 'Patch A\n\ngone.js (archivo completo) · app.css L10, L11 (eliminada):  Varios');

  await pd.updateReview({ review: id, notes: 'uno' });
  const notes = await pd.updateReview({ review: id, notes: 'dos', append: true });
  assert.equal(notes.notes, 'uno\n\ndos');

  await pd.deleteComment({ review: id, comment_id: multi.id });
  assert.equal((await pd.getReview(id)).comments.length, 1);
});

test('annotated patch shows explicit line numbers and comment marks', async () => {
  const { pd } = await setup();
  const { id } = await pd.createReview({ title: 'x' });
  await pd.addPatch({ review: id, diff: sample });
  await pd.addComment({ review: id, text: 't', locations: [{ path: 'styles/app.css', line: 12 }] });
  const out = await pd.getPatch({ review: id, file: 'app.css' });
  assert.match(out, /=== styles\/app\.css \(modified, \+2 -1\)/);
  assert.match(out, /\n {4}10 {5}10 \|    margin: 0;\n/);
  assert.match(out, /\n {4}11 {8}\| -  color: #333;\n/);
  assert.match(out, / {6}12 \| \+  padding: 4px !important;  ◀ comentado/);
});

test('invalid locations explain what is valid', async () => {
  const { pd } = await setup();
  const { id } = await pd.createReview({ title: 'x' });
  await pd.addPatch({ review: id, diff: sample });
  await assert.rejects(
    pd.addComment({ review: id, text: 't', locations: [{ path: 'styles/app.css', line: 99 }] }),
    (e: Error) => e instanceof UserError && /nuevas 10-13 \/ viejas 10-12/.test(e.message),
  );
  await assert.rejects(pd.addComment({ review: id, text: 't', locations: [{ path: 'nope.ts' }] }), /no tiene el archivo/);
  await assert.rejects(pd.addComment({ review: id, text: 't', labels: ['inventada'], locations: [{ path: 'gone.js' }] }), /create_label/);
  await assert.rejects(pd.addPatch({ review: id, diff: 'hola' }), /no parece un diff/);
  await assert.rejects(pd.getReview('../etc/passwd'), /No encuentro/);
});

test('labels: create, update, reorder, delete — keeping the rest of settings.json', async () => {
  const { paths, pd } = await setup();
  await fs.mkdir(paths.configDir, { recursive: true });
  await fs.writeFile(
    paths.settingsFile,
    JSON.stringify({ version: 1, appearance: { theme: 'forest' }, labels: [{ id: 'bug', title: 'bug', description: '', color: '#FFE5534B' }] }),
  );

  const l = await pd.createLabel({ title: 'Refactor', description: 'Mejor estructura' });
  assert.match(l.id, /^[0-9a-f]{24}$/);
  assert.equal(l.color, '#ffe0823d'); // first palette color not in use
  await assert.rejects(pd.createLabel({ title: 'refactor' }), /Ya existe/);
  await assert.rejects(pd.createLabel({ title: 'x', color: 'rojo' }), /Color inválido/);

  const u = await pd.updateLabel({ label: 'refactor', title: 'refactor', color: '#123456' });
  assert.equal(u.color, '#ff123456');

  assert.deepEqual(
    (await pd.reorderLabels(['refactor'])).map((x) => x.title),
    ['refactor', 'bug'],
  );

  const { id } = await pd.createReview({ title: 'r' });
  await pd.addPatch({ review: id, diff: sample });
  await pd.addComment({ review: id, text: 't', labels: ['refactor', 'bug'], locations: [{ path: 'gone.js' }] });
  assert.equal((await pd.listLabels(true)).find((x) => x.title === 'refactor')!.comments, 1);

  const del = await pd.deleteLabel({ label: 'refactor', remove_from_comments: true });
  assert.equal(del.comments_referencing, 1);
  assert.equal(del.removed_from_comments, 1);
  assert.deepEqual((await pd.getReview(id)).comments[0]!.labels.map((x) => x.id), ['bug']);

  const settings = JSON.parse(await fs.readFile(paths.settingsFile, 'utf8'));
  assert.deepEqual(settings.appearance, { theme: 'forest' });
  assert.deepEqual(settings.labels.map((x: { id: string }) => x.id), ['bug']);
  assert.equal(settings.labels[0].color, '#ffe5534b');
});

test('without settings.json the app defaults are used', async () => {
  const { pd } = await setup();
  assert.deepEqual(
    (await pd.listLabels()).map((l) => l.id),
    ['bug', 'nit', 'question', 'perf', 'security', 'praise'],
  );
});

test('unknown fields written by the app survive a round trip', async () => {
  const { paths, pd } = await setup();
  const { id } = await pd.createReview({ title: 'x' });
  const file = paths.reviewFile(id);
  const j = JSON.parse(await fs.readFile(file, 'utf8'));
  j.futureField = { a: 1 };
  await fs.writeFile(file, JSON.stringify(j));
  await pd.updateReview({ review: id, title: 'y' });
  assert.deepEqual(JSON.parse(await fs.readFile(file, 'utf8')).futureField, { a: 1 });
});
