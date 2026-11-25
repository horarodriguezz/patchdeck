import { randomBytes } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';

import type { Paths } from './paths.js';

// ------------------------------------------------------------------ JSON shapes
// These mirror the `toJson` / `fromJson` of the Dart models. Unknown keys are
// kept as they are so that a newer app version never loses data to this server.

export interface AnchorJson {
  patch: string;
  path: string;
  old?: number;
  new?: number;
}

export interface CommentJson {
  id: string;
  anchors: AnchorJson[];
  labels: string[];
  text: string;
  createdAt: string;
  updatedAt: string;
  dismissed?: boolean;
  [k: string]: unknown;
}

export interface PatchJson {
  id: string;
  name: string;
  createdAt: string;
  raw: string;
  [k: string]: unknown;
}

export interface ReviewJson {
  version: number;
  id: string;
  title: string;
  createdAt: string;
  updatedAt: string;
  context: string;
  notes: string;
  patches: PatchJson[];
  comments: CommentJson[];
  viewed?: string[];
  [k: string]: unknown;
}

export interface ReviewSummaryJson {
  id: string;
  title: string;
  createdAt: string;
  updatedAt: string;
  patches: string[];
  comments: number;
}

export interface LabelJson {
  id: string;
  title: string;
  description: string;
  color: string;
  [k: string]: unknown;
}

export interface SettingsJson {
  labels: LabelJson[];
  copy?: { template?: string; [k: string]: unknown };
  [k: string]: unknown;
}

/** Same defaults as `AppSettings.defaults()` (used when settings.json does not exist). */
export const defaultLabels: LabelJson[] = [
  { id: 'bug', title: 'bug', description: 'Comportamiento incorrecto', color: '#ffe5534b' },
  { id: 'nit', title: 'nit', description: 'Detalle menor / estilo', color: '#ff8b949e' },
  { id: 'question', title: 'pregunta', description: 'Necesita aclaración', color: '#ff539bf5' },
  { id: 'perf', title: 'performance', description: 'Impacto en rendimiento', color: '#ffb083f0' },
  { id: 'security', title: 'seguridad', description: 'Riesgo de seguridad', color: '#ffe0823d' },
  { id: 'praise', title: 'bien hecho', description: 'Algo que vale la pena destacar', color: '#ff57ab5a' },
];

export const defaultCopyTemplate = '{{fileName + lines}}:  {{commentText}}';

// ------------------------------------------------------------------- helpers

export class UserError extends Error {}

/** 24-char random hex, like `newId()` in `lib/models/ids.dart`. */
export function newId(): string {
  return randomBytes(12).toString('hex');
}

/** Local time without offset, like Dart's `DateTime.now().toIso8601String()`. */
export function nowIso(d: Date = new Date()): string {
  const p = (n: number, w = 2) => String(n).padStart(w, '0');
  return (
    `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}` +
    `T${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}.${p(d.getMilliseconds(), 3)}`
  );
}

export function timeOf(iso: string): number {
  // Dart may write microseconds; JS only understands milliseconds.
  const t = Date.parse(iso.replace(/(\.\d{3})\d+/, '$1'));
  return Number.isNaN(t) ? 0 : t;
}

const safeId = /^[A-Za-z0-9_-]{1,64}$/;

export function assertSafeId(id: string): void {
  if (!safeId.test(id)) throw new UserError(`Id inválido: "${id}"`);
}

export async function readJson(file: string): Promise<unknown | undefined> {
  let text: string;
  try {
    text = await fs.readFile(file, 'utf8');
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code === 'ENOENT') return undefined;
    throw e;
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new UserError(`${file} no es JSON válido; no lo toco (revísalo a mano).`);
  }
}

/**
 * Atomic write (temp file + rename), like `JsonStore.write`. The temp name is
 * unique so it never collides with the app's own `<file>.tmp`.
 */
export async function writeJsonAtomic(file: string, data: unknown, pretty: boolean): Promise<void> {
  await fs.mkdir(path.dirname(file), { recursive: true });
  const tmp = `${file}.${process.pid}.${randomBytes(4).toString('hex')}.tmp`;
  await fs.writeFile(tmp, pretty ? JSON.stringify(data, null, 2) : JSON.stringify(data), 'utf8');
  try {
    await fs.rename(tmp, file);
  } catch (e) {
    await fs.rm(tmp, { force: true });
    throw e;
  }
}

