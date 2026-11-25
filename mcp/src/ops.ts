/**
 * Everything the MCP tools do, as plain async methods (the tools in
 * `tools.ts` only validate input and serialize the result).
 */
import { promises as fs } from 'node:fs';

import { filePath, parsePatch, type DiffFile, type DiffLine, type ParsedPatch } from './diff.js';
import { describeLocations, exportAllCommentsText, exportReviewMarkdown, renderPatch } from './format.js';
import {
  defaultCopyTemplate,
  formatColor,
  newId,
  nowIso,
  parseColor,
  Store,
  UserError,
  type AnchorJson,
  type CommentJson,
  type LabelJson,
  type PatchJson,
  type ReviewJson,
} from './store.js';

/** Same palette as the label editor in the app. */
export const labelPalette = [
  0xffe5534b, 0xffe0823d, 0xffc69026, 0xff57ab5a, 0xff2ea39c, 0xff539bf5, 0xff6e7ff3, 0xffb083f0, 0xffe275ad,
  0xff8b949e, 0xff5c6370, 0xff1f883d,
];

export interface LocationInput {
  /** Patch name (`A`, `B`, …) or id; optional when the review has a single patch. */
  patch?: string;
  path: string;
  /** Omitted: the comment targets the whole file. */
  line?: number;
  end_line?: number;
  /** Which numbering `line` uses: the new file (default) or the old one (deleted lines). */
  side?: 'new' | 'old';
}

export interface CommentFilters {
  patch?: string;
  path?: string;
  label?: string;
  include_dismissed?: boolean;
}

/** A, B, …, Z, AA, AB, … — first free name, like `nextPatchName` in Dart. */
export function nextPatchName(existing: Iterable<string>): string {
  const taken = new Set(existing);
  for (let i = 0; ; i++) {
    let n = i + 1;
    let s = '';
    while (n > 0) {
      n--;
      s = String.fromCharCode(65 + (n % 26)) + s;
      n = Math.floor(n / 26);
    }
    if (!taken.has(s)) return s;
  }
}

const anchorKey = (a: AnchorJson) => `${a.patch}|${a.path}|${a.old ?? ''}|${a.new ?? ''}`;

export class Patchdeck {
  private cache = new Map<string, { raw: string; parsed: ParsedPatch }>();

  constructor(readonly store: Store) {}

  // ------------------------------------------------------------- lookup

  parse(p: PatchJson): ParsedPatch {
    const hit = this.cache.get(p.id);
    if (hit && hit.raw === p.raw) return hit.parsed;
    const parsed = parsePatch(p.raw);
    this.cache.set(p.id, { raw: p.raw, parsed });
    return parsed;
  }

  /** Accepts an id or a title (exact, else a unique partial match; case-insensitive). */
  async resolveReviewId(ref: string): Promise<string> {
    const list = await this.store.listReviews();
    if (list.some((s) => s.id === ref)) return ref;
    const q = ref.trim().toLowerCase();
    const exact = list.filter((s) => s.title.trim().toLowerCase() === q);
    const matches = exact.length ? exact : list.filter((s) => s.title.toLowerCase().includes(q));
    if (matches.length === 1) return matches[0]!.id;
    if (/^[A-Za-z0-9_-]{1,64}$/.test(ref)) {
      // Maybe the index is stale; try the file itself.
      try {
        return (await this.store.loadReview(ref)).id;
      } catch {
        /* fall through */
      }
    }
    const known = list.map((s) => `${s.id} ("${s.title}")`).join(', ') || 'ninguna';
    if (matches.length > 1) {
      throw new UserError(`"${ref}" coincide con varias reviews: ${matches.map((s) => `${s.id} ("${s.title}")`).join(', ')}`);
    }
    throw new UserError(`No encuentro la review "${ref}". Reviews: ${known}`);
  }

  findPatch(r: ReviewJson, ref: string | undefined): PatchJson {
    if (ref === undefined || ref === '') {
      if (r.patches.length === 1) return r.patches[0]!;
      throw new UserError(
        r.patches.length === 0
          ? 'La review no tiene patches.'
          : `Indica el patch: ${r.patches.map((p) => p.name).join(', ')}`,
      );
    }
    const p =
      r.patches.find((x) => x.id === ref) ?? r.patches.find((x) => x.name.toLowerCase() === ref.trim().toLowerCase());
    if (!p) throw new UserError(`No hay un patch "${ref}". Patches: ${r.patches.map((x) => x.name).join(', ') || 'ninguno'}`);
    return p;
  }

