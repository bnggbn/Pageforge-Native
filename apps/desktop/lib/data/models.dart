typedef Json = Map<String, dynamic>;

class BookSummary {
  BookSummary(Json json)
    : id = json['id'] as String,
      title = json['title'] as String,
      filename = json['filename'] as String,
      format = json['format'] as String,
      versions = json['revisionCount'] as int,
      progress = (json['progress'] as num).toDouble();
  final String id, title, filename, format;
  final int versions;
  final double progress;
  String get label => format == 'markdown'
      ? 'MD'
      : format == 'text'
      ? 'TXT'
      : format.toUpperCase();
}

class RevisionSummary {
  RevisionSummary(Json json)
    : id = json['id'] as String,
      kind = json['kind'] as String,
      createdAt = DateTime.parse(json['createdAt'] as String);
  final String id, kind;
  final DateTime createdAt;
}

class Revision extends RevisionSummary {
  Revision(super.json)
    : content = json['content'] as String,
      notes = List<Json>.unmodifiable((json['notes'] as List).cast<Json>());
  final String content;
  final List<Json> notes;
}

class Book {
  Book(Json json)
    : id = json['id'] as String,
      title = json['title'] as String,
      format = json['format'] as String,
      originalPath = json['originalPath'] as String,
      sections = List<Json>.unmodifiable(
        (json['sections'] as List).cast<Json>(),
      ),
      sheets = List<Json>.unmodifiable((json['sheets'] as List).cast<Json>()),
      revisions = List<Revision>.unmodifiable(
        (json['revisions'] as List).map((item) => Revision(item as Json)),
      ),
      history = List<RevisionSummary>.unmodifiable(
        ((json['history'] ?? json['revisions']) as List).map(
          (item) => RevisionSummary(item as Json),
        ),
      ),
      revisionCount =
          json['revisionCount'] as int? ?? (json['revisions'] as List).length,
      progress = json['progress'] as Json?;
  final String id, title, format, originalPath;
  final List<Json> sections, sheets;
  final List<Revision> revisions;
  final List<RevisionSummary> history;
  final int revisionCount;
  final Json? progress;
  Revision get head => revisions.last;
  bool get editable => format == 'markdown' || format == 'text';
}
