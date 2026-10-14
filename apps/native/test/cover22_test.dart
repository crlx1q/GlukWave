import 'dart:math' as math;
import 'package:flutter/gestures.dart';
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
import 'helpers/artwork_fixture.dart';
import 'package:glukwave/ui/scrolling_label.dart';

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
            await base.screenshot(t, 'cover22-back-${size.toInt()}');
          }
        }
      }
      await base.clean(t, c);
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
        await base.viewport(t, viewport);
        await t.pumpWidget(
          audio.shell(
            c,
            PlayerPage(controller: c, onMore: (_) {}),
            scale: 1.25,
          ),
        );
        await t.pumpAndSettle();
        if (viewport.height >= 900) {
          final play = t.getRect(find.byKey(const Key('player-play')));
          expect(play.top, greaterThanOrEqualTo(0));
          expect(
            play.bottom,
            lessThanOrEqualTo(viewport.height),
            reason:
                'The primary playback control must be visible without scrolling on a normal desktop.',
          );
        }
        final cover = t.getRect(find.byKey(const Key('player-cover-gesture')));
        final transport = t.getRect(
          find.byKey(const Key('player-transport-capsule')),
        );
        if (find.byKey(const Key('player-wide-layout')).evaluate().isNotEmpty) {
          expect(cover.right, lessThan(transport.left));
        } else {
          expect(cover.bottom, lessThan(transport.top));
          expect(cover.center.dx, closeTo(transport.center.dx, 1));
        }
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
          'cover22-${viewport.width.toInt()}-${viewport.height.toInt()}-vertical',
        );
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
      },
    );
  }
  testWidgets(
    'Full turn painted circle and paper corners stay within scene and clear heading',
    (t) async {
      await installArtworkFixture();
      final c = (await t.runAsync(audio.makeController))!;
      const title = '1 A.M Study Session 📚 - [lofi hip hop/chill beats]';
      final track = WaveTrack({
        'id': 'true-corners',
        'title': title,
        'artist': 'Lofi Girl',
        'album': title,
        'source': 'soundcloud',
        'duration': 3673,
        'artwork': 'https://qa.invalid/forest.jpg',
      });
      c.tracks = [track];
      c.audio.tracks = [track];
      c.audio.current = track;
      c.settings['lyricsUnderCover'] = false;
      await base.viewport(t, const Size(1440, 900));
      await t.pumpWidget(
        audio.shell(c, PlayerPage(controller: c, onMore: (_) {}), scale: 1),
      );
      await t.pumpAndSettle();
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: t.getCenter(find.byKey(const Key('album-3d'))),
      );
      await t.pump(const Duration(milliseconds: 700));
      var currentX = -9.0, currentY = -18.0;
      final original = t.getSize(find.byKey(const Key('album-stage-bounds')));
      for (final pose in [
        const Offset(-38, -85),
        const Offset(-38, -90),
        const Offset(-38, -122),
        const Offset(38, -85),
        const Offset(38, 92),
        const Offset(-38, 92),
      ]) {
        final gesture = t.widget<GestureDetector>(
          find.byKey(const Key('album-3d')),
        );
        gesture.onLongPressStart!(const LongPressStartDetails());
        gesture.onLongPressMoveUpdate!(
          LongPressMoveUpdateDetails(
            offsetFromOrigin: Offset(
              (pose.dy - currentY) / .65,
              (currentX - pose.dx) / .22,
            ),
          ),
        );
        await t.pump();
        currentX = pose.dx;
        currentY = pose.dy;
        final matrix = t
            .widget<Transform>(find.byKey(const Key('album-3d-transform')))
            .transform;
        final bounds = t.getRect(find.byKey(const Key('album-stage-bounds'))),
            center = bounds.center;
        final side = t.widget<AlbumStage>(find.byType(AlbumStage)).size;
        final left = t
            .widget<AnimatedPositioned>(
              find.byKey(const Key('album-record-position')),
            )
            .left!;
        final heading = t.getRect(
          find.byWidgetPredicate((w) => w is ScrollingLabel && w.text == title),
        );
        for (var index = 0; index < 1024; index++) {
          final angle = index * math.pi * 2 / 1024;
          final point =
              center +
              MatrixUtils.transformPoint(
                matrix,
                Offset(
                  left + side * .47 - side / 2 + side * .47 * math.cos(angle),
                  side * .47 * math.sin(angle),
                ),
              );
          expect(point.dy, greaterThanOrEqualTo(bounds.top + 4));
          expect(point.dy, lessThanOrEqualTo(bounds.bottom - 4));
          expect(
            heading.inflate(4).contains(point),
            isFalse,
            reason:
                'The projected record stays clear of metadata in either adaptive layout.',
          );
        }
        for (final z in [-9.0, 9.0]) {
          final face = Matrix4.copy(matrix)..translateByDouble(0, 0, z, 1);
          for (final x in [-.5, .5]) {
            for (final y in [-.5, .5]) {
              final point =
                  center +
                  MatrixUtils.transformPoint(face, Offset(x * side, y * side));
              expect(point.dy, greaterThanOrEqualTo(bounds.top + 4));
              expect(point.dy, lessThanOrEqualTo(bounds.bottom - 4));
              expect(
                heading.inflate(4).contains(point),
                isFalse,
                reason:
                    'Every sleeve corner stays clear of metadata in either adaptive layout.',
              );
            }
          }
        }
        expect(side, 302);
        expect(
          t.getSize(find.byKey(const Key('album-stage-bounds'))),
          original,
        );
        expect(t.takeException(), isNull);
        await base.screenshot(
          t,
          'cover22-fixed-native-corner-${pose.dx.toInt()}-${pose.dy.toInt()}',
        );
      }
      await mouse.removePointer();
      await t.ensureVisible(find.byKey(const Key('player-equalizer')));
      await t.pumpAndSettle();
      final control = t.getRect(find.byKey(const Key('player-equalizer')));
      expect(control.top, greaterThanOrEqualTo(0));
      expect(control.bottom, lessThanOrEqualTo(900));
      await base.clean(t, c);
      clearArtworkFixture();
    },
  );
}
