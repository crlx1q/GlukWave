import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/ui/album_stage.dart';
import 'package:glukwave/ui/player.dart';
import 'audio_design_test.dart' as audio;
import 'app_layout_test.dart' as base;
import 'helpers/fonts.dart';
import 'helpers/cover22_evaluator_artwork_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
  });
  setUp(installArtworkFixture);
  tearDown(clearArtworkFixture);
  testWidgets(
    'Sleeve reverse fits real long metadata, omits duplicate album and unknown duration',
    (t) async {
      final c = (await t.runAsync(audio.makeController))!;
      await base.viewport(t, const Size(375, 812));
      final titles = [
        '1 A.M Study Session 📚 - [lofi hip hop/chill beats]',
        'Пока город спит — музыка для тихого зимнего вечера',
        '夜の街と静かな音楽 — 雨の日に聴く長いコレクション',
        '🌙🎧📚 Музыка, которая остаётся рядом с тобой',
        List.filled(200, 'W').join(),
      ];
      for (final size in [155.0, 202.0, 302.0]) {
        for (var index = 0; index < titles.length; index++) {
          final track = WaveTrack({
            'id': 'reverse-$index',
            'title': titles[index],
            'artist': 'Lofi Girl',
            'album': index == 0
                ? titles[index]
                : index == 1
                ? ''
                : 'Quiet moments',
            'source': 'soundcloud',
            'duration': index == 1 ? 0 : 3673,
          });
          await t.pumpWidget(
            audio.shell(
              c,
              Center(
                child: Container(
                  key: const Key('paper'),
                  width: size,
                  height: size,
                  padding: EdgeInsets.fromLTRB(
                    size * .086,
                    size * .093,
                    size * .086,
                    size * .07,
                  ),
                  color: const Color(0xff32312d),
                  child: SleeveBackMetadata(track: track, size: size),
                ),
              ),
              scale: 1.25,
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.text(titles[index]), findsOneWidget);
          expect(find.textContaining('01 —'), findsNothing);
          expect(find.textContaining('studio sessions'), findsNothing);
          expect(
            find.byKey(const Key('album-back-album')),
            index < 2 ? findsNothing : findsOneWidget,
          );
          expect(
            find.byKey(const Key('album-back-duration')),
            index == 1 ? findsNothing : findsOneWidget,
          );
          expect(find.text('SoundCloud'), findsOneWidget);
          final paper = t.getRect(find.byKey(const Key('paper')));
          for (final key in [
            'album-back-title',
            'album-back-artist',
            'album-back-source',
            if (index >= 2) 'album-back-album',
            if (index != 1) 'album-back-duration',
          ]) {
            final rect = t.getRect(find.byKey(Key(key)));
            expect(rect.left, greaterThanOrEqualTo(paper.left));
            expect(rect.right, lessThanOrEqualTo(paper.right));
            expect(rect.top, greaterThanOrEqualTo(paper.top));
            expect(rect.bottom, lessThanOrEqualTo(paper.bottom));
          }
          final paragraph = t.renderObject<RenderParagraph>(
            find.byKey(const Key('album-back-title')),
          );
          expect(paragraph.didExceedMaxLines, index == 4);
          if (index == 0 && size >= 202) {
            await base.screenshot(t, 'cover22-evaluator-back-${size.toInt()}');
          }
        }
      }
      await base.clean(t, c);
      clearArtworkFixture();
    },
  );
  for (final viewport in [
    const Size(1440, 900),
    const Size(1280, 650),
    const Size(375, 812),
    const Size(320, 568),
    const Size(812, 375),
  ]) {
    testWidgets(
      'Vertical sleeve above transport retains dimensions and reachable controls $viewport',
      (t) async {
        final c = (await t.runAsync(audio.makeController))!;
        c.settings['lyricsUnderCover'] = false;
        final realTrack = WaveTrack({'id':'cover22-evaluator','title':'1 A.M Study Session 📚 - [lofi hip hop/chill beats]','artist':'Lofi Girl','album':'1 A.M Study Session 📚 - [lofi hip hop/chill beats]','source':'soundcloud','duration':3673,'artwork':'https://qa.invalid/forest.jpg'});
        c.tracks=[realTrack]; c.audio.tracks=[realTrack]; c.audio.current=realTrack;
        await base.viewport(t, viewport);
        await t.pumpWidget(
          audio.shell(
            c,
            PlayerPage(controller: c, onMore: (_) {}),
            mode: viewport.width==375?'light':'dark',
            scale: 1.25,
          ),
        );
        await t.pumpAndSettle();
        final realImage = find.descendant(of: find.byKey(const Key('album-front-sleeve')), matching: find.byType(RawImage));
        for(var i=0; i<15; i++) {
          if(realImage.evaluate().isNotEmpty && t.widget<RawImage>(realImage.first).image!=null) break;
          await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:150)));
          await t.pump(const Duration(milliseconds:200));
        }
        expect(t.widget<RawImage>(realImage.first).image,isNotNull);
        final cover = t.getRect(find.byKey(const Key('player-cover-gesture')));
        final transport = t.getRect(
          find.byKey(const Key('player-transport-capsule')),
        );
        expect(cover.bottom, lessThan(transport.top));
        expect(cover.center.dx, closeTo(transport.center.dx, 1));
        final stage = t.widget<AlbumStage>(find.byType(AlbumStage));
        if (viewport.width >= 1100) expect(stage.size, 302);
        final original = t.getSize(find.byKey(const Key('album-stage-bounds')));
        if (viewport.height >= 568) {
          final transform = t
              .widget<Transform>(find.byKey(const Key('album-3d-transform')))
              .transform;
          final side = stage.size;
          for (final point in [
            Offset(-side / 2, -side / 2),
            Offset(side / 2, side / 2),
          ]) {
            final projected = MatrixUtils.transformPoint(transform, point);
            expect(projected.distance, lessThan(side * 1.1));
          }
        }
        await base.screenshot(
          t,
          'cover22-evaluator-${viewport.width.toInt()}-${viewport.height.toInt()}-vertical',
        );
        final gesture = t.widget<GestureDetector>(find.byKey(const Key('album-3d')));
        gesture.onLongPressStart!(const LongPressStartDetails());
        gesture.onLongPressMoveUpdate!(const LongPressMoveUpdateDetails(offsetFromOrigin:Offset(180/.65,0)));
        await t.pump();
        expect(t.getSize(find.byKey(const Key('album-stage-bounds'))),original);
        await base.screenshot(t,'cover22-evaluator-${viewport.width.toInt()}-${viewport.height.toInt()}-back');
        gesture.onLongPressStart!(const LongPressStartDetails());
        gesture.onLongPressMoveUpdate!(const LongPressMoveUpdateDetails(offsetFromOrigin:Offset(540/.65,-170)));
        await t.pump();
        expect(t.getSize(find.byKey(const Key('album-stage-bounds'))),original);
        await base.screenshot(t,'cover22-evaluator-${viewport.width.toInt()}-${viewport.height.toInt()}-extreme');
        await t.ensureVisible(find.byKey(const Key('player-equalizer')));
        await t.pumpAndSettle();
        final control = t.getRect(find.byKey(const Key('player-equalizer')));
        expect(control.top, greaterThanOrEqualTo(0));
        expect(control.bottom, lessThanOrEqualTo(viewport.height));
        expect(
          t.getSize(find.byKey(const Key('album-stage-bounds'))),
          original,
        );
        await t.tap(find.byKey(const Key('player-equalizer')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('player-eq-popover')), findsOneWidget);
        expect(t.takeException(), isNull);
        await base.clean(t, c);
      clearArtworkFixture();
      },
    );
  }
}



