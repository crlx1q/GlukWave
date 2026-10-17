import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/connect_device_tile.dart';
import 'package:glukwave/ui/desktop_player.dart';
import 'package:glukwave/ui/mini_lyrics.dart';
import 'package:glukwave/ui/motion_icons.dart';
import 'package:glukwave/ui/player_gestures.dart';
import 'package:glukwave/ui/physical_wave_clock.dart';
import 'package:glukwave/ui/device_labels.dart';
import 'package:flutter/scheduler.dart';
import 'package:glukwave/ui/widgets.dart';
import 'package:glukwave/services/desktop.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/core/equalizer.dart';
import 'package:glukwave/ui/native19_desktop_transport.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_layout_test.dart' as f;
import 'audio_design_test.dart' as audio;
import 'audio_lifecycle_test.dart' as lifecycle;
import 'helpers/fonts.dart';

class HardwareUiAudio extends WaveAudioHandler {
  HardwareUiAudio(super.api, super.cache)
    : super(hardwareVolume: true, output: lifecycle.NativeOutput());
  @override
  bool get equalizerSupported => true;
  @override
  Future<void> applyProcessing(
    WaveEqualizer preference,
    double rate, {
    bool inRoom = false,
  }) async {}
}

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
  for (final cover3d in [true, false]) {
    testWidgets(
      'Current/next lyric rail remains present with ${cover3d ? '3D' : '2D'} cover on phone',
      (tester) async {
        final c = (await tester.runAsync(audio.makeController))!;
        await tester.runAsync(
          () => c.customize({
            'appearance': {'cover3d': cover3d},
          }),
        );
        c.settings['lyrics'] = true;
        c.settings['lyricsUnderCover'] = true;
        (c.api as f.LayoutApi).lyricLines = [
          {'time': 0, 'text': 'Current line of the song'},
          {'time': 20, 'text': 'The next line waits below'},
          {'time': 40, 'text': 'A third line stays hidden'},
        ];
        (c.api as f.LayoutApi).lyricSynchronized = true;
        await f.viewport(tester, const Size(390, 844));
        await tester.pumpWidget(
          audio.shell(c, PlayerPage(controller: c, onMore: (_) {})),
        );
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('mini-lyrics-frame')), findsOneWidget);
        expect(find.text('Current line of the song'), findsOneWidget);
        expect(find.text('The next line waits below'), findsOneWidget);
        expect(find.text('A third line stays hidden'), findsNothing);
        final frame = tester.getRect(
          find.byKey(const Key('mini-lyrics-frame')),
        );
        final seek = tester.getRect(find.byKey(const Key('player-seek')));
        expect(frame.bottom, lessThanOrEqualTo(seek.top));
        await tester.ensureVisible(
          find.byKey(const Key('player-compact-lyrics')),
        );
        await tester.pumpAndSettle();
        await f.screenshot(
          tester,
          'parity23-phone-${cover3d ? '3d' : '2d'}-lyrics',
        );
        c.settings['lyricsUnderCover'] = false;
        c.render();
        await tester.pumpWidget(
          audio.shell(c, PlayerPage(controller: c, onMore: (_) {})),
        );
        await tester.pump();
        expect(find.byKey(const Key('mini-lyrics-frame')), findsNothing);
        await f.clean(tester, c);
      },
    );
  }
  testWidgets(
    'Idle preview adopts its own playback, then follows next track metadata',
    (tester) async {
      final c = (await tester.runAsync(audio.makeController))!;
      final preview = c.tracks[1];
      await f.viewport(tester, const Size(1280, 900));
      await tester.pumpWidget(
        audio.shell(
          c,
          PlayerPage(controller: c, initialTrack: preview, onMore: (_) {}),
        ),
      );
      await settle(tester);
      expect(find.text(preview.title), findsWidgets);
      c.audio.current = c.tracks[2];
      c.render();
      await tester.pump();
      expect(find.text(preview.title), findsWidgets);
      c.audio.current = preview;
      c.render();
      await tester.pump();
      c.audio.current = c.tracks[2];
      c.render();
      await settle(tester);
      expect(find.text(preview.title), findsNothing);
      expect(find.text(c.tracks[2].title), findsWidgets);
      expect(tester.takeException(), isNull);
      await f.clean(tester, c);
    },
  );
  testWidgets('Independent Connect active remote row retains its own song', (
    tester,
  ) async {
    final c = (await tester.runAsync(audio.makeController))!;
    c.connect = {'independent': true, 'activeDeviceId': 'remote-desktop'};
    final remote = {
      'id': 'remote-desktop',
      'name': 'GlukWave · Windows',
      'online': true,
      'track': c.tracks[2].json,
      'state': {'trackId': c.tracks[2].id, 'playing': true},
    };
    await f.viewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      audio.shell(
        c,
        Scaffold(
          body: ConnectDeviceTile(controller: c, device: remote),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(c.tracks[2].title), findsOneWidget);
    expect(find.text(c.tracks[0].title), findsNothing);
    expect(find.text('Selected output · paused'), findsNothing);
    expect(find.text('Selected output'), findsOneWidget);
    await f.screenshot(tester, 'parity23-independent-connect');
    expect(tester.takeException(), isNull);
    await f.clean(tester, c);
  });
  testWidgets(
    'Phone mini player is 60px with 44px touch targets and vector brand',
    (tester) async {
      final c = (await tester.runAsync(audio.makeController))!;
      await f.viewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        audio.shell(
          c,
          Scaffold(
            body: Column(
              children: [
                const Brand(compact: true, animated: true),
                MiniPlayer(controller: c, onOpen: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(MiniPlayer)).height, 60);
      expect(
        tester.getSize(find.byKey(const Key('mini-like'))).height,
        greaterThanOrEqualTo(44),
      );
      expect(find.byKey(const Key('glukwave-vector-mark')), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await f.screenshot(tester, 'parity23-phone-mini-brand');
      expect(tester.takeException(), isNull);
      await f.clean(tester, c);
    },
  );
  testWidgets(
    'Collapsed desktop excludes lyrics and retains compact transport',
    (tester) async {
      final c = (await tester.runAsync(audio.makeController))!;
      c.settings['lyrics'] = true;
      c.settings['lyricsUnderCover'] = true;
      (c.api as f.LayoutApi).lyricLines = [
        {'time': 0, 'text': 'Current lyric'},
        {'time': 12, 'text': 'Next lyric'},
      ];
      await f.viewport(tester, const Size(410, 116));
      await tester.pumpWidget(
        audio.shell(c, DesktopCompactPlayer(controller: c)),
      );
      await settle(tester);
      expect(find.byType(MiniLyrics), findsNothing);
      expect(find.text('Current lyric'), findsNothing);
      expect(find.text('Next lyric'), findsNothing);
      expect(c.desktop.compactLyrics, isFalse);
      expect(compactPlayerSize(quick: false, lyrics: true).height, 116);
      expect(compactPlayerSize(quick: false).height, 116);
      expect(tester.takeException(), isNull);
      await f.screenshot(tester, 'parity23-desktop-mini-lyrics');
      await f.clean(tester, c);
    },
  );
  testWidgets('Native loading clock stays 900ms at custom appearance speed', (
    tester,
  ) async {
    final c = (await tester.runAsync(audio.makeController))!;
    await tester.runAsync(
      () => c.customize({
        'reducedMotion': false,
        'appearance': {'speed': 1.8},
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWaveTheme(c.customization, Brightness.dark),
        home: const WavePlaybackIcon(playing: false, loading: true),
      ),
    );
    await tester.pump();
    final dynamic state = tester.state(find.byType(WavePlaybackIcon));
    expect(
      (state.loop as PhysicalWaveClock).duration,
      const Duration(milliseconds: 900),
    );
    expect(
      (state.entry as AnimationController).duration,
      const Duration(milliseconds: 220),
    );
    await f.clean(tester, c);
  });
  testWidgets('Track content animation uses the incoming queue direction', (
    tester,
  ) async {
    final c = (await tester.runAsync(audio.makeController))!;
    await f.viewport(tester, const Size(390, 844));
    Widget scene() => audio.shell(
      c,
      TrackMotion(controller: c, child: Text(c.audio.viewCurrent!.title)),
    );
    await tester.pumpWidget(scene());
    c.audio.current = c.tracks[1];
    await tester.pumpWidget(scene());
    expect(find.text(c.tracks[1].title), findsOneWidget);
    // Energy/reduced-motion fixture settles immediately without stale content.
    final movement = tester.widget<FractionalTranslation>(
      find.byKey(const Key('player-track-motion')),
    );
    expect(movement.translation, Offset.zero);
    expect(tester.takeException(), isNull);
    await f.clean(tester, c);
  });
  testWidgets(
    'Real phone audio policy hides local volume and keeps desktop remote control',
    (tester) async {
      final c = (await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final api = f.LayoutApi(), cache = MusicCache(api);
        final c = f.LayoutController(api, cache, HardwareUiAudio(api, cache));
        c.preferences = await SharedPreferences.getInstance();
        await c.restoreCustomizationScope();
        await c.customize({'reducedMotion': true, 'language': 'ru'});
        return c;
      }))!;
      c.loading = false;
      c.online = true;
      final song = WaveTrack({
        'id': 'phone-track',
        'title': 'Марсель — Был Өмірде',
        'artist': 'Алихан Ғарышқан',
        'duration': 240,
        'artwork': '',
        'source': 'local',
        'playback': {'kind': 'audio', 'url': '/own.wav'},
      });
      c.tracks = [song];
      c.audio.tracks = [song];
      c.audio.current = song;
      await f.viewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        audio.shell(c, PlayerPage(controller: c, onMore: (_) {}), scale: 1),
      );
      await settle(tester);
      expect(c.audio.hardwareVolume, isTrue);
      expect(find.byKey(const Key('player-volume')), findsNothing);
      await f.screenshot(tester, 'parity23-phone-hardware-volume');
      c.connect = {
        'activeDeviceId': 'desktop-output',
        'activeDeviceName': 'GlukWave · Windows',
        'independent': false,
      };
      await tester.runAsync(() async {
        c.audio.showRemote(
          PlaybackSnapshot.fromJson({'trackId': song.id}),
          song,
          [song],
        );
      });
      c.render();
      await tester.pumpWidget(
        audio.shell(c, PlayerPage(controller: c, onMore: (_) {}), scale: 1),
      );
      await settle(tester);
      expect(find.byKey(const Key('player-volume')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await f.clean(tester, c);
    },
  );
  testWidgets(
    'Desktop bottom transport stays compact with or without lyric rail',
    (tester) async {
      final c = (await tester.runAsync(audio.makeController))!;
      c.settings['lyricsUnderCover'] = true;
      await f.viewport(tester, const Size(1280, 900));
      Widget scene() => audio.shell(
        c,
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: NativeDesktopTransport(controller: c, onOpen: () {}),
          ),
        ),
      );
      await tester.pumpWidget(scene());
      await settle(tester);
      expect(tester.getSize(find.byType(NativeDesktopTransport)).height, 68);
      (c.api as f.LayoutApi).lyricLines = [
        {'time': 0, 'text': 'Current lyric'},
        {'time': 20, 'text': 'Next lyric'},
      ];
      c.audio.current = c.tracks[1];
      c.render();
      await tester.pumpWidget(scene());
      await settle(tester);
      expect(tester.getSize(find.byType(NativeDesktopTransport)).height, 68);
      expect(find.text('Current lyric'), findsNothing);
      expect(find.byType(MiniLyrics), findsNothing);
      await f.screenshot(tester, 'parity24-bottom-clean');
      c.settings['lyricsUnderCover'] = false;
      await tester.pumpWidget(scene());
      await settle(tester);
      expect(tester.getSize(find.byType(NativeDesktopTransport)).height, 68);
      expect(tester.takeException(), isNull);
      await f.clean(tester, c);
    },
  );
  testWidgets('Next and previous animate metadata in opposite directions', (
    tester,
  ) async {
    final c = (await tester.runAsync(audio.makeController))!;
    await tester.runAsync(() => c.customize({'reducedMotion': false}));
    Widget scene() => MaterialApp(
      theme: buildWaveTheme(c.customization, Brightness.dark),
      home: TrackMotion(controller: c, child: Text(c.audio.viewCurrent!.title)),
    );
    await tester.pumpWidget(scene());
    c.audio.current = c.tracks[1];
    await tester.pumpWidget(scene());
    final next = tester.widget<FractionalTranslation>(
      find.byKey(const Key('player-track-motion')),
    );
    expect(next.translation.dx, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester
          .widget<FractionalTranslation>(
            find.byKey(const Key('player-track-motion')),
          )
          .translation
          .dx,
      lessThan(next.translation.dx),
    );
    c.audio.current = c.tracks[0];
    await tester.pumpWidget(scene());
    expect(
      tester
          .widget<FractionalTranslation>(
            find.byKey(const Key('player-track-motion')),
          )
          .translation
          .dx,
      lessThan(0),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await f.clean(tester, c);
  });
  testWidgets(
    'Wide desktop restores cover beside controls and CD has an opaque tray',
    (tester) async {
      final c = (await tester.runAsync(audio.makeController))!;
      await tester.runAsync(
        () => c.customize({
          'appearance': {'cover3d': true, 'coverKind': 'cd'},
        }),
      );
      await f.viewport(tester, const Size(1497, 900));
      await tester.pumpWidget(
        audio.shell(c, PlayerPage(controller: c, onMore: (_) {}), scale: 1),
      );
      await settle(tester);
      expect(find.byKey(const Key('player-wide-layout')), findsOneWidget);
      final cover = tester.getRect(
            find.byKey(const Key('player-cover-gesture')),
          ),
          controls = tester.getRect(
            find.byKey(const Key('player-transport-capsule')),
          );
      expect(cover.right, lessThan(controls.left));
      expect(cover.top, greaterThanOrEqualTo(0));
      expect(cover.bottom, lessThanOrEqualTo(900));
      final tray = tester.widget<Container>(
        find.byKey(const Key('album-cd-tray')),
      );
      expect((tray.decoration as BoxDecoration).color?.a, 1);
      await f.screenshot(tester, 'parity23-wide-cd-opaque');
      expect(tester.takeException(), isNull);
      await f.clean(tester, c);
    },
  );
  for (final speed in [.5, 1.0, 2.0]) {
    testWidgets(
      'Physical loading/listening cycle ignores appearance speed $speed',
      (tester) async {
        final c = (await tester.runAsync(audio.makeController))!;
        await tester.runAsync(
          () => c.customize({
            'reducedMotion': false,
            'appearance': {'speed': speed},
          }),
        );
        timeDilation = 1 / speed;
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: buildWaveTheme(c.customization, Brightness.dark),
              home: const Row(
                children: [
                  WavePlaybackIcon(playing: false, loading: true),
                  ListeningWave(playing: true),
                ],
              ),
            ),
          );
          await tester.pump();
          final dynamic playState = tester.state(find.byType(WavePlaybackIcon)),
              listenState = tester.state(find.byType(ListeningWave));
          final loading = playState.loop as PhysicalWaveClock,
              listening = listenState.clock as PhysicalWaveClock;
          final before = loading.watch.elapsedMicroseconds;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 160)),
          );
          await tester.pump();
          final elapsed = loading.watch.elapsedMicroseconds - before;
          expect(elapsed, greaterThanOrEqualTo(150000));
          expect(
            loading.value,
            closeTo(
              (loading.watch.elapsedMicroseconds %
                      loading.duration.inMicroseconds) /
                  loading.duration.inMicroseconds,
              .025,
            ),
          );
          expect(
            listening.value,
            closeTo(
              (listening.watch.elapsedMicroseconds % 1200000) / 1200000,
              .025,
            ),
          );
          expect(loading.duration, const Duration(milliseconds: 900));
          expect(listening.duration, const Duration(milliseconds: 1200));
          expect(tester.takeException(), isNull);
        } finally {
          timeDilation = 1;
          await f.clean(tester, c);
        }
      },
    );
  }
}
