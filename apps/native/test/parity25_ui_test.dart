import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/core/library_mutations.dart';
import 'package:glukwave/core/library_order.dart';
import 'package:glukwave/ui/album_stage.dart';
import 'package:glukwave/ui/cover_planes.dart';
import 'package:glukwave/ui/mini_lyrics.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/library_sort.dart';
import 'package:glukwave/ui/app.dart';
import 'app_layout_test.dart' as f;
import 'audio_design_test.dart' as a;
import 'native19_ui_test.dart' as n;
import 'helpers/artwork_fixture.dart';
import 'helpers/fonts.dart';

const lines = <Json>[
  {'time': 0, 'text': 'We keep a light in the window'},
  {'time': 10, 'text': 'Until the morning finds us'},
  {'time': 20, 'text': 'And the evening follows slowly'},
  {'time': 30, 'text': 'A distant line stays soft'},
  {'time': 40, 'text': 'A quiet shore comes into view'},
  {'time': 50, 'text': 'The tide carries our memory'},
];
Future<void> settle(WidgetTester t) async {
  await t.pump();
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await t.pumpAndSettle();
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
  setUp(installArtworkFixture);
  tearDown(clearArtworkFixture);
  test('Legacy likes normalize once and rollback retains confirmed dates', () {
    final j = LibraryMutations({
      'tracks': [],
      'likedIds': ['old', 'new'],
      'playlists': [],
      'history': [],
    });
    expect(j.visible['likedIds'], ['new', 'old']);
    expect(copyLibrary(j.visible)['likedIds'], ['new', 'old']);
    j.acceptSnapshot({
      'likedIds': ['first', 'second'],
      'likedAt': {'first': '2026-10-15T10:00:00Z'},
      'tracks': [],
      'playlists': [],
      'history': [],
    }, j.revision);
    expect(j.visible['likedIds'], ['first', 'second']);
    final e = j.begin('like:now', 'like', 'now', {
      'liked': true,
      'likedAt': '2026-10-15T11:00:00Z',
    });
    expect(j.visible['likedIds'], ['now', 'first', 'second']);
    expect(object(j.visible['likedAt'])['now'], '2026-10-15T11:00:00Z');
    expect(object(j.visible['addedAt'])['now'], '2026-10-15T11:00:00Z');
    j.reject(e);
    expect(object(j.visible['likedAt']).containsKey('now'), isFalse);
    final legacy = j.begin('like:legacy', 'like', 'legacy', {
      'liked': true,
      'likedAt': '2026-10-15T12:00:00Z',
    });
    legacy.data['likedAt'] = null;
    j.acknowledge(legacy);
    expect(object(j.visible['likedAt']).containsKey('legacy'), isFalse);
  });
  test(
    'Membership dates are instant; viewing a sort does not reorder the playlist',
    () {
      final j = LibraryMutations({
        'tracks': [],
        'likedIds': [],
        'likedAt': {},
        'playlists': [
          {
            'id': 'p',
            'trackIds': ['a'],
            'trackAddedAt': {'a': '2026-10-01T00:00:00Z'},
          },
        ],
        'history': [],
      });
      final e = j.begin('playlist:p', 'membership', 'p', {
        'trackId': 'b',
        'present': true,
        'addedAt': '2026-10-15T00:00:00Z',
      });
      expect(object(j.visible['addedAt'])['b'], '2026-10-15T00:00:00Z');
      j.reject(e);
      expect(objects(j.visible['playlists']).first['trackIds'], ['a']);
      final tracks = [
        WaveTrack({'id': 'a', 'title': 'Zebra', 'artist': 'B', 'duration': 90}),
        WaveTrack({
          'id': 'b',
          'title': 'Alpha',
          'artist': 'A',
          'duration': 200,
        }),
      ];
      expect(sortedTracks(tracks, 'title', tracks).map((t) => t.id), [
        'b',
        'a',
      ]);
      expect(tracks.map((t) => t.id), ['a', 'b']);
      expect(
        byRecentDates(tracks, {
          'a': '2026-10-15T10:00:00Z',
          'b': '2026-10-01T10:00:00Z',
        }).map((t) => t.id),
        ['a', 'b'],
      );
    },
  );
  test(
    'Depth clipping removes only disc pixels covered by the physical sleeve',
    () {
      final scene = AlbumPlaneScene(
        size: 300,
        camera: Matrix4.identity()..setEntry(3, 2, -1 / 1100),
        planes: [
          CoverPlane(
            const SizedBox(),
            Matrix4.identity()..translateByDouble(138, 9, 0, 1),
            282,
            282,
            twoSided: true,
            circle: true,
          ),
          CoverPlane(
            const SizedBox(),
            Matrix4.identity()..translateByDouble(0, 0, 9, 1),
            300,
            300,
          ),
        ],
      );
      final p = scene.projected,
          visible = visibleCoverPath(scene.projected[0], scene.projected);
      expect(visible.contains(const Offset(225, 150)), isFalse);
      expect(visible.contains(const Offset(350, 150)), isTrue);
      expect(
        visibleCoverPath(p[1], p).contains(const Offset(150, 150)),
        isTrue,
      );
    },
  );
  for (final kind in ['vinyl', 'cd']) {
    testWidgets('Actual $kind opaque scene through twelve poses', (t) async {
      final c = (await t.runAsync(a.makeController))!;
      await t.runAsync(
        () => c.customize({
          'appearance': {'cover3d': true, 'coverKind': kind},
        }),
      );
      final track = WaveTrack({
        ...c.tracks.first.json,
        'artwork': 'https://qa.invalid/coast.jpg',
      });
      await f.viewport(t, const Size(800, 700));
      await t.pumpWidget(
        a.shell(
          c,
          Center(
            child: AlbumStage(
              controller: c,
              track: track,
              size: 302,
              playing: false,
            ),
          ),
          scale: 1,
        ),
      );
      await settle(t);
      final dynamic state = t.state(find.byType(AlbumStage));
      final bounds = t.getSize(find.byKey(const Key('album-stage-bounds')));
      for (final pose in [
        (0, -9),
        (45, -9),
        (82, -9),
        (100, -9),
        (135, -9),
        (180, -9),
        (225, -9),
        (260, -9),
        (315, -9),
        (360, -9),
        (82, -38),
        (260, 38),
      ]) {
        state.setState(
          () => state.tilt = Offset(
            (pose.$1 + 18) * math.pi / 180,
            (-9 - pose.$2) * math.pi / 180,
          ),
        );
        await t.pumpAndSettle();
        final scene = t.widget<AlbumPlaneScene>(find.byType(AlbumPlaneScene));
        expect(scene.projected.where((p) => p.visible), isNotEmpty);
        expect(t.getSize(find.byKey(const Key('album-stage-bounds'))), bounds);
        for (final p in scene.projected) {
          expect(
            p.polygon.every((p) => p.dx.isFinite && p.dy.isFinite),
            isTrue,
          );
        }
        await f.screenshot(t, 'parity25-$kind-${pose.$1}-${pose.$2}');
      }
      expect(t.takeException(), isNull);
      clearArtworkFixture();
      await f.clean(t, c);
    });
  }
  for (final size in [
    const Size(1440, 900),
    const Size(768, 900),
    const Size(375, 812),
  ]) {
    testWidgets('Expanded lyrics below artwork at $size', (t) async {
      final c = (await t.runAsync(a.makeController))!;
      c.tracks = [
        WaveTrack({
          ...c.tracks.first.json,
          'artwork': 'https://qa.invalid/coast.jpg',
        }),
        ...c.tracks.skip(1),
      ];
      c.settings['lyrics'] = true;
      c.settings['lyricsUnderCover'] = true;
      (c.api as f.LayoutApi).lyricLines = lines;
      (c.api as f.LayoutApi).lyricSynchronized = true;
      c.audio.showRemote(
        PlaybackSnapshot.fromJson({
          'trackId': c.tracks.first.id,
          'position': 1,
          'playing': false,
        }),
        c.tracks.first,
        c.tracks,
      );
      await f.viewport(t, size);
      await t.pumpWidget(
        a.shell(c, PlayerPage(controller: c, onMore: (_) {}), scale: 1),
      );
      await settle(t);
      final art = t.getRect(find.byKey(const Key('album-stage-bounds'))),
          lyric = t.getRect(find.byType(MiniLyrics));
      expect(lyric.top, greaterThan(art.top));
      expect(lyric.center.dx - art.center.dx, closeTo(0, 40));
      if (size.width >= 1100) {
        expect(
          lyric.right,
          lessThan(t.getRect(find.byKey(const Key('player-play'))).left),
        );
      }
      await f.screenshot(t, 'parity25-expanded-${size.width.toInt()}');
      await t.tap(find.byKey(const Key('player-lyrics-toggle')));
      await settle(t);
      await f.screenshot(t, 'parity25-full-lyrics-${size.width.toInt()}');
      expect(t.takeException(), isNull);
      clearArtworkFixture();
      await f.clean(t, c);
    });
  }
  for (final size in [
    const Size(320, 568),
    const Size(375, 812),
    const Size(768, 900),
    const Size(1440, 900),
  ]) {
    testWidgets('Library sort fits $size at125percent', (t) async {
      final c = (await t.runAsync(n.fixture))!;
      c.likedIds = c.tracks.reversed.map((t) => t.id).toList();
      await t.runAsync(() => c.customize({'fontScale': 1.25}));
      await f.viewport(t, size);
      await t.pumpWidget(
        RepaintBoundary(
          key: const Key('capture'),
          child: GlukWaveApp(controller: c),
        ),
      );
      await settle(t);
      final dynamic shell = t.state(find.byType(WaveShell));
      shell.setState(() {
        shell.page = WavePage.library;
        shell.filter = 'liked';
      });
      await settle(t);
      expect(find.byType(LibrarySortControl), findsOneWidget);
      await t.ensureVisible(find.byType(LibrarySortControl));
      await t.tap(find.byType(LibrarySortControl));
      await settle(t);
      await f.screenshot(t, 'parity25-library-sort-${size.width.toInt()}');
      await t.tap(
        find
            .text(
              librarySortText(
                t.element(find.byType(LibrarySortControl)),
                'title',
              ),
            )
            .last,
      );
      await settle(t);
      expect(t.takeException(), isNull);
      clearArtworkFixture();
      await f.clean(t, c);
    });
  }
}
