/**
 * Text output, ported from `lib/state/comment_format.dart` and
 * `lib/state/review_export.dart` so Claude produces exactly what the app copies.
 */
import { filePath, type DiffFile, type ParsedPatch } from './diff.js';
import { defaultCopyTemplate, type AnchorJson, type CommentJson, type LabelJson, type ReviewJson } from './store.js';

type LabelById = (id: string) => LabelJson | undefined;

function compress(v: number[]): string {
  const parts: string[] = [];
  for (let i = 0; i < v.length; ) {
    let j = i;
    while (j + 1 < v.length && v[j + 1] === v[j]! + 1) j++;
    parts.push(i === j ? `L${v[i]}` : `L${v[i]}-L${v[j]}`);
    i = j + 1;
  }
  return parts.join(', ');
}

const isWholeFile = (a: AnchorJson) => a.old == null && a.new == null;

/** "L3-L5, L9" for new-side lines, "L7-L8 (eliminadas)" for deleted ones. */
export function lineRanges(anchors: AnchorJson[]): string {
  const news = [...new Set(anchors.filter((a) => a.new != null).map((a) => a.new!))].sort((a, b) => a - b);
  const olds = [...new Set(anchors.filter((a) => a.new == null && a.old != null).map((a) => a.old!))].sort(
    (a, b) => a - b,
  );
  const out: string[] = [];
  if (anchors.some(isWholeFile)) out.push('(archivo completo)');
  if (news.length) out.push(compress(news));
  if (olds.length) out.push(`${compress(olds)} (${olds.length === 1 ? 'eliminada' : 'eliminadas'})`);
  return out.join(', ');
}

function groupAnchors(anchors: AnchorJson[], patchId?: string): Map<string, Map<string, AnchorJson[]>> {
  const byPatch = new Map<string, Map<string, AnchorJson[]>>();
  for (const a of anchors) {
    if (patchId !== undefined && a.patch !== patchId) continue;
    let files = byPatch.get(a.patch);
    if (!files) byPatch.set(a.patch, (files = new Map()));
    let list = files.get(a.path);
    if (!list) files.set(a.path, (list = []));
    list.push(a);
  }
  return byPatch;
}

export function describeLocations(anchors: AnchorJson[], patchNames: Map<string, string>, patchId?: string): string {
  const byPatch = groupAnchors(anchors, patchId);
  const multi = byPatch.size > 1;
  const parts: string[] = [];
  for (const [pid, files] of byPatch) {
    const joined = [...files].map(([p, l]) => `${p} ${lineRanges(l)}`).join(' · ');
    parts.push(multi ? `${patchNames.get(pid) ?? '?'}: ${joined}` : joined);
  }
  return parts.join(' | ');
}

/** `formatComment` from the app: fills `{{fileName + lines}}`, `{{commentText}}`, … */
export function formatComment(
  c: CommentJson,
  labelById: LabelById,
  patchNames: Map<string, string>,
  template: string = defaultCopyTemplate,
  patchId?: string,
): string {
  const byPatch = groupAnchors(c.anchors, patchId);
  const multi = byPatch.size > 1;
  const locations = (fmt: (path: string, lines: AnchorJson[]) => string) => {
    const parts: string[] = [];
    for (const [pid, files] of byPatch) {
      const joined = [...files].map(([p, l]) => fmt(p, l)).join(' · ');
      parts.push(multi ? `${patchNames.get(pid) ?? '?'}: ${joined}` : joined);
    }
    return parts.join(' | ');
  };
  const base = (p: string) => p.split('/').pop() ?? p;
  const values: Record<string, () => string> = {
    'filename+lines': () => locations((p, l) => `${base(p)} ${lineRanges(l)}`),
    'filepath+lines': () => locations((p, l) => `${p} ${lineRanges(l)}`),
    filename: () => locations((p) => base(p)),
    filepath: () => locations((p) => p),
    lines: () => locations((_, l) => lineRanges(l)),
    commenttext: () => c.text.trim(),
    commenttags: () =>
      c.labels
        .map((id) => labelById(id)?.title)
        .filter((t): t is string => t !== undefined)
        .join(', '),
    patchname: () => [...byPatch.keys()].map((pid) => patchNames.get(pid) ?? '?').join(', '),
  };
  return template
    .replace(/\{\{\s*([^}]*?)\s*\}\}/g, (m, key: string) => {
      const k = key.replace(/\s+/g, '').toLowerCase();
      return values[k]?.() ?? m;
    })
    .trim();
}