/** Serializes async sections per key inside this process. */
class Locks {
  private tails = new Map<string, Promise<unknown>>();

  run<T>(key: string, fn: () => Promise<T>): Promise<T> {
    const prev = this.tails.get(key) ?? Promise.resolve();
    const next = prev.then(fn, fn);
    const tail = next.catch(() => undefined);
    this.tails.set(key, tail);
    void tail.then(() => {
      if (this.tails.get(key) === tail) this.tails.delete(key);
    });
    return next;
  }
}

// ------------------------------------------------------------- normalization

function str(v: unknown, fallback = ''): string {
  return typeof v === 'string' ? v : fallback;
}

function normalizeReview(j: Record<string, unknown>): ReviewJson {
  const now = nowIso();
  const patches = Array.isArray(j.patches) ? (j.patches as Record<string, unknown>[]) : [];
  const comments = Array.isArray(j.comments) ? (j.comments as Record<string, unknown>[]) : [];
  return {
    ...j,
    version: typeof j.version === 'number' ? j.version : 1,
    id: str(j.id),
    title: str(j.title, 'Sin título'),
    createdAt: str(j.createdAt, now),
    updatedAt: str(j.updatedAt, now),
    context: str(j.context),
    notes: str(j.notes),
    patches: patches.map((p) => ({
      ...p,
      id: str(p.id),
      name: str(p.name, '?'),
      createdAt: str(p.createdAt, now),
      raw: str(p.raw),
    })),
    comments: comments.map((c) => ({
      ...c,
      id: str(c.id),
      anchors: Array.isArray(c.anchors) ? (c.anchors as AnchorJson[]) : [],
      labels: Array.isArray(c.labels) ? (c.labels as unknown[]).filter((l): l is string => typeof l === 'string') : [],
      text: str(c.text),
      createdAt: str(c.createdAt, now),
      updatedAt: str(c.updatedAt, now),
    })),
  };
}

/** What `Review.toJson` writes; drops an empty `viewed` like the app does. */
function serializeReview(r: ReviewJson): ReviewJson {
  const out: ReviewJson = { ...r, comments: r.comments.map(serializeComment) };
  if (!out.viewed || out.viewed.length === 0) delete out.viewed;
  return out;
}

function serializeComment(c: CommentJson): CommentJson {
  const out: CommentJson = { ...c };
  if (!out.dismissed) delete out.dismissed;
  return out;
}

export function summaryOf(r: ReviewJson): ReviewSummaryJson {
  return {
    id: r.id,
    title: r.title,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
    patches: r.patches.map((p) => p.name),
    comments: r.comments.length,
  };
}

// --------------------------------------------------------------------- store

/**
 * Reads and writes Patchdeck's files. Every mutation is read-modify-write of a
 * single file under a lock, so the window in which the running app could
 * overwrite it (or vice versa) is as small as possible; the app watches the
 * directory and reloads what changes on disk.
 */
export class Store {
  private locks = new Locks();

  constructor(readonly paths: Paths) {}

  // ------------------------------------------------------------- reviews

  async listReviews(): Promise<ReviewSummaryJson[]> {
    const json = await readJson(this.paths.reviewsIndex).catch(() => undefined);
    const list = Array.isArray(json) ? (json as ReviewSummaryJson[]) : await this.rebuildIndex();
    return [...list].sort((a, b) => timeOf(b.updatedAt) - timeOf(a.updatedAt));
  }

  /** Every review file on disk (heavier: includes the patch bodies). */
  async allReviews(): Promise<ReviewJson[]> {
    let entries: string[];
    try {
      entries = await fs.readdir(this.paths.reviewsDir);
    } catch {
      return [];
    }
    const out: ReviewJson[] = [];
    for (const name of entries) {
      if (!name.endsWith('.json') || name === 'index.json') continue;
      const id = name.slice(0, -5);
      if (!safeId.test(id)) continue;
      const j = await readJson(path.join(this.paths.reviewsDir, name)).catch(() => undefined);
      if (j && typeof j === 'object' && !Array.isArray(j)) out.push(normalizeReview(j as Record<string, unknown>));
    }
    return out;
  }

