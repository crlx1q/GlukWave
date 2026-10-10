import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/ui/app.dart';
import 'app_layout_test.dart' as f;
import 'helpers/fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  for (final language in ['en', 'ru', 'kk', 'uk', 'de', 'es']) {
    testWidgets('Expanded source/season single layer320/125 $language', (
      tester,
    ) async {
      final c = await f.controller();
      c.user = WaveUser({
        'id': 'source-fixture',
        'username': 'listener',
        'plan': 'beta',
      });
      await c.customize({
        'language': language,
        'fontScale': 1.25,
        'reducedMotion': false,
        'seasonalEffects': {'enabled': true, 'mode': 'leaves'},
        'appearance': {'cover3d': false, 'backgroundBlur': false},
      });
      final track = WaveTrack({
        'id': 'source-test',
        'title':
            'An original evening recording with a deliberately long descriptive title and collaborators',
        'artist': 'Wave verification collective and a long creator name',
        'duration': 4800,
        'source': 'soundcloud',
        'playback': {
          'kind': 'audio',
          'format': 'hls',
          'offline': false,
          'attribution': {
            'source': 'soundcloud',
            'artist': 'Wave verification collective and a long creator name',
            'sourceUrl': 'https://soundcloud.com/glukwave-verification',
          },
        },
      });
      c.tracks = [track];
      c.audio.tracks = [track];
      c.audio.current = track;
      c.audio.mediaItem.add(c.audio.item(track));
      await f.viewport(tester, const Size(320, 900));
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('capture'),
          child: GlukWaveApp(controller: c),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('seasonal-atmosphere')), findsOneWidget);
      await tester.drag(
        find.byKey(const Key('mini-gesture')),
        const Offset(0, -210),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('full-player')), findsOneWidget);
      expect(find.byKey(const Key('seasonal-atmosphere')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('full-player')),
          matching: find.byKey(const Key('source-attribution')),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      if (language == 'ru') {
        await f.screenshot(tester, 'season-source-player-ru320');
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.binding.setSurfaceSize(null);
    });
  }
}
