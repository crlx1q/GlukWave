import 'dart:convert';
import 'package:flutter/services.dart';

/// Use the application's exact registered faces, including real weight metadata.
/// A single variable ExtraLight file does not reproduce the app's full family.
Future<void> loadAppFonts() async {
  final manifest =
      jsonDecode(await rootBundle.loadString('FontManifest.json'))
          as List<dynamic>;
  for (final family in manifest.cast<Map<String, dynamic>>().where(
    (entry) => ['Nunito', 'Manrope'].contains(entry['family']),
  )) {
    final loader = FontLoader(family['family'] as String);
    for (final face in family['fonts'] as List<dynamic>) {
      loader.addFont(rootBundle.load(face['asset'] as String));
    }
    await loader.load();
  }
}
