import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/ui/volume_slider.dart';
import 'package:glukwave/l10n/wave_localizations.dart';

void main() {
  test(
    'automatic Kazakh resolves Russian; explicitly selected Kazakh is retained',
    () {
      expect(automaticLanguage('kk-KZ'), 'ru');
      expect(supportedLanguage('kk-KZ'), 'kk');
      expect(automaticLanguage('de'), 'de');
    },
  );
  testWidgets(
    'volume wheel and keyboard move two percent, drafts commit once after quiet time',
    (tester) async {
      final previews = <double>[], commits = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: VolumeSlider(
                  value: 0,
                  onPreview: previews.add,
                  onChanged: commits.add,
                ),
              ),
            ),
          ),
        ),
      );
      final point = tester.getCenter(find.byType(Slider));
      for (var i = 0; i < 5; i++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: point,
            scrollDelta: const Offset(0, -120),
          ),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(previews, [.02, .04, .06, .08, .1]);
      expect(commits, isEmpty);
      await tester.pump(const Duration(milliseconds: 300));
      expect(commits, [.1]);
      expect(tester.widget<Slider>(find.byType(Slider)).divisions, 50);
    },
  );
}
