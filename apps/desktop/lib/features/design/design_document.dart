import 'dart:convert';
import '../../data/models.dart';

/// Validated immutable design data. JSON never contains executable code.
class DesignDocument {
  DesignDocument._(this._json);
  final Json _json;
  static const _groups = ['theme', 'library', 'reader'];
  static final _color = RegExp(r'^#[0-9a-fA-F]{6}$');
  static const fonts = ['Georgia', 'Noto Serif TC', 'Microsoft JhengHei'];
  static const motifs = ['auto', 'rings', 'frames', 'waves', 'leaf', 'arch'];
  static final defaults = DesignDocument.parse(
    r'''{"schemaVersion":1,"theme":{"paper":"#f5f2e9","ink":"#343a32","accent":"#a84b36","forest":"#344a42","muted":"#858879","headingFont":"Georgia"},"library":{"showInvitation":true,"cardWidth":260,"gap":28,"coverArt":"auto"},"reader":{"pageWidth":780,"lineHeight":1.95,"paragraphGapLines":1}}''',
  );

  static DesignDocument parse(String source) {
    if (utf8.encode(source).length > 16384) {
      throw const FormatException('外觀 JSON 超過 16 KiB');
    }
    return fromJson(jsonDecode(source));
  }

  static DesignDocument fromJson(Object? value) {
    if (value is! Json) throw const FormatException('外觀必須是 JSON 物件');
    _keys(value, ['schemaVersion', 'theme', 'library', 'reader'], 'root');
    if (value['schemaVersion'] != 1) {
      throw const FormatException('不支援的 schemaVersion');
    }
    for (final group in _groups) {
      if (value[group] is! Json) throw FormatException('$group 必須是物件');
    }
    final theme = value['theme'] as Json;
    final library = value['library'] as Json;
    final reader = Map<String, dynamic>.of(value['reader'] as Json);
    _keys(theme, [
      'paper',
      'ink',
      'accent',
      'forest',
      'muted',
      'headingFont',
    ], 'theme');
    _keys(library, [
      'showInvitation',
      'cardWidth',
      'gap',
      'coverArt',
    ], 'library');
    if (!reader.containsKey('paragraphGapLines')) {
      reader['paragraphGapLines'] = 1;
    }
    _keys(reader, ['pageWidth', 'lineHeight', 'paragraphGapLines'], 'reader');
    for (final key in ['paper', 'ink', 'accent', 'forest', 'muted']) {
      if (theme[key] is! String || !_color.hasMatch(theme[key] as String)) {
        throw FormatException('theme.$key 必須為 #RRGGBB');
      }
    }
    if (!fonts.contains(theme['headingFont'])) {
      throw const FormatException('不支援的 headingFont');
    }
    if (!motifs.contains(library['coverArt'])) {
      throw const FormatException('不支援的 coverArt');
    }
    if (library['showInvitation'] is! bool) {
      throw const FormatException('library.showInvitation 必須為布林值');
    }
    _range(library['cardWidth'], 220, 340, 'library.cardWidth');
    _range(library['gap'], 12, 48, 'library.gap');
    _range(reader['pageWidth'], 480, 1000, 'reader.pageWidth');
    _range(reader['lineHeight'], 1.3, 2.4, 'reader.lineHeight');
    _range(reader['paragraphGapLines'], 0, 3, 'reader.paragraphGapLines');
    return DesignDocument._(
      Map<String, dynamic>.unmodifiable({
        'schemaVersion': 1,
        'theme': Map<String, dynamic>.unmodifiable(theme),
        'library': Map<String, dynamic>.unmodifiable(library),
        'reader': Map<String, dynamic>.unmodifiable(reader),
      }),
    );
  }

  static void _keys(Json value, List<String> keys, String path) {
    if (value.length != keys.length || !keys.every(value.containsKey)) {
      throw FormatException('$path 欄位缺少或包含未知欄位');
    }
  }

  static void _range(dynamic value, double min, double max, String path) {
    if (value is! num || !value.isFinite || value < min || value > max) {
      throw FormatException('$path 必須在 $min–$max');
    }
  }

  T get<T>(String group, String key) => _json[group][key] as T;
  double number(String group, String key) => (get<num>(group, key)).toDouble();
  Json toJson() => {
    ..._json,
    for (final group in _groups)
      group: Map<String, dynamic>.of(_json[group] as Json),
  };
  late final String source = const JsonEncoder.withIndent('  ').convert(_json);

  DesignDocument change(String group, String key, Object value) =>
      changeValues(group, {key: value});

  DesignDocument changeValues(String group, Map<String, Object> values) {
    final next = toJson();
    (next[group] as Json).addAll(values);
    return fromJson(next);
  }
}