  findFile(parsed: ParsedPatch, path: string): DiffFile {
    const p = path.trim().replace(/^[ab]\//, '');
    const f =
      parsed.files.find((x) => filePath(x) === p) ??
      parsed.files.find((x) => x.newPath === p || x.oldPath === p) ??
      (() => {
        const bySuffix = parsed.files.filter((x) => filePath(x).endsWith('/' + p));
        return bySuffix.length === 1 ? bySuffix[0] : undefined;
      })();
    if (!f) throw new UserError(`El patch no tiene el archivo "${path}". Archivos: ${parsed.files.map(filePath).join(', ')}`);
    return f;
  }

  /** Turns human locations into the app's anchors, validating every line. */
  resolveLocations(r: ReviewJson, locations: LocationInput[]): AnchorJson[] {
    if (!locations.length) throw new UserError('Hace falta al menos una ubicación.');
    const out = new Map<string, AnchorJson>();
    for (const loc of locations) {
      const patch = this.findPatch(r, loc.patch);
      const file = this.findFile(this.parse(patch), loc.path);
      const path = filePath(file);
      if (loc.line === undefined) {
        if (loc.end_line !== undefined) throw new UserError('end_line requiere line.');
        const a = { patch: patch.id, path };
        out.set(anchorKey(a), a);
        continue;
      }
      const side = loc.side ?? 'new';
      const rows: DiffLine[] = file.hunks.flatMap((h) => h.lines.filter((l) => l.kind !== 'noNewline'));
      const num = (l: DiffLine) => (side === 'new' ? (l.kind === 'del' ? undefined : l.new) : l.kind === 'add' ? undefined : l.old);
      const end = loc.end_line ?? loc.line;
      const lo = Math.min(loc.line, end);
      const hi = Math.max(loc.line, end);
      const hits: number[] = [];
      rows.forEach((l, i) => {
        const n = num(l);
        if (n !== undefined && n >= lo && n <= hi) hits.push(i);
      });
      if (!hits.length) {
        throw new UserError(
          `${path}: la línea ${lo === hi ? lo : `${lo}-${hi}`} (${side === 'new' ? 'nueva' : 'vieja'}) no está en el patch ` +
            `${patch.name}. Rangos visibles: ${hunkRanges(file)}. Para comentar el archivo completo omite "line".`,
        );
      }
      // Like dragging in the UI: everything between the first and last hit,
      // including interleaved lines of the other side.
      const selected = loc.end_line === undefined ? [rows[hits[0]!]!] : rows.slice(hits[0]!, hits[hits.length - 1]! + 1);
      for (const l of selected) {
        const a: AnchorJson = { patch: patch.id, path };
        if (l.kind !== 'add' && l.old !== undefined) a.old = l.old;
        if (l.kind !== 'del' && l.new !== undefined) a.new = l.new;
        out.set(anchorKey(a), a);
      }
    }
    return [...out.values()];
  }

  /** Anchors that don't match any line of their patch (e.g. the patch was removed). */
  private unresolved(r: ReviewJson, c: CommentJson): number {
    let n = 0;
    for (const a of c.anchors) {
      const p = r.patches.find((x) => x.id === a.patch);
      if (!p) {
        n++;
        continue;
      }
      const f = this.parse(p).files.find((x) => filePath(x) === a.path);
      if (!f) {
        n++;
        continue;
      }
      if (a.old == null && a.new == null) continue;
      const ok = f.hunks.some((h) =>
        h.lines.some(
          (l) =>
            l.kind !== 'noNewline' &&
            (l.kind === 'add' ? undefined : l.old) === (a.old ?? undefined) &&
            (l.kind === 'del' ? undefined : l.new) === (a.new ?? undefined),
        ),
      );
      if (!ok) n++;
    }
    return n;
  }

  // ------------------------------------------------------------- labels

  async labels(): Promise<LabelJson[]> {
    return (await this.store.loadSettings()).labels;
  }

  static resolveLabel(all: LabelJson[], ref: string): LabelJson {
    const byId = all.find((l) => l.id === ref);
    if (byId) return byId;
    const q = ref.trim().toLowerCase();
    const byTitle = all.filter((l) => l.title.trim().toLowerCase() === q);
    if (byTitle.length === 1) return byTitle[0]!;
    if (byTitle.length > 1) throw new UserError(`Hay varias etiquetas "${ref}"; usa el id: ${byTitle.map((l) => l.id).join(', ')}`);
    throw new UserError(
      `No existe la etiqueta "${ref}". Etiquetas: ${all.map((l) => `${l.title} (${l.id})`).join(', ') || 'ninguna'}. ` +
        'Puedes crearla con create_label.',
    );
  }

  static resolveLabels(all: LabelJson[], refs: string[]): string[] {
    return [...new Set(refs.map((r) => Patchdeck.resolveLabel(all, r).id))];
  }

  private labelLookup(all: LabelJson[]) {
    const m = new Map(all.map((l) => [l.id, l]));
    return (id: string) => m.get(id);
  }

  private commentView(r: ReviewJson, c: CommentJson, all: LabelJson[]) {
    const names = new Map(r.patches.map((p) => [p.id, p.name]));
    const label = this.labelLookup(all);
    const unresolved = this.unresolved(r, c);
    return {
      id: c.id,
      text: c.text,
      labels: c.labels.map((id) => ({ id, title: label(id)?.title ?? null })),
      dismissed: c.dismissed === true,
      location: describeLocations(c.anchors, names),
      anchors: c.anchors.map((a) => ({ ...a, patch: names.get(a.patch) ?? a.patch })),
      ...(unresolved ? { unresolved_anchors: unresolved } : {}),
      createdAt: c.createdAt,
      updatedAt: c.updatedAt,
    };
  }

  async listLabels(includeUsage = false) {
    const all = await this.labels();
    let usage: Map<string, number> | undefined;
    if (includeUsage) {
      usage = new Map();
      for (const r of await this.store.allReviews()) {
        for (const c of r.comments) for (const id of c.labels) usage.set(id, (usage.get(id) ?? 0) + 1);
      }
    }
    return all.map((l) => ({
      id: l.id,
      title: l.title,
      description: l.description,
      color: l.color,
      ...(usage ? { comments: usage.get(l.id) ?? 0 } : {}),
    }));
  }

  private static checkTitle(all: LabelJson[], title: string, exceptId?: string): string {
    const t = title.trim();
    if (!t) throw new UserError('El título de la etiqueta no puede estar vacío.');
    const clash = all.find((l) => l.id !== exceptId && l.title.trim().toLowerCase() === t.toLowerCase());
    if (clash) throw new UserError(`Ya existe la etiqueta "${clash.title}" (${clash.id}).`);
    return t;
  }

  private static color(v: string): string {
    const c = parseColor(v);
    if (c === null) throw new UserError(`Color inválido "${v}"; usa #RRGGBB o #AARRGGBB.`);
    return formatColor(c);
  }

  async createLabel(input: { title: string; description?: string; color?: string }) {
    return this.store.mutateSettings((s) => {
      const title = Patchdeck.checkTitle(s.labels, input.title);
      const used = new Set(s.labels.map((l) => parseColor(l.color)));
      const color =
        input.color !== undefined
          ? Patchdeck.color(input.color)
          : formatColor(labelPalette.find((c) => !used.has(c)) ?? labelPalette[s.labels.length % labelPalette.length]!);
      const label: LabelJson = { id: newId(), title, description: input.description?.trim() ?? '', color };
      s.labels.push(label);
      return label;
    });
  }

  async updateLabel(input: { label: string; title?: string; description?: string; color?: string }) {
    return this.store.mutateSettings((s) => {
      const l = Patchdeck.resolveLabel(s.labels, input.label);
      if (input.title !== undefined) l.title = Patchdeck.checkTitle(s.labels, input.title, l.id);
      if (input.description !== undefined) l.description = input.description.trim();
      if (input.color !== undefined) l.color = Patchdeck.color(input.color);
      return l;
    });
  }

  async deleteLabel(input: { label: string; remove_from_comments?: boolean }) {
    const removed = await this.store.mutateSettings((s) => {
      const l = Patchdeck.resolveLabel(s.labels, input.label);
      s.labels = s.labels.filter((x) => x.id !== l.id);
      return l;
    });
    let referencing = 0;
    let stripped = 0;
    for (const r of await this.store.allReviews()) {
      const n = r.comments.filter((c) => c.labels.includes(removed.id)).length;
      referencing += n;
      if (n && input.remove_from_comments) {
        await this.store.mutateReview(r.id, (rr) => {
          for (const c of rr.comments) {
            if (!c.labels.includes(removed.id)) continue;
            c.labels = c.labels.filter((id) => id !== removed.id);
            c.updatedAt = nowIso();
            stripped++;
          }
        });
      }
    }
    return {
      deleted: removed,
      comments_referencing: referencing,
      removed_from_comments: stripped,
      note:
        referencing && !input.remove_from_comments
          ? 'Los comentarios conservan el id pero la app ya no muestra la etiqueta (igual que al borrarla desde Configuración).'
          : undefined,
    };
  }

  async reorderLabels(order: string[]) {
    return this.store.mutateSettings((s) => {
      const ids = Patchdeck.resolveLabels(s.labels, order);
      const first = ids.map((id) => s.labels.find((l) => l.id === id)!);
      s.labels = [...first, ...s.labels.filter((l) => !ids.includes(l.id))];
      return s.labels.map((l) => ({ id: l.id, title: l.title }));
    });
  }

  // ------------------------------------------------------------ reviews

  async listReviews() {
    return (await this.store.listReviews()).map((s) => ({
      id: s.id,
      title: s.title,
      updatedAt: s.updatedAt,
      patches: s.patches,
      comments: s.comments,
    }));
  }

  async getReview(ref: string) {
    const r = await this.store.loadReview(await this.resolveReviewId(ref));
    const all = await this.labels();
    const viewed = new Set(r.viewed ?? []);
    return {
      id: r.id,
      title: r.title,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      context: r.context,
      notes: r.notes,
      patches: r.patches.map((p) => {
        const parsed = this.parse(p);
        return {
          id: p.id,
          name: p.name,
          ...(parsed.preamble ? { message: parsed.preamble.slice(0, 2000) } : {}),
          files: parsed.files.map((f) => ({
            path: filePath(f),
            ...(f.oldPath !== f.newPath && f.status !== 'added' && f.status !== 'deleted' ? { oldPath: f.oldPath } : {}),
            status: f.status,
            additions: f.additions,
            deletions: f.deletions,
            ...(f.isBinary ? { binary: true } : {}),
            viewed: viewed.has(`${p.id}|${filePath(f)}`),
            comments: r.comments.filter((c) => c.anchors.some((a) => a.patch === p.id && a.path === filePath(f))).length,
          })),
        };
      }),
      comments: r.comments.map((c) => this.commentView(r, c, all)),
    };
  }

  async getPatch(input: { review: string; patch?: string; file?: string; max_lines?: number; format?: 'annotated' | 'raw' }) {
    const r = await this.store.loadReview(await this.resolveReviewId(input.review));
    const p = this.findPatch(r, input.patch);
    const maxLines = input.max_lines ?? 3000;
    if (input.format === 'raw' && !input.file) {
      const lines = p.raw.split('\n');
      return truncate(lines, maxLines, `patch ${p.name}`);
    }
    const parsed = this.parse(p);
    const files = input.file ? [this.findFile(parsed, input.file)] : parsed.files;
    const commented = new Map<string, Set<string>>();
    for (const c of r.comments) {
      if (c.dismissed) continue;
      for (const a of c.anchors) {
        if (a.patch !== p.id) continue;
        let s = commented.get(a.path);
        if (!s) commented.set(a.path, (s = new Set()));
        s.add(`${a.old ?? ''}|${a.new ?? ''}`);
      }
    }
    const header = [
      `Patch ${p.name} de "${r.title}". Columnas: línea vieja, línea nueva | marcador y código.`,
      'Para comentar usa la línea nueva (side "new") o, en líneas eliminadas (-), la vieja (side "old").',
      '',
    ];
    return truncate([...header, ...renderPatch(parsed, files, commented)], maxLines, 'la salida');
  }

  async createReview(input: { title: string; context?: string; notes?: string }) {
    const r = await this.store.createReview(input.title, input.context ?? '', input.notes ?? '');
    return { id: r.id, title: r.title };
  }

  async updateReview(input: { review: string; title?: string; context?: string; notes?: string; append?: boolean }) {
    const id = await this.resolveReviewId(input.review);
    const { review } = await this.store.mutateReview(id, (r) => {
      if (input.title !== undefined) {
        if (!input.title.trim()) throw new UserError('El título no puede quedar vacío.');
        r.title = input.title.trim();
      }
      const join = (old: string, add: string) => (input.append && old.trim() ? `${old.trimEnd()}\n\n${add}` : add);
      if (input.context !== undefined) r.context = join(r.context, input.context);
      if (input.notes !== undefined) r.notes = join(r.notes, input.notes);
    });
    return { id: review.id, title: review.title, context: review.context, notes: review.notes };
  }

  async addPatch(input: { review: string; diff?: string; file_path?: string; name?: string }) {
    if ((input.diff === undefined) === (input.file_path === undefined)) {
      throw new UserError('Pasa exactamente uno de "diff" o "file_path".');
    }
    const raw = input.diff ?? (await fs.readFile(input.file_path!, 'utf8'));
    const parsed = parsePatch(raw);
    if (!parsed.files.length) throw new UserError('El texto no parece un diff unificado (no encontré archivos).');
    const id = await this.resolveReviewId(input.review);
    const { result } = await this.store.mutateReview(id, (r) => {
      const name = input.name?.trim() || nextPatchName(r.patches.map((p) => p.name));
      if (r.patches.some((p) => p.name === name)) throw new UserError(`Ya hay un patch "${name}".`);
      const p: PatchJson = { id: newId(), name, createdAt: nowIso(), raw };
      r.patches.push(p);
      return p;
    });
    return {
      id: result.id,
      name: result.name,
      files: parsed.files.map((f) => ({ path: filePath(f), status: f.status, additions: f.additions, deletions: f.deletions })),
    };
  }

  async renamePatch(input: { review: string; patch: string; name: string }) {
    const id = await this.resolveReviewId(input.review);
    const { result } = await this.store.mutateReview(id, (r) => {
      const p = this.findPatch(r, input.patch);
      const name = input.name.trim();
      if (!name) throw new UserError('El nombre no puede quedar vacío.');
      if (r.patches.some((x) => x !== p && x.name === name)) throw new UserError(`Ya hay un patch "${name}".`);
      p.name = name;
      return { id: p.id, name };
    });
    return result;
  }

  async setFileViewed(input: { review: string; patch?: string; path: string; viewed: boolean }) {
    const id = await this.resolveReviewId(input.review);
    const { result } = await this.store.mutateReview(id, (r) => {
      const p = this.findPatch(r, input.patch);
      const path = filePath(this.findFile(this.parse(p), input.path));
      const key = `${p.id}|${path}`;
      const set = new Set(r.viewed ?? []);
      if (input.viewed) set.add(key);
      else set.delete(key);
      r.viewed = [...set];
      return { patch: p.name, path, viewed: input.viewed };
    });
    return result;
  }

  // ----------------------------------------------------------- comments

  async listComments(input: { review: string } & CommentFilters) {
    const r = await this.store.loadReview(await this.resolveReviewId(input.review));
    const all = await this.labels();
    const patch = input.patch !== undefined ? this.findPatch(r, input.patch) : undefined;
    const labelId = input.label !== undefined ? Patchdeck.resolveLabel(all, input.label).id : undefined;
    const path = input.path?.trim().replace(/^[ab]\//, '');
    return r.comments
      .filter((c) => input.include_dismissed !== false || !c.dismissed)
      .filter((c) => !patch || c.anchors.some((a) => a.patch === patch.id))
      .filter((c) => !path || c.anchors.some((a) => a.path === path || a.path.endsWith('/' + path)))
      .filter((c) => !labelId || c.labels.includes(labelId))
      .map((c) => this.commentView(r, c, all));
  }

  async addComment(input: { review: string; text: string; locations: LocationInput[]; labels?: string[] }) {
    if (!input.text.trim()) throw new UserError('El comentario no puede estar vacío.');
    const id = await this.resolveReviewId(input.review);
    const all = await this.labels();
    const labelIds = Patchdeck.resolveLabels(all, input.labels ?? []);
    const { review, result } = await this.store.mutateReview(id, (r) => {
      const now = nowIso();
      const c: CommentJson = {
        id: newId(),
        anchors: this.resolveLocations(r, input.locations),
        labels: labelIds,
        text: input.text,
        createdAt: now,
        updatedAt: now,
      };
      r.comments.push(c);
      return c;
    });
    return this.commentView(review, result, all);
  }

  async updateComment(input: {
    review: string;
    comment_id: string;
    text?: string;
    labels?: string[];
    add_labels?: string[];
    remove_labels?: string[];
    dismissed?: boolean;
    locations?: LocationInput[];
  }) {
    const id = await this.resolveReviewId(input.review);
    const all = await this.labels();
    const { review, result } = await this.store.mutateReview(id, (r) => {
      const c = r.comments.find((x) => x.id === input.comment_id);
      if (!c) throw new UserError(`No existe el comentario ${input.comment_id} en la review.`);
      if (input.text !== undefined) {
        if (!input.text.trim()) throw new UserError('El comentario no puede quedar vacío.');
        c.text = input.text;
      }
      let labels = input.labels !== undefined ? Patchdeck.resolveLabels(all, input.labels) : [...c.labels];
      if (input.add_labels) labels = [...new Set([...labels, ...Patchdeck.resolveLabels(all, input.add_labels)])];
      if (input.remove_labels) {
        const drop = new Set(input.remove_labels.map((ref) => all.find((l) => l.id === ref)?.id ?? Patchdeck.resolveLabel(all, ref).id));
        labels = labels.filter((l) => !drop.has(l));
      }
      c.labels = labels;
      if (input.dismissed !== undefined) c.dismissed = input.dismissed;
      if (input.locations !== undefined) c.anchors = this.resolveLocations(r, input.locations);
      c.updatedAt = nowIso();
      return c;
    });
    return this.commentView(review, result, all);
  }

  async deleteComment(input: { review: string; comment_id: string }) {
    const id = await this.resolveReviewId(input.review);
    await this.store.mutateReview(id, (r) => {
      const i = r.comments.findIndex((c) => c.id === input.comment_id);
      if (i < 0) throw new UserError(`No existe el comentario ${input.comment_id} en la review.`);
      r.comments.splice(i, 1);
    });
    return { deleted: input.comment_id };
  }

  async exportReview(input: { review: string; format?: 'markdown' | 'comments' }) {
    const r = await this.store.loadReview(await this.resolveReviewId(input.review));
    const settings = await this.store.loadSettings();
    const label = this.labelLookup(settings.labels);
    if (input.format === 'comments') {
      return exportAllCommentsText(r, label, settings.copy?.template ?? defaultCopyTemplate);
    }
    return exportReviewMarkdown(r, label);
  }
}

function hunkRanges(f: DiffFile): string {
  if (!f.hunks.length) return 'ninguno (archivo sin hunks)';
  return f.hunks
    .map((h) => {
      const news = h.lines.filter((l) => l.kind !== 'del' && l.new !== undefined).map((l) => l.new!);
      const olds = h.lines.filter((l) => l.kind !== 'add' && l.old !== undefined).map((l) => l.old!);
      const range = (v: number[]) => (v.length ? `${Math.min(...v)}-${Math.max(...v)}` : '—');
      return `nuevas ${range(news)} / viejas ${range(olds)}`;
    })
    .join('; ');
}

function truncate(lines: string[], max: number, what: string): string {
  if (lines.length <= max) return lines.join('\n');
  return (
    lines.slice(0, max).join('\n') +
    `\n\n[… ${what} se cortó en ${max} de ${lines.length} líneas; pide un archivo con "file" o sube "max_lines".]`
  );
}
