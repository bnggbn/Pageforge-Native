class ParagraphLocation {
  const ParagraphLocation({
    required this.section,
    required this.contentHash,
    required this.startHash,
    required this.startOccurrence,
    required this.endHash,
    required this.endOccurrence,
  });
  final int section, startOccurrence, endOccurrence;
  final String contentHash, startHash, endHash;
  String get encoded =>
      'pf:p1:$section:$contentHash:$startHash:$startOccurrence:$endHash:$endOccurrence';
  static ParagraphLocation? parse(String source) {
    final parts = source.split(':');
    if (parts.length != 8 || parts[0] != 'pf' || parts[1] != 'p1') return null;
    final section = int.tryParse(parts[2]),
        first = int.tryParse(parts[5]),
        last = int.tryParse(parts[7]);
    final hash = RegExp(r'^[a-f0-9]{64}$');
    if (section == null ||
        section < 0 ||
        first == null ||
        first < 0 ||
        last == null ||
        last < 0 ||
        !hash.hasMatch(parts[3]) ||
        !hash.hasMatch(parts[4]) ||
        !hash.hasMatch(parts[6])) {
      return null;
    }
    return ParagraphLocation(
      section: section,
      contentHash: parts[3],
      startHash: parts[4],
      startOccurrence: first,
      endHash: parts[6],
      endOccurrence: last,
    );
  }

  static String label(String source) {
    final location = parse(source);
    return location == null ? source : '段落筆記 · 第 ${location.section + 1} 節';
  }
}

class NotePassage {
  const NotePassage(this.quote, this.location);
  final String quote, location;
}
