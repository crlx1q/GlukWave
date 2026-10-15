import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/ui/album_stage.dart';
import 'package:glukwave/ui/lyric_timing.dart';
import 'package:glukwave/ui/mini_lyrics.dart';
import 'package:glukwave/ui/native19_desktop_transport.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/desktop_player.dart';
import 'app_layout_test.dart' as f;
import 'audio_design_test.dart' as a;
import 'helpers/fonts.dart';

const lines = <Json>[
  {'time': 10, 'text': 'The sea comes into view'},
  {'time': 16, 'text': 'And the evening follows slowly'},
  {'time': 22, 'text': 'We keep a light in the window'},
  {'time': 28, 'text': 'Until the morning finds us'},
  {'time': 34, 'text': 'A distant line stays soft'},
];

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 35)),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
    await loadAppFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test(
    'Lyric intro uses the media clock and seeks cancel or restore its cue',
    () {
      expect(lyricCue(lines, true, 0).countdown, isNull);
      expect(lyricCue(lines, true, 7).countdown, 3);
      expect(lyricCue(lines, true, 8.25).countdown, 2);
      expect(lyricCue(lines, true, 9.9).countdown, 1);
      expect(lyricCue(lines, true, 10).active, 0);
      expect(lyricCue(lines, true, 20).intro, isFalse);
      expect(lyricCue(lines, true, 8).countdown, 2);
      expect(lyricCue(lines, false, 8).countdown, isNull);
      expect(
        lyricCue(
          [
            {'time': 0, 'text': 'Immediate'},
          ],
          true,
          0,
        ).countdown,
        isNull,
      );
      expect(
        lyricCue(
          [
            {'time': 0, 'text': ''},
            {'time': 1, 'text': '♪'},
            ...lines,
          ],
          true,
          8,
        ).countdown,
        2,
      );
      expect(lyricDefocus(1, 0), 0);
      expect(lyricDefocus(5, 0), closeTo(4.6, .001));
    },
  );
  testWidgets(
    'Mini lyric rail changes from 3 to 2 to 1 then current and next without its own timer',
    (tester) async {
      final c = (await tester.runAsync(a.makeController))!;
      c.settings['lyrics'] = true;
      c.settings['lyricsUnderCover'] = true;
      await f.viewport(tester, const Size(390, 240));
      Future<void> position(double seconds) async {
        c.audio.showRemote(
          PlaybackSnapshot.fromJson({
            'trackId': c.tracks[0].id,
            'position': seconds,
            'playing': false,
          }),
          c.tracks[0],
          c.tracks,
        );
        await tester.pumpWidget(
          a.shell(
            c,
            Center(
              child: MiniLyrics(
                controller: c,
                track: c.tracks[0],
                lines: lines,
                synchronized: true,
              ),
            ),
            scale: 1,
          ),
        );
        await settle(tester);
      }

      await position(7.2);
      expect(find.text('3'), findsOneWidget);
      expect(find.text(lines[0]['text']), findsNothing);
      await f.screenshot(tester, 'parity24-intro-3');
      await position(8.2);
      expect(find.text('2'), findsOneWidget);
      await position(9.2);
      expect(find.text('1'), findsOneWidget);
      await position(10.2);
      expect(find.byType(LyricCountdown), findsNothing);
      expect(find.text(lines[0]['text']), findsOneWidget);
      expect(find.text(lines[1]['text']), findsOneWidget);
      final rail = tester.widget<Container>(
        find.byKey(const Key('mini-lyrics-frame')),
      );
      expect(
        (rail.decoration as BoxDecoration).border!.top.style,
        BorderStyle.none,
      );
      await f.screenshot(tester, 'parity24-lyric-rail');
      expect(tester.takeException(), isNull);
      await f.clean(tester, c);
    },
  );
  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    testWidgets(
      'Full lyric depth and entry transition fit ${size.width} viewport',
      (tester) async {
        final c = (await tester.runAsync(a.makeController))!;
        c.settings['lyrics'] = true;
        c.settings['lyricsUnderCover'] = true;
        (c.api as f.LayoutApi).lyricLines = lines;
        (c.api as f.LayoutApi).lyricSynchronized = true;
        c.audio.showRemote(
          PlaybackSnapshot.fromJson({
            'trackId': c.tracks[0].id,
            'position': 10.5,
            'playing': false,
          }),
          c.tracks[0],
          c.tracks,
        );
        await f.viewport(tester, size);
        await tester.pumpWidget(
          a.shell(c, PlayerPage(controller: c, onMore: (_) {}), scale: 1),
        );
        await settle(tester);
        await tester.tap(find.byKey(const Key('player-lyrics-toggle')));
        await settle(tester);
        expect(
          find.byKey(const ValueKey('player-view-entry-1')),
          findsOneWidget,
        );
        expect(find.byType(ImageFiltered), findsWidgets);
        if (size.width >= 1000) {
          expect(
            tester
                .getRect(find.byKey(const Key('player-secondary-capsule')))
                .bottom,
            lessThanOrEqualTo(size.height),
          );
        }
        expect(tester.getSize(find.byType(PlayerPage)).width, size.width);
        await f.screenshot(
          tester,
          'parity24-full-lyrics-${size.width.toInt()}',
        );
        expect(tester.takeException(), isNull);
        await f.clean(tester, c);
      },
    );
  }
  testWidgets('Desktop bottom excludes lyrics and preserves remote metadata', (
    tester,
  ) async {
    final c = (await tester.runAsync(a.makeController))!;
    c.settings['lyrics'] = true;
    c.settings['lyricsUnderCover'] = true;
    (c.api as f.LayoutApi).lyricLines = [
      {'time': 0, 'text': 'The sea comes into view'},
      {'time': 20, 'text': 'And the evening follows slowly'},
    ];
    (c.api as f.LayoutApi).lyricSynchronized = true;
    await f.viewport(tester, const Size(1440, 300));
    await tester.pumpWidget(
      a.shell(
        c,
        Align(
          alignment: Alignment.bottomCenter,
          child: NativeDesktopTransport(controller: c, onOpen: () {}),
        ),
        scale: 1,
      ),
    );
    await settle(tester);
    expect(tester.getSize(find.byType(NativeDesktopTransport)).height, 96);
    expect(find.byType(MiniLyrics), findsNothing);
    expect(find.text('The sea comes into view'), findsNothing);
    await f.screenshot(tester, 'parity24-desktop-bottom-clean');
    c.connect = {
      'activeDeviceId': 'remote-desktop',
      'activeDeviceName': 'GlukWave · Windows',
      'independent': false,
    };
    c.audio.showRemote(
      PlaybackSnapshot.fromJson({
        'trackId': c.tracks[0].id,
        'position': 0,
        'playing': false,
      }),
      c.tracks[0],
      c.tracks,
    );
    await tester.pumpWidget(
      a.shell(
        c,
        Align(
          alignment: Alignment.bottomCenter,
          child: NativeDesktopTransport(controller: c, onOpen: () {}),
        ),
        scale: 1.25,
      ),
    );
    await settle(tester);
    await f.screenshot(tester, 'parity24-desktop-bottom-remote-125');

    expect(tester.takeException(), isNull);
    await f.clean(tester, c);
  });
  testWidgets('Compact native window excludes lyrics at125percent text', (
    tester,
  ) async {
    final c = (await tester.runAsync(a.makeController))!;
    c.settings['lyrics'] = true;
    c.settings['lyricsUnderCover'] = true;
    (c.api as f.LayoutApi).lyricLines = [
      {'time': 0, 'text': 'The sea comes into view'},
      {'time': 20, 'text': 'And the evening follows slowly'},
    ];
    (c.api as f.LayoutApi).lyricSynchronized = true;
    await f.viewport(tester, const Size(410, 116));
    await tester.pumpWidget(
      a.shell(c, DesktopCompactPlayer(controller: c), scale: 1.25),
    );
    await settle(tester);
    expect(find.text('The sea comes into view'), findsNothing);
    expect(find.text('And the evening follows slowly'), findsNothing);
    expect(find.byType(MiniLyrics), findsNothing);
    await f.screenshot(tester, 'parity24-compact-window-125');
    expect(tester.takeException(), isNull);
    await f.clean(tester, c);
  });
  testWidgets(
    'CD lid retains opaque reverse and all four thickness edges through full rotation',
    (tester) async {
      final c = (await tester.runAsync(a.makeController))!;
      await tester.runAsync(
        () => c.customize({
          'appearance': {'cover3d': true, 'coverKind': 'cd'},
        }),
      );
      await f.viewport(tester, const Size(800, 700));
      await tester.pumpWidget(
        a.shell(
          c,
          Center(
            child: AlbumStage(
              controller: c,
              track: c.tracks[0],
              size: 302,
              playing: false,
            ),
          ),
          scale: 1,
        ),
      );
      await settle(tester);
      final dynamic state = tester.state(find.byType(AlbumStage));
      final bounds = tester.getSize(
        find.byKey(const Key('album-stage-bounds')),
      );
      for (final angle in [0, 45, 82, 100, 135, 180, 225, 260, 315, 360]) {
        state.setState(
          () => state.tilt = Offset((angle + 18) * math.pi / 180, 0),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(const Key('album-stage-bounds'))),
          bounds,
        );
        for (final edge in ['top', 'bottom', 'left', 'right']) {
          expect(find.byKey(Key('album-cd-lid-$edge')), findsOneWidget);
        }
        if (math.cos((angle - 14) * math.pi / 180) < 0) {
          final interior = tester.widget<Container>(
            find.byKey(const Key('album-cd-lid-inner')),
          );
          expect(
            (interior.decoration as BoxDecoration).gradient!.colors.every(
              (color) => color.a == 1,
            ),
            isTrue,
          );
        }
        await f.screenshot(tester, 'parity24-cd-$angle');
      }
      expect(tester.takeException(), isNull);
      await f.clean(tester, c);
    },
  );
}
