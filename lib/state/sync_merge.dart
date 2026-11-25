import 'dart:convert';

import '../models/app_settings.dart';
import '../models/label.dart';
import '../models/review.dart';

/// Three-way merges for files that other processes (the MCP server) may
/// rewrite while the app has them open.
///
/// `base` is what was on disk when we last read or wrote it, `local` is the
/// app's in-memory state and `remote` is the file as it is now. A side that
/// didn't touch something takes the other side's version; when both changed
/// the same comment, the most recently updated one wins.

/// The on-disk state of a review the last time we synced with it.
class ReviewSnapshot {
  ReviewSnapshot.of(Review r)
    : title = r.title,
      context = r.contextMarkdown,
      notes = r.notesMarkdown,
      patches = {for (final p in r.patches) p.id: p},
      comments = {for (final c in r.comments) c.id: c},
      viewed = Set.of(r.viewedFiles);

  final String title;
  final String context;
  final String notes;
  final Map<String, PatchEntry> patches;
  final Map<String, ReviewComment> comments;
  final Set<String> viewed;
}

String _json(Object? o) => jsonEncode(o);

bool _sameComment(ReviewComment a, ReviewComment b) => identical(a, b) || _json(a.toJson()) == _json(b.toJson());
bool _samePatch(PatchEntry a, PatchEntry b) => identical(a, b) || (a.name == b.name && a.raw == b.raw);

/// Merges [remote] into [local] (in place).
void mergeReviewInto(Review local, ReviewSnapshot base, Review remote) {
  String pick(String b, String l, String r) => l == b ? r : l;
  local
    ..title = pick(base.title, local.title, remote.title)
    ..contextMarkdown = pick(base.context, local.contextMarkdown, remote.contextMarkdown)
    ..notesMarkdown = pick(base.notes, local.notesMarkdown, remote.notesMarkdown);
  if (remote.updatedAt.isAfter(local.updatedAt)) local.updatedAt = remote.updatedAt;

  final patches = _mergeById<PatchEntry>(
    base: base.patches,
    local: local.patches,
    remote: remote.patches,
    idOf: (p) => p.id,
    same: _samePatch,
    // Both renamed the same patch: keep the local name.
    resolve: (l, r) => l,
  );
  local.patches
    ..clear()
    ..addAll(patches);

  final comments = _mergeById<ReviewComment>(
    base: base.comments,
    local: local.comments,
    remote: remote.comments,
    idOf: (c) => c.id,
    same: _sameComment,
    resolve: (l, r) => r.updatedAt.isAfter(l.updatedAt) ? r : l,
  );
  local.comments
    ..clear()
    ..addAll(comments);

  final addedRemotely = remote.viewedFiles.difference(base.viewed);
  final removedRemotely = base.viewed.difference(remote.viewedFiles);
  final viewed = local.viewedFiles.difference(removedRemotely).union(addedRemotely);
  local.viewedFiles
    ..clear()
    ..addAll(viewed);
}

/// Items in remote order, then the ones only the local side added.
List<T> _mergeById<T>({
  required Map<String, T> base,
  required List<T> local,
  required List<T> remote,
  required String Function(T) idOf,
  required bool Function(T, T) same,
  required T Function(T local, T remote) resolve,
}) {
  final localById = {for (final x in local) idOf(x): x};
  final remoteIds = {for (final x in remote) idOf(x)};
  final out = <T>[];
  for (final r in remote) {
    final id = idOf(r);
    final b = base[id];
    final l = localById[id];
    if (l == null) {
      // Not in local: added remotely (keep) or deleted locally (drop, unless
      // the remote side changed it since).
      if (b == null || !same(b, r)) out.add(r);
      continue;
    }
    if (b == null) {
      out.add(resolve(l, r)); // both added the same id (unlikely)
    } else if (same(l, b)) {
      out.add(r);
    } else if (same(r, b)) {
      out.add(l);
    } else {
      out.add(resolve(l, r));
    }
  }
  for (final l in local) {
    final id = idOf(l);
    if (remoteIds.contains(id)) continue;
    final b = base[id];
    // Added locally (keep) or deleted remotely (drop, unless edited locally).
    if (b == null || !same(l, b)) out.add(l);
  }
  return out;
}

/// Merges settings: labels by id (and their order), the rest as a whole.
AppSettings mergeSettings({required AppSettings base, required AppSettings local, required AppSettings remote}) {
  Map<String, dynamic> rest(AppSettings s) => s.toJson()..remove('labels');
  final restLocalChanged = _json(rest(local)) != _json(rest(base));
  final merged = restLocalChanged ? local : remote;

  bool same(ReviewLabel a, ReviewLabel b) => _json(a.toJson()) == _json(b.toJson());
  final labels = _mergeById<ReviewLabel>(
    base: {for (final l in base.labels) l.id: l},
    local: local.labels,
    remote: remote.labels,
    idOf: (l) => l.id,
    same: same,
    resolve: (l, r) => l,
  );
  // Keep the local order if the user reordered; otherwise the remote order.
  final baseOrder = [for (final l in base.labels) l.id].join(',');
  final localOrder = [for (final l in local.labels) l.id].join(',');
  if (baseOrder != localOrder) {
    final pos = {for (var i = 0; i < local.labels.length; i++) local.labels[i].id: i};
    final big = local.labels.length;
    final indexed = [for (var i = 0; i < labels.length; i++) (i, labels[i])];
    indexed.sort((a, b) {
      final pa = pos[a.$2.id] ?? big + a.$1;
      final pb = pos[b.$2.id] ?? big + b.$1;
      return pa.compareTo(pb);
    });
    labels
      ..clear()
      ..addAll([for (final e in indexed) e.$2]);
  }
  return merged.copyWith(labels: labels);
}