  private async rebuildIndex(): Promise<ReviewSummaryJson[]> {
    return (await this.allReviews()).map(summaryOf);
  }

  async loadReview(id: string): Promise<ReviewJson> {
    assertSafeId(id);
    const j = await readJson(this.paths.reviewFile(id));
    if (!j || typeof j !== 'object' || Array.isArray(j)) throw new UserError(`No existe la review ${id}`);
    return normalizeReview(j as Record<string, unknown>);
  }

  async createReview(title: string, context = '', notes = ''): Promise<ReviewJson> {
    const now = nowIso();
    const r: ReviewJson = {
      version: 1,
      id: newId(),
      title: title.trim() || 'Review sin título',
      createdAt: now,
      updatedAt: now,
      context,
      notes,
      patches: [],
      comments: [],
    };
    await this.locks.run(r.id, () => this.saveReview(r));
    return r;
  }

  /** Loads, applies [fn], bumps `updatedAt` and saves (file + index). */
  async mutateReview<T>(id: string, fn: (r: ReviewJson) => T | Promise<T>): Promise<{ review: ReviewJson; result: T }> {
    assertSafeId(id);
    return this.locks.run(id, async () => {
      const review = await this.loadReview(id);
      const result = await fn(review);
      review.updatedAt = nowIso();
      await this.saveReview(review);
      return { review, result };
    });
  }

  private async saveReview(r: ReviewJson): Promise<void> {
    await writeJsonAtomic(this.paths.reviewFile(r.id), serializeReview(r), false);
    await this.locks.run('<index>', async () => {
      const json = await readJson(this.paths.reviewsIndex).catch(() => undefined);
      const idx = Array.isArray(json) ? (json as ReviewSummaryJson[]) : await this.rebuildIndex();
      const next = idx.filter((s) => s.id !== r.id);
      next.push(summaryOf(r));
      next.sort((a, b) => timeOf(b.updatedAt) - timeOf(a.updatedAt));
      await writeJsonAtomic(this.paths.reviewsIndex, next, true);
    });
  }

  // ------------------------------------------------------------ settings

  async loadSettings(): Promise<SettingsJson> {
    const j = await readJson(this.paths.settingsFile);
    const obj = j && typeof j === 'object' && !Array.isArray(j) ? (j as Record<string, unknown>) : {};
    // Same rule as AppSettings.fromJson: no `labels` list means the defaults.
    const labels = Array.isArray(obj.labels)
      ? (obj.labels as Record<string, unknown>[]).map((l) => ({
          ...l,
          id: str(l.id),
          title: str(l.title),
          description: str(l.description),
          color: normalizeStoredColor(l.color),
        }))
      : defaultLabels.map((l) => ({ ...l }));
    return { ...obj, labels } as SettingsJson;
  }

  /** Read-modify-write of settings.json that only touches what [fn] changes. */
  async mutateSettings<T>(fn: (s: SettingsJson) => T | Promise<T>): Promise<T> {
    return this.locks.run('<settings>', async () => {
      const s = await this.loadSettings();
      const result = await fn(s);
      if (s.version === undefined) s.version = 1;
      await writeJsonAtomic(this.paths.settingsFile, s, true);
      return result;
    });
  }
}

// ------------------------------------------------------------------ colors

/** `#AARRGGBB` lowercase, the format `ReviewLabel.toJson` writes. */
export function formatColor(argb: number): string {
  return '#' + (argb >>> 0).toString(16).padStart(8, '0');
}

/** Accepts `#RRGGBB` or `#AARRGGBB` (with or without `#`), like `ReviewLabel.parseColor`. */
export function parseColor(v: unknown): number | null {
  if (typeof v === 'number' && Number.isInteger(v)) return v >>> 0;
  if (typeof v !== 'string') return null;
  let s = v.trim().replace(/^#/, '');
  if (s.length === 6) s = 'FF' + s;
  if (s.length !== 8 || !/^[0-9a-fA-F]{8}$/.test(s)) return null;
  return parseInt(s, 16) >>> 0;
}

function normalizeStoredColor(v: unknown): string {
  return formatColor(parseColor(v) ?? 0xff8b949e);
}
