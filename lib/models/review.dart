/// A pointer to a concrete line of a concrete patch.
///
/// Anchors are stable across re-parsing (they don't depend on list indices),
/// which is what gets persisted.
class LineAnchor {
  const LineAnchor({required this.patchId, required this.path, this.oldLine, this.newLine});

  final String patchId;
  final String path;
  final int? oldLine;
  final int? newLine;

  String get key => '$patchId|$path|${oldLine ?? ''}|${newLine ?? ''}';

  @override
  bool operator ==(Object other) => other is LineAnchor && other.key == key;

  @override
  int get hashCode => key.hashCode;

  Map<String, dynamic> toJson() => {
    'patch': patchId,
    'path': path,
    if (oldLine != null) 'old': oldLine,
    if (newLine != null) 'new': newLine,
  };

  factory LineAnchor.fromJson(Map<String, dynamic> j) => LineAnchor(
    patchId: j['patch'] as String,
    path: j['path'] as String,
    oldLine: j['old'] as int?,
    newLine: j['new'] as int?,
  );
}

class ReviewComment {
  ReviewComment({
    required this.id,
    required this.anchors,
    required this.labelIds,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.dismissed = false,
  });

  final String id;
  final List<LineAnchor> anchors;
  final List<String> labelIds;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// "Denegado": kept for the record but muted everywhere and never copied
  /// by the bulk copy actions.
  final bool dismissed;

  ReviewComment copyWith({List<LineAnchor>? anchors, List<String>? labelIds, String? text, bool? dismissed}) =>
      ReviewComment(
        id: id,
        anchors: anchors ?? this.anchors,
        labelIds: labelIds ?? this.labelIds,
        text: text ?? this.text,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        dismissed: dismissed ?? this.dismissed,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'anchors': [for (final a in anchors) a.toJson()],
    'labels': labelIds,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (dismissed) 'dismissed': true,
  };

  factory ReviewComment.fromJson(Map<String, dynamic> j) => ReviewComment(
    id: j['id'] as String,
    anchors: [
      for (final a in (j['anchors'] as List? ?? const [])) LineAnchor.fromJson((a as Map).cast<String, dynamic>()),
    ],
    labelIds: [for (final l in (j['labels'] as List? ?? const [])) l as String],
    text: j['text'] as String? ?? '',
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
    dismissed: j['dismissed'] as bool? ?? false,
  );
}

class PatchEntry {
  PatchEntry({required this.id, required this.name, required this.raw, required this.createdAt});

  final String id;
  final String name;
  final String raw;
  final DateTime createdAt;

  PatchEntry copyWith({String? name}) => PatchEntry(id: id, name: name ?? this.name, raw: raw, createdAt: createdAt);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'createdAt': createdAt.toIso8601String(), 'raw': raw};

  factory PatchEntry.fromJson(Map<String, dynamic> j) => PatchEntry(
    id: j['id'] as String,
    name: j['name'] as String? ?? '?',
    raw: j['raw'] as String? ?? '',
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class Review {
  Review({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.contextMarkdown = '',
    this.notesMarkdown = '',
    List<PatchEntry>? patches,
    List<ReviewComment>? comments,
  }) : patches = patches ?? [],
       comments = comments ?? [];

  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  String contextMarkdown;
  String notesMarkdown;
  final List<PatchEntry> patches;
  final List<ReviewComment> comments;

  ReviewSummary get summary => ReviewSummary(
    id: id,
    title: title,
    createdAt: createdAt,
    updatedAt: updatedAt,
    patchNames: [for (final p in patches) p.name],
    commentCount: comments.length,
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'context': contextMarkdown,
    'notes': notesMarkdown,
    'patches': [for (final p in patches) p.toJson()],
    'comments': [for (final c in comments) c.toJson()],
  };

  factory Review.fromJson(Map<String, dynamic> j) => Review(
    id: j['id'] as String,
    title: j['title'] as String? ?? 'Sin título',
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
    contextMarkdown: j['context'] as String? ?? '',
    notesMarkdown: j['notes'] as String? ?? '',
    patches: [
      for (final p in (j['patches'] as List? ?? const [])) PatchEntry.fromJson((p as Map).cast<String, dynamic>()),
    ],
    comments: [
      for (final c in (j['comments'] as List? ?? const [])) ReviewComment.fromJson((c as Map).cast<String, dynamic>()),
    ],
  );
}

/// Lightweight metadata kept in the reviews index so the home screen never
/// has to load (potentially huge) patch bodies.
class ReviewSummary {
  const ReviewSummary({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.patchNames,
    required this.commentCount,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> patchNames;
  final int commentCount;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'patches': patchNames,
    'comments': commentCount,
  };

  factory ReviewSummary.fromJson(Map<String, dynamic> j) => ReviewSummary(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
    patchNames: [for (final p in (j['patches'] as List? ?? const [])) p as String],
    commentCount: j['comments'] as int? ?? 0,
  );
}

/// A, B, ..., Z, AA, AB, ... — first free name in the sequence.
String nextPatchName(Iterable<String> existing) {
  final taken = existing.toSet();
  for (var i = 0; ; i++) {
    final name = _alpha(i);
    if (!taken.contains(name)) return name;
  }
}

String _alpha(int i) {
  var n = i + 1;
  final b = StringBuffer();
  while (n > 0) {
    n--;
    b.write(String.fromCharCode(65 + n % 26));
    n ~/= 26;
  }
  return b.toString().split('').reversed.join();
}
