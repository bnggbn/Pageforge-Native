import 'package:flutter/material.dart';
import '../features/design/design_document.dart';

class DesignTheme extends ThemeExtension<DesignTheme> {
  const DesignTheme(this.document);
  final DesignDocument document;
  Color color(String key) => Color(
    int.parse(
      'ff${document.get<String>('theme', key).substring(1)}',
      radix: 16,
    ),
  );
  Color get paper => color('paper');
  Color get ink => color('ink');
  Color get rust => color('accent');
  Color get forest => color('forest');
  Color get muted => color('muted');
  String get headingFont => document.get<String>('theme', 'headingFont');
  double get cardWidth => document.number('library', 'cardWidth');
  double get gap => document.number('library', 'gap');
  bool get showInvitation => document.get<bool>('library', 'showInvitation');
  int? get coverArt {
    final index = DesignDocument.motifs.indexOf(
      document.get<String>('library', 'coverArt'),
    );
    return index == 0 ? null : index - 1;
  }

  double get pageWidth => document.number('reader', 'pageWidth');
  double get lineHeight => document.number('reader', 'lineHeight');
  @override
  DesignTheme copyWith({DesignDocument? document}) =>
      DesignTheme(document ?? this.document);
  @override
  DesignTheme lerp(covariant DesignTheme? other, double t) =>
      t < .5 || other == null ? this : other;
}

extension DesignContext on BuildContext {
  DesignTheme get design =>
      Theme.of(this).extension<DesignTheme>() ??
      DesignTheme(DesignDocument.defaults);
}
