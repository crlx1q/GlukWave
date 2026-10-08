import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/fonts.dart';

Map<String, int> fontTables(ByteData bytes) {
  final result = <String, int>{};
  for (var i = 0; i < bytes.getUint16(4); i++) {
    final at = 12 + i * 16;
    final tag = String.fromCharCodes([
      for (var n = 0; n < 4; n++) bytes.getUint8(at + n),
    ]);
    result[tag] = bytes.getUint32(at + 8);
  }
  return result;
}

Future<int> inkCoverage(FontWeight weight, {String family = 'Nunito'}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final text = TextPainter(
    text: TextSpan(
      text: 'GlukWave Music',
      style: TextStyle(
        fontFamily: family,
        fontWeight: weight,
        fontSize: 40,
        color: const ui.Color(0xff000000),
      ),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  text.paint(canvas, ui.Offset.zero);
  final picture = recorder.endRecording();
  final image = await picture.toImage(400, 70);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  var alpha = 0;
  for (var i = 3; i < bytes.lengthInBytes; i += 4) {
    alpha += bytes.getUint8(i);
  }
  text.dispose();
  picture.dispose();
  image.dispose();
  return alpha;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);
  test(
    'App font manifest maps six genuine static faces with matching metadata',
    () async {
      final manifest =
          jsonDecode(await rootBundle.loadString('FontManifest.json'))
              as List<dynamic>;
      for (final entry in {
        'Manrope': [400, 500, 600, 700, 800],
        'Nunito': [400, 500, 600, 700, 800, 900],
      }.entries) {
        final family = manifest.cast<Map<String, dynamic>>().singleWhere(
          (item) => item['family'] == entry.key,
        );
        final faces = family['fonts'] as List<dynamic>;
        expect(faces.map((f) => f['weight']), entry.value);
        expect(
          faces.map((f) => f['asset']).toSet(),
          hasLength(entry.value.length),
        );
        for (final face in faces) {
          final bytes = await rootBundle.load(face['asset'] as String);
          final tables = fontTables(bytes);
          expect(tables.containsKey('fvar'), isFalse);
          expect(tables.containsKey('gvar'), isFalse);
          expect(bytes.getUint16(tables['OS/2']! + 4), face['weight']);
        }
      }
    },
  );
  test(
    'Actual registered rounded bold outlines render heavier than normal',
    () async {
      final normal = await inkCoverage(FontWeight.w400);
      final bold = await inkCoverage(FontWeight.w800);
      expect(normal, greaterThan(0));
      expect(bold, greaterThan(normal * 1.35));
    },
  );
  test(
    'Manrope default registers genuine regular and extra-bold outlines',
    () async {
      final normal = await inkCoverage(FontWeight.w400, family: 'Manrope');
      final bold = await inkCoverage(FontWeight.w800, family: 'Manrope');
      expect(normal, greaterThan(0));
      expect(bold, greaterThan(normal * 1.12));
    },
  );
}
