import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/ui/widgets.dart';
import 'package:glukwave/l10n/wave_localizations.dart';
import 'helpers/fonts.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
  });
  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    testWidgets('Warm reference layout fits width $width with reduced motion', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 850);
      await tester.binding.setSurfaceSize(Size(width, 850));
      WaveStrings.current = const WaveStrings('ru');
      await tester.pumpWidget(
        MaterialApp(
          theme: waveTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Brand(),
                  const SizedBox(height: 24),
                  const PageHeading(
                    'Добрый вечер, друг',
                    'Пусть сегодня звучит что-то твоё.',
                  ),
                  WaveHero(empty: true, reducedMotion: true, onPlay: () {}),
                  const EmptyState(
                    'Твой музыкальный мир ждёт',
                    'Добавь свои аудиофайлы или подключи библиотеку.',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Моя волна'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }
}
