import 'package:flutter/material.dart';

ThemeData buildGlukWaveTheme() {
  const seed = Color(0xFF6C4DFF);

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorSchemeSeed: seed,
    scaffoldBackgroundColor: const Color(0xFF090A16),
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(centerTitle: false),
    cardTheme: const CardThemeData(
      color: Color(0xFF16172A),
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
  );
}