export function commentsForPatch(r: ReviewJson, patchId: string, includeDismissed = false): CommentJson[] {
  return r.comments.filter((c) => (includeDismissed || !c.dismissed) && c.anchors.some((a) => a.patch === patchId));
}

/** "Copiar todos": every active comment with the copy template, grouped by patch. */
export function exportAllCommentsText(r: ReviewJson, labelById: LabelById, template: string): string {
  const names = new Map(r.patches.map((p) => [p.id, p.name]));
  const sections: string[] = [];
  for (const p of r.patches) {
    const text = commentsForPatch(r, p.id)
      .map((c) => formatComment(c, labelById, names, template, p.id))
      .join('\n\n');
    if (text) sections.push(`Patch ${p.name}\n\n${text}`);
  }
  return sections.join('\n\n');
}

/** Same Markdown as "Copiar review" in the finalize screen. */
export function exportReviewMarkdown(r: ReviewJson, labelById: LabelById): string {
  const names = new Map(r.patches.map((p) => [p.id, p.name]));
  let b = `# ${r.title}\n\n`;
  if (r.context.trim()) b += `## Contexto\n\n${r.context.trim()}\n\n`;
  for (const p of r.patches) {
    const comments = commentsForPatch(r, p.id);
    if (!comments.length) continue;
    b += `## Patch ${p.name}\n\n`;
    for (const c of comments) {
      const labels = c.labels.map((id) => labelById(id)?.title).filter((t): t is string => t !== undefined);
      b += '- ';
      if (labels.length) b += labels.map((l) => `\`${l}\``).join(' ') + ' ';
      b += `**${describeLocations(c.anchors, names, p.id)}**\n`;
      b += `  ${c.text.trim().replace(/\n/g, '\n  ')}\n`;
    }
    b += '\n';
  }
  if (r.notes.trim()) b += `## Notas\n\n${r.notes.trim()}\n\n`;
  return b;
}

// ------------------------------------------------------------ patch rendering

const sigil = { context: ' ', add: '+', del: '-', noNewline: '\\' } as const;

/**
 * Diff with explicit line numbers, one row per line:
 * `  old   new | +code`. These are the numbers `add_comment` expects.
 */
export function renderFile(f: DiffFile, commented?: Set<string>): string[] {
  const out: string[] = [];
  const pathLabel =
    (f.status === 'renamed' || f.status === 'copied') && f.oldPath !== f.newPath
      ? `${f.oldPath} → ${f.newPath}`
      : filePath(f);
  out.push(`=== ${pathLabel} (${f.status}, +${f.additions} -${f.deletions})${f.isBinary ? ' [binario]' : ''}`);
  for (const h of f.hunks) {
    out.push(h.header);
    for (const l of h.lines) {
      const o = l.kind === 'add' || l.old == null ? '' : String(l.old);
      const n = l.kind === 'del' || l.new == null ? '' : String(l.new);
      const key = `${l.kind === 'add' ? '' : (l.old ?? '')}|${l.kind === 'del' ? '' : (l.new ?? '')}`;
      const mark = commented?.has(key) ? '  ◀ comentado' : '';
      out.push(`${o.padStart(6)} ${n.padStart(6)} | ${sigil[l.kind]}${l.text}${mark}`);
    }
  }
  return out;
}

export function renderPatch(parsed: ParsedPatch, files: DiffFile[], commentedByPath: Map<string, Set<string>>): string[] {
  const out: string[] = [];
  if (parsed.preamble && files.length === parsed.files.length) out.push(parsed.preamble, '');
  for (const f of files) {
    out.push(...renderFile(f, commentedByPath.get(filePath(f))), '');
  }
  return out;
}
