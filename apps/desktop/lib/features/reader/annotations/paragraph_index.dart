import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/rendering.dart';
import 'paragraph_location.dart';

class ParagraphEntry {
  const ParagraphEntry(
    this.text,
    this.hash,
    this.occurrence,
    this.bounds, {
    Offset? endPoint,
  }) : _endPoint = endPoint;
  final String text, hash;
  final int occurrence;
  final Rect bounds;
  final Offset? _endPoint;
  Offset get endPoint => _endPoint ?? bounds.bottomRight;
}

/// Index existing rendered text; never split Markdown into isolated selection areas.
class ParagraphIndex {
  ParagraphIndex(this.content, this.section)
    : contentHash = sha256.convert(utf8.encode(content)).toString();
  final String content, contentHash;
  final int section;
  List<ParagraphEntry> _entries = [];
  final _byHash = <String, List<ParagraphEntry>>{};
  final _positions = <ParagraphEntry, int>{};
  final _text = <ParagraphEntry, String>{};
  List<ParagraphEntry> get entries => _entries;
  set entries(List<ParagraphEntry> value) {
    _entries = List.unmodifiable(value);
    _byHash.clear();
    _positions.clear();
    _text.clear();
    for (var i = 0; i < value.length; i++) {
      final entry = value[i];
      _byHash.putIfAbsent(entry.hash, () => []).add(entry);
      _positions[entry] = i;
      _text[entry] = normalize(entry.text);
    }
  }

  final _hashes = <String, String>{};
  static String normalize(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();
  void measure(
    RenderBox root,
    RenderObject article, {
    required bool plainText,
  }) {
    final paragraphs = <RenderParagraph>[];
    void visit(RenderObject node) {
      if (node is RenderParagraph) paragraphs.add(node);
      node.visitChildren(visit);
    }

    visit(article);
    final result = <ParagraphEntry>[], counts = <String, int>{};
    for (final paragraph in paragraphs) {
      final text = paragraph.text.toPlainText();
      final ranges = <TextRange>[];
      if (plainText) {
        var start = 0;
        for (final match in RegExp(r'\r?\n[ \t]*\r?\n').allMatches(text)) {
          if (match.start > start) {
            ranges.add(TextRange(start: start, end: match.start));
          }
          start = match.end;
        }
        if (start < text.length) {
          ranges.add(TextRange(start: start, end: text.length));
        }
      } else {
        ranges.add(TextRange(start: 0, end: text.length));
      }
      for (final range in ranges) {
        final value = text.substring(range.start, range.end),
            normalized = normalize(value);
        if (normalized.isEmpty) continue;
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: range.start, extentOffset: range.end),
        );
        if (boxes.isEmpty) continue;
        Rect? bounds;
        for (final box in boxes) {
          final local = box.toRect();
          final converted = Rect.fromPoints(
            root.globalToLocal(paragraph.localToGlobal(local.topLeft)),
            root.globalToLocal(paragraph.localToGlobal(local.bottomRight)),
          );
          bounds = bounds == null
              ? converted
              : bounds.expandToInclude(converted);
        }
        final hash = _hashes.putIfAbsent(
          normalized,
          () => sha256.convert(utf8.encode(normalized)).toString(),
        );
        final occurrence = counts[hash] ?? 0;
        counts[hash] = occurrence + 1;
        var end = range.end;
        while (end > range.start &&
            text.substring(end - 1, end).trim().isEmpty) {
          end--;
        }
        var lastStart = end - 1;
        if (lastStart > range.start &&
            text.codeUnitAt(lastStart) >= 0xdc00 &&
            text.codeUnitAt(lastStart) <= 0xdfff) {
          lastStart--;
        }
        final lastBoxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: lastStart, extentOffset: end),
        );
        final lastBox = lastBoxes.isEmpty ? boxes.last : lastBoxes.last;
        final caret = paragraph.getOffsetForCaret(
          TextPosition(offset: end),
          Rect.zero,
        );
        final endPoint = root.globalToLocal(
          paragraph.localToGlobal(
            Offset(caret.dx, (lastBox.top + lastBox.bottom) / 2),
          ),
        );
        result.add(
          ParagraphEntry(value, hash, occurrence, bounds!, endPoint: endPoint),
        );
      }
    }
    entries = result;
  }

  ParagraphEntry? at(Offset point) {
    for (final entry in entries) {
      if (entry.bounds.inflate(2).contains(point)) return entry;
    }
    return null;
  }

  NotePassage passage(
    String quote,
    ParagraphEntry first,
    ParagraphEntry last,
  ) => NotePassage(
    quote,
    ParagraphLocation(
      section: section,
      contentHash: contentHash,
      startHash: first.hash,
      startOccurrence: first.occurrence,
      endHash: last.hash,
      endOccurrence: last.occurrence,
    ).encoded,
  );
  List<ParagraphEntry> resolve(String location, String quote) {
    final anchor = ParagraphLocation.parse(location);
    if (anchor == null) return _legacy(quote);
    if (anchor.section != section) return [];
    ParagraphEntry? find(String hash, int occurrence) {
      final candidates = _byHash[hash] ?? <ParagraphEntry>[];
      if (anchor.contentHash != contentHash) {
        return candidates.length == 1 ? candidates.single : null;
      }
      for (final entry in candidates) {
        if (entry.occurrence == occurrence) return entry;
      }
      return null;
    }

    final first = find(anchor.startHash, anchor.startOccurrence),
        last = find(anchor.endHash, anchor.endOccurrence);
    if (first == null || last == null) return [];
    final start = _positions[first]!, end = _positions[last]!;
    return end >= start ? entries.sublist(start, end + 1) : [];
  }

  List<ParagraphEntry> _legacy(String quote) {
    if (quote.trim().isEmpty) return [];
    final whole = normalize(quote);
    final candidates = entries
        .where((entry) => _text[entry]!.contains(whole))
        .toList();
    if (candidates.length == 1) return candidates;
    final fragments = quote
        .split('\n')
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (fragments.length < 2) return [];
    final first = entries
        .where(
          (entry) => normalize(entry.text).contains(normalize(fragments.first)),
        )
        .toList();
    final last = entries
        .where(
          (entry) => normalize(entry.text).contains(normalize(fragments.last)),
        )
        .toList();
    if (first.length != 1 || last.length != 1) return [];
    final a = entries.indexOf(first.single), b = entries.indexOf(last.single);
    return b >= a ? entries.sublist(a, b + 1) : [];
  }
}
