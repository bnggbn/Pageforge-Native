import 'package:flutter/material.dart';
import '../features/design/design_document.dart';
import 'design_theme.dart';

const editorialFace = 'Georgia';
const editorialFallback = ['Noto Serif TC', 'Microsoft JhengHei'];

const paper = Color(0xfff5f2e9);
const ink = Color(0xff343a32);
const rust = Color(0xffa84b36);
const muted = Color(0xff858879);
const forest = Color(0xff344a42);

ThemeData pageforgeTheme([DesignDocument? document]) {
  final design = DesignTheme(document ?? DesignDocument.defaults);
  final paper = design.paper, ink = design.ink, rust = design.rust;
  return ThemeData(
    extensions: [design],
    useMaterial3: true,
    scaffoldBackgroundColor: paper,
    colorScheme: ColorScheme.fromSeed(seedColor: rust, surface: paper),
    fontFamily: 'Microsoft JhengHei',
    textTheme: TextTheme(
      displaySmall: TextStyle(
        fontFamily: design.headingFont,
        fontFamilyFallback: editorialFallback,
        color: ink,
        fontSize: 40,
        letterSpacing: -1.5,
      ),
      headlineSmall: TextStyle(
        color: ink,
        fontSize: 24,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: TextStyle(color: ink, height: 1.8),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: rust,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 19),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
    dividerColor: const Color(0xffdadbce),
  );
}
