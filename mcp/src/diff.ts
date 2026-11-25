/**
 * Unified-diff parser — a port of `lib/diff/diff_parser.dart` (without syntax
 * highlighting). It must number lines and pick file paths exactly like the
 * app, because comment anchors are `(patch, path, old line, new line)`.
 */

export type LineKind = 'context' | 'add' | 'del' | 'noNewline';
export type FileStatus = 'modified' | 'added' | 'deleted' | 'renamed' | 'copied';

export interface DiffLine {
  kind: LineKind;
  old?: number;
  new?: number;
  text: string;
}

export interface DiffHunk {
  header: string;
  oldStart: number;
  newStart: number;
  section: string;
  lines: DiffLine[];
}

export interface DiffFile {
  oldPath: string;
  newPath: string;
  status: FileStatus;
  isBinary: boolean;
  hunks: DiffHunk[];
  additions: number;
  deletions: number;
}

export interface ParsedPatch {
  preamble: string;
  files: DiffFile[];
}

/** Path used for anchoring comments (same rule as `DiffFile.path` in Dart). */
export function filePath(f: DiffFile): string {
  return f.status === 'deleted' ? f.oldPath : f.newPath;
}

const hunkRe = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@ ?(.*)$/;

/** Same semantics as Dart's `LineSplitter`: no trailing empty line. */
function splitLines(raw: string): string[] {
  if (raw.length === 0) return [];
  const lines = raw.split(/\r\n|\r|\n/);
  if (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();
  return lines;
}

interface FileBuilder extends DiffFile {}
interface HunkBuilder extends DiffHunk {
  oldNo: number;
  newNo: number;
}

export function parsePatch(raw: string): ParsedPatch {
  const lines = splitLines(raw);
  const files: DiffFile[] = [];
  const preamble: string[] = [];

  let file: FileBuilder | null = null;
  let hunk: HunkBuilder | null = null;
  let oldLeft = 0;
  let newLeft = 0;

  const closeHunk = () => {
    if (hunk && file) {
      const { oldNo: _o, newNo: _n, ...h } = hunk;
      file.hunks.push(h);
    }
    hunk = null;
    oldLeft = newLeft = 0;
  };
  const closeFile = () => {
    closeHunk();
    if (file) files.push(file);
    file = null;
  };
  const newFile = (oldPath: string, newPath: string): FileBuilder => ({
    oldPath,
    newPath,
    status: 'modified',
    isBinary: false,
    hunks: [],
    additions: 0,
    deletions: 0,
  });

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]!;

    // Inside a hunk the counters say exactly how many lines belong to it.
    if (hunk !== null && (oldLeft > 0 || newLeft > 0)) {
      const h: HunkBuilder = hunk;
      const c = line.length === 0 ? ' ' : line[0];
      const text = line.length === 0 ? '' : line.slice(1);
      if (c === ' ') {
        h.lines.push({ kind: 'context', old: h.oldNo++, new: h.newNo++, text });
        oldLeft--;
        newLeft--;
        continue;
      }
      if (c === '-') {
        h.lines.push({ kind: 'del', old: h.oldNo++, text });
        file!.deletions++;
        oldLeft--;
        continue;
      }
      if (c === '+') {
        h.lines.push({ kind: 'add', new: h.newNo++, text });
        file!.additions++;
        newLeft--;
        continue;
      }
      if (c === '\\') {
        h.lines.push({ kind: 'noNewline', text: 'No newline at end of file' });
        continue;
      }
      closeHunk(); // malformed counts: fall through to header handling
    } else if (hunk !== null && line.startsWith('\\')) {
      (hunk as HunkBuilder).lines.push({ kind: 'noNewline', text: 'No newline at end of file' });
      continue;
    }

    if (line.startsWith('diff --git ')) {
      closeFile();
      const [o, n] = splitGitPaths(line.slice(11));
      file = newFile(o, n);
      continue;
    }
    if (line.startsWith('@@ ') && file !== null) {
      closeHunk();
      const m = hunkRe.exec(line);
      if (!m) continue;
      const os = parseInt(m[1]!, 10);
      const ns = parseInt(m[3]!, 10);
      oldLeft = m[2] === undefined ? 1 : parseInt(m[2], 10);
      newLeft = m[4] === undefined ? 1 : parseInt(m[4], 10);
      hunk = { header: line, oldStart: os, newStart: ns, section: m[5] ?? '', lines: [], oldNo: os, newNo: ns };
      continue;
    }
    if (line.startsWith('--- ') && i + 1 < lines.length && lines[i + 1]!.startsWith('+++ ')) {
      const oldP = stripPrefix(line.slice(4));
      const newP = stripPrefix(lines[i + 1]!.slice(4));
      let f = file as FileBuilder | null;
      if (f === null || f.hunks.length > 0 || hunk !== null) {
        // Plain `diff -u` without a `diff --git` header.
        closeFile();
        f = file = newFile(oldP ?? newP ?? '', newP ?? oldP ?? '');
      }
      if (oldP === null) f.status = 'added';
      if (newP === null) f.status = 'deleted';
      if (oldP !== null) f.oldPath = oldP;
      if (newP !== null) f.newPath = newP;
      i++;
      continue;
    }
    const f = file as FileBuilder | null;
    if (f !== null && hunk === null) {
      if (line.startsWith('new file mode')) {
        f.status = 'added';
        continue;
      }
      if (line.startsWith('deleted file mode')) {
        f.status = 'deleted';
        continue;
      }
      if (line.startsWith('rename from ')) {
        f.status = 'renamed';
        f.oldPath = line.slice(12);
        continue;
      }
      if (line.startsWith('rename to ')) {
        f.status = 'renamed';
        f.newPath = line.slice(10);
        continue;
      }
      if (line.startsWith('copy from ')) {
        f.status = 'copied';
        f.oldPath = line.slice(10);
        continue;
      }
      if (line.startsWith('copy to ')) {
        f.status = 'copied';
        f.newPath = line.slice(8);
        continue;
      }
      if (line.startsWith('Binary files ') || line.startsWith('GIT binary patch')) {
        f.isBinary = true;
        continue;
      }
      if (
        line.startsWith('index ') ||
        line.startsWith('similarity index') ||
        line.startsWith('dissimilarity index') ||
        line.startsWith('old mode') ||
        line.startsWith('new mode')
      ) {
        continue;
      }
      if (f.isBinary) continue; // binary payload
    }
    // Everything else: commit headers / messages / signature.
    if (file !== null) closeFile();
    if (line === '-- ' || (preamble.length === 0 && line.trim() === '')) continue;
    if (i > 0 && lines[i - 1] === '-- ' && /^\d+\.\d+/.test(line)) continue;
    preamble.push(line);
  }
  closeFile();
  return { preamble: preamble.join('\n').trimEnd(), files };
}

function stripPrefix(p: string): string | null {
  let s = p;
  const tab = s.indexOf('\t');
  if (tab >= 0) s = s.slice(0, tab);
  if (s.startsWith('"') && s.endsWith('"') && s.length > 1) s = s.slice(1, -1);
  if (s === '/dev/null') return null;
  if (s.startsWith('a/') || s.startsWith('b/')) return s.slice(2);
  return s;
}

function splitGitPaths(rest: string): [string, string] {
  const mid = rest.indexOf(' b/');
  if (mid > 0) return [stripPrefix(rest.slice(0, mid)) ?? '', stripPrefix(rest.slice(mid + 1)) ?? ''];
  const parts = rest.split(' ');
  return [stripPrefix(parts[0]!) ?? '', stripPrefix(parts[parts.length - 1]!) ?? ''];
}
