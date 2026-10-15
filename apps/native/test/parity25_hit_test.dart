import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/album_stage.dart';
import 'audio_design_test.dart' as a;
import 'app_layout_test.dart' as f;
import 'helpers/fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
  });
  for (final size in [const Size(638, 716), const Size(1440, 900)]) {
    for (final threeD in [false, true]) {
      testWidgets(
        'Actual seek and empty envelope scroll work at $size cover3d=$threeD',
        (t) async {
          final c = (await t.runAsync(a.makeController))!;
          await t.runAsync(
            () => c.customize({
              'appearance': {'cover3d': threeD, 'coverKind': 'cd'},
            }),
          );
          c.settings['lyricsUnderCover'] = false;
          c.waveActive = true;
          c.waveMode = 'favorites';
          c.waveMood = 'calm';
          await f.viewport(t, size);
          await t.pumpWidget(
            a.shell(c, PlayerPage(controller: c, onMore: (_) {}), scale: 1),
          );
          await t.pump();
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 80)),
          );
          await t.pumpAndSettle();
          final label = t
              .widget<Text>(find.byKey(const Key('player-context-label')))
              .data!;
          expect(label, contains('Favorites'));
          expect(label, contains('Calm'));
          final slider = find.byKey(const Key('player-seek'));
          await t.ensureVisible(slider);
          await t.pumpAndSettle();
          final before = t.widget<Slider>(slider).value,
              rect = t.getRect(slider);
          final dynamic cover = t.state(find.byType(AlbumStage));
          final tilt = cover.tilt;
          final gesture = await t.startGesture(
            Offset(rect.left + rect.width * .2, rect.center.dy),
          );
          await gesture.moveTo(
            Offset(rect.left + rect.width * .8, rect.center.dy),
          );
          await t.pump();
          expect(t.widget<Slider>(slider).value, greaterThan(before + 1000));
          expect(cover.tilt, tilt);
          await gesture.up();
          await t.pumpAndSettle();
          if (size.width < 1000) {
            final scrollFinder = find
                .descendant(
                  of: find.byKey(const Key('player-content-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first;
            final scroll = t.state<ScrollableState>(scrollFinder).position;
            expect(scroll.maxScrollExtent, greaterThan(10));
            scroll.jumpTo(20);
            await t.pump();
            final stage = t.getRect(
              find.byKey(const Key('album-stage-bounds')),
            );
            final point = Offset(
              stage.left + 7,
              (stage.top + 28).clamp(100.0, size.height - 120),
            );
            final beforeScroll = scroll.pixels;
            await t.dragFrom(point, const Offset(0, 80));
            await t.pumpAndSettle();
            expect(scroll.pixels, lessThan(beforeScroll));
            expect(cover.tilt, tilt);
          }
          expect(t.takeException(), isNull);
          await f.clean(t, c);
        },
      );
    }
  }
}
