/// Immutable edit values over fixed source ranges. A keystroke copies only the
/// changed section and its small replacement map; joining waits for persistence.
class SectionedDraft {
  SectionedDraft(String source, {int sectionUnits = 16000})
    : this._(source, _ranges(source, sectionUnits), const {});

  SectionedDraft._(this.source, this.ranges, this.replacements);
  final String source;
  final List<(int, int)> ranges;
  final Map<int, String> replacements;
  String? _materialized;
  int get length => ranges.length;

  String section(int index) =>
      replacements[index] ??
      source.substring(ranges[index].$1, ranges[index].$2);

  SectionedDraft replace(int index, String value) {
    if (section(index) == value) return this;
    final next = {...replacements};
    final range = ranges[index];
    if (value == source.substring(range.$1, range.$2)) {
      next.remove(index);
    } else {
      next[index] = value;
    }
    return SectionedDraft._(source, ranges, Map.unmodifiable(next));
  }

  bool matches(String value) => identical(source, value) || source == value
      ? replacements.isEmpty
      : text == value;

  String get text => _materialized ??= replacements.isEmpty
      ? source
      : [for (var i = 0; i < length; i++) section(i)].join();

  // Prefer whole paragraphs/lines. Very long lines need an explicit edit range;
  // retain their exact characters, including CRLF and surrogate pairs.
  static List<(int, int)> _ranges(String source, int units) {
    if (units < 2) throw ArgumentError.value(units, 'sectionUnits');
    final result = <(int, int)>[];
    var start = 0;
    while (source.length - start > units) {
      var end = start + units;
      final paragraph = source.lastIndexOf('\n\n', end - 2);
      final line = source.lastIndexOf('\n', end - 1);
      if (paragraph >= start + units ~/ 2) {
        end = paragraph + 2;
      } else if (line >= start + units ~/ 2) {
        end = line + 1;
      } else {
        final before = source.codeUnitAt(end - 1);
        final after = source.codeUnitAt(end);
        if ((before >= 0xd800 &&
                before <= 0xdbff &&
                after >= 0xdc00 &&
                after <= 0xdfff) ||
            (before == 13 && after == 10)) {
          end--;
        }
      }
      result.add((start, end));
      start = end;
    }
    result.add((start, source.length));
    return List.unmodifiable(result);
  }
}
