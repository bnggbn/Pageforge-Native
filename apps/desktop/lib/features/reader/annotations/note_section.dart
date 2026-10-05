import '../../../data/models.dart';
import 'paragraph_index.dart';
import 'paragraph_location.dart';

/// Resolve chapter identity before matching paragraphs, including old Web notes.
/// Ambiguous notes stay available on the wall without being attached to a chapter.
class NoteSectionIndex {
  NoteSectionIndex(this.sections);
  final List<Json> sections;
  // Normalize at most once per chapter, only when a legacy quote needs fallback.
  final _text = <int, String>{};
  int? resolve(Json note) {
    final location = note['location'] as String? ?? '';
    final anchor = ParagraphLocation.parse(location);
    if (anchor != null) {
      return anchor.section < sections.length ? anchor.section : null;
    }
    final titled = <int>[];
    for (var i = 0; i < sections.length; i++) {
      final title = sections[i]['title'] as String? ?? '';
      if (title.isNotEmpty && location.startsWith('$title / ')) titled.add(i);
    }
    if (titled.length == 1) return titled.single;
    final quote = ParagraphIndex.normalize(note['quote'] as String? ?? '');
    if (quote.isEmpty) return null;
    final candidates = titled.isEmpty
        ? List<int>.generate(sections.length, (i) => i)
        : titled;
    int? match;
    for (final i in candidates) {
      final text = _text.putIfAbsent(
        i,
        () => ParagraphIndex.normalize(sections[i]['text'] as String? ?? ''),
      );
      if (!text.contains(quote)) continue;
      if (match != null) return null;
      match = i;
    }
    return match;
  }
}

int? noteSection(Json note, List<Json> sections) =>
    NoteSectionIndex(sections).resolve(note);
