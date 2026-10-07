import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pageforge/data/models.dart';
import 'package:pageforge/features/design/design_document.dart';

void main() {
  test('Flutter owns required fields, UI enums and visual bounds', () {
    final invalid = <String, void Function(Json)>{
      'version': (d) => d['schemaVersion'] = 2,
      'unknown field': (d) => d['script'] = 'execute()',
      'color': (d) => d['theme']['paper'] = 'url(file:///secret)',
      'font': (d) => d['theme']['headingFont'] = 'unknown',
      'motif': (d) => d['library']['coverArt'] = 'unknown',
      'missing boolean': (d) => (d['library'] as Json).remove('showInvitation'),
      'null boolean': (d) => d['library']['showInvitation'] = null,
      'wrong boolean': (d) => d['library']['showInvitation'] = 1,
      'card width': (d) => d['library']['cardWidth'] = 999,
      'gap': (d) => d['library']['gap'] = 0,
      'page width': (d) => d['reader']['pageWidth'] = 999999,
      'line height': (d) => d['reader']['lineHeight'] = 0,
      'null paragraph gap': (d) => d['reader']['paragraphGapLines'] = null,
      'negative paragraph gap': (d) => d['reader']['paragraphGapLines'] = -1,
      'large paragraph gap': (d) => d['reader']['paragraphGapLines'] = 4,
      'wrong paragraph gap type': (d) =>
          d['reader']['paragraphGapLines'] = 'large',
      'unknown nested field': (d) => d['theme']['future'] = true,
    };
    for (final entry in invalid.entries) {
      final value = DesignDocument.defaults.toJson();
      entry.value(value);
      expect(
        () => DesignDocument.parse(jsonEncode(value)),
        throwsFormatException,
        reason: entry.key,
      );
    }
  });

  test(
    'old files default paragraph spacing locally without rewriting their source',
    () {
      final old = DesignDocument.defaults.toJson();
      (old['reader'] as Json).remove('paragraphGapLines');
      final source = jsonEncode(old);
      final parsed = DesignDocument.parse(source);
      expect(parsed.number('reader', 'paragraphGapLines'), 1);
      expect(
        (jsonDecode(source)['reader'] as Json).containsKey('paragraphGapLines'),
        false,
      );
      expect(parsed.toJson()['reader']['paragraphGapLines'], 1);
    },
  );

  test('syntax, non-object roots and encoded byte limits are client rules', () {
    for (final source in ['{', 'null', '[]', '{} {}', ' ' * 16385]) {
      expect(() => DesignDocument.parse(source), throwsFormatException);
    }
    expect(() => DesignDocument.parse('中' * 6000), throwsFormatException);
    final valid = DesignDocument.defaults.toJson();
    valid['library']['showInvitation'] = false;
    valid['reader']['paragraphGapLines'] = 0;
    final parsed = DesignDocument.parse(jsonEncode(valid));
    expect(parsed.get<bool>('library', 'showInvitation'), false);
    expect(parsed.number('reader', 'paragraphGapLines'), 0);
  });
}
