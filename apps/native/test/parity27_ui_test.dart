import 'package:glukwave/ui/recommendation_actions.dart';
import 'package:glukwave/ui/home_shelf.dart';
import 'package:glukwave/ui/provider_import.dart';
import 'package:glukwave/ui/update_notice.dart';
import 'package:glukwave/services/app_updates.dart';
import 'package:glukwave/ui/app.dart';
import 'native19_ui_test.dart' as n;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/native19_desktop_transport.dart';
import 'package:glukwave/ui/listening_rail.dart';
import 'package:glukwave/ui/desktop_titlebar.dart';
import 'package:glukwave/ui/queue_panel.dart';
import 'package:glukwave/ui/volume_panel.dart';
import 'package:glukwave/services/cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'app_layout_test.dart' as f;
import 'audio_design_test.dart' as a;
import 'helpers/fonts.dart';

class QueueFixture extends f.LayoutController {
  int moves = 0;
  QueueFixture(super.api, super.cache, super.audio);
  @override
  Future<void> moveQueue(int from, int to) async {
    moves++;
    final next = List<WaveTrack>.of(audio.tracks);
    final row = next.removeAt(from);
    next.insert(to, row);
    audio.tracks = next;
    render();
  }
}

Future<QueueFixture> queueFixture() async {
  SharedPreferences.setMockInitialValues({});
  final api = f.LayoutApi(),
      cache = MusicCache(api),
      audio = a.UiAudio(api, cache),
      c = QueueFixture(api, cache, audio);
  c.preferences = await SharedPreferences.getInstance();
  await c.restoreCustomizationScope();
  await c.customize({'reducedMotion': true, 'language': 'en'});
  c.tracks = List.generate(
    30,
    (i) => WaveTrack({
      'id': 'queue-$i',
      'title': 'Ночной берег $i',
      'artist': 'GlukWave sessions',
      'duration': 210,
      'source': 'local',
      'artwork': '',
    }),
  );
  audio.tracks = c.tracks;
  audio.current = c.tracks.first;
  c.loading = false;
  return c;
}

class TransferApi extends f.LayoutApi {
  bool tokenChecked = false;
  final excluded = <Json>[];
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    if (path == '/api/recommendations/exclude') {
      excluded.add(object(data));
      return {'ok': true};
    }
    if (path == '/api/integrations') {
      return {
        'connections': [
          {'provider': 'spotify', 'configured': true, 'connected': false},
        ],
      };
    }
    if (path == '/api/public-import/spotify/token') {
      tokenChecked = object(data)['accessToken'] == 'qa-personal-token';
      return {
        'connection': {
          'provider': 'spotify',
          'connected': true,
          'manual': true,
          'displayName': 'Original personal library',
        },
      };
    }
    if (path == '/api/integrations/spotify/playlists') {
      return {
        'liked': {
          'id': 'liked',
          'kind': 'likes',
          'name': 'Original likes',
          'trackCount': 2,
        },
        'playlists': [],
      };
    }
    return super.call(path, method: method, data: data, query: query);
  }
}

class PreviewUpdater extends AppUpdater {
  PreviewUpdater(super.api)
    : super(currentVersion: '1.0.0+26', platform: 'windows');
  @override
  bool get visible => release != null && !dismissed;
  void present(UpdatePhase next) {
    release = const AppRelease(
      version: '1.0.1',
      platform: 'windows',
      sha256:
          '0000000000000000000000000000000000000000000000000000000000000000',
      url: '/api/downloads/windows',
      format: 'installer',
      bytes: 40000000,
    );
    phase = next;
    progress = .42;
    notifyListeners();
  }
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
  testWidgets('Desktop dock is104px withseek; phone remains60px', (t) async {
    final c = (await t.runAsync(a.makeController))!;
    for (final size in [
      const Size(1440, 900),
      const Size(1024, 768),
      const Size(800, 900),
      const Size(390, 844),
      const Size(320, 740),
    ]) {
      await f.viewport(t, size);
      await t.pumpWidget(
        a.shell(
          c,
          Align(
            alignment: Alignment.bottomCenter,
            child: MiniPlayer(controller: c, onOpen: () {}),
          ),
          scale: 1.25,
        ),
      );
      await t.pumpAndSettle();
      if (size.width >= 800) {
        expect(find.byType(NativeDesktopTransport), findsOneWidget);
        expect(
          t.getSize(find.byKey(const Key('desktop-main-dock'))).height,
          104,
        );
        expect(find.byKey(const Key('desktop-dock-seek')), findsOneWidget);
      } else {
        expect(find.byType(NativeDesktopTransport), findsNothing);
        expect(t.getSize(find.byType(MiniPlayer)).height, 60);
      }
      expect(t.takeException(), isNull);
      await f.screenshot(t, 'parity27-dock-${size.width.toInt()}');
    }
    await f.clean(t, c);
  });
  testWidgets('Volume panel320to1280 at125percent both themes', (t) async {
    final c = (await t.runAsync(a.makeController))!;
    for (final mode in ['light', 'dark']) {
      for (final size in [
        const Size(320, 740),
        const Size(390, 844),
        const Size(768, 900),
        const Size(1280, 860),
      ]) {
        await f.viewport(t, size);
        await t.pumpWidget(
          a.shell(c, WaveVolumePanel(controller: c), mode: mode, scale: 1.25),
        );
        await t.pumpAndSettle();
        final box = t.getRect(find.byKey(const Key('volume-panel-surface')));
        expect(box.left, greaterThanOrEqualTo(15));
        expect(box.right, lessThanOrEqualTo(size.width - 15));
        expect(t.takeException(), isNull);
        await f.screenshot(t, 'parity27-volume-$mode-${size.width.toInt()}');
      }
    }
    await f.clean(t, c);
  });
  testWidgets('Rail hascontext without second transport seekorvolume', (
    t,
  ) async {
    final c = (await t.runAsync(a.makeController))!;
    await f.viewport(t, const Size(1760, 980));
    await t.pumpWidget(
      a.shell(
        c,
        Align(
          alignment: Alignment.centerRight,
          child: DesktopListeningRail(
            controller: c,
            onExpand: () {},
            onDevices: () {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    expect(find.byKey(const Key('mini-play')), findsNothing);
    expect(find.text('Coming next'), findsOneWidget);
    expect(t.takeException(), isNull);
    await f.screenshot(t, 'parity27-context-rail-1760');
    await f.clean(t, c);
  });
  testWidgets('Queue pickup commitsonce;cancel keepsorder', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final c = (await t.runAsync(queueFixture))!;
    await f.viewport(t, const Size(390, 844));
    await t.pumpWidget(
      a.shell(
        c,
        SingleChildScrollView(
          child: QueuePanel(controller: c, onMore: (_) {}),
        ),
        scale: 1,
      ),
    );
    await t.pumpAndSettle();
    final from = t.getCenter(find.byIcon(Icons.drag_indicator_rounded).first);
    final gesture = await t.startGesture(from, kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(0, 100));
    await t.pump(const Duration(milliseconds: 80));
    expect(find.byKey(const Key('queue-lifted-proxy')), findsOneWidget);
    await f.screenshot(t, 'parity27-queue-pickup-390');
    await gesture.up();
    await t.pumpAndSettle();
    expect(c.moves, 1);
    expect(c.audio.tracks.first.id, isNot('queue-0'));
    final prior = c.audio.tracks.map((e) => e.id).toList();
    final cancel = await t.startGesture(
      t.getCenter(find.byIcon(Icons.drag_indicator_rounded).first),
      kind: PointerDeviceKind.mouse,
    );
    await cancel.moveBy(const Offset(0, 80));
    await t.pump(const Duration(milliseconds: 80));
    await cancel.cancel();
    await t.pumpAndSettle();
    expect(c.moves, 1);
    expect(c.audio.tracks.map((e) => e.id).toList(), prior);
    expect(t.takeException(), isNull);
    await f.clean(t, c);
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('Duplicate queueoccurrences keepindependent stablekeys', (
    t,
  ) async {
    final c = (await t.runAsync(queueFixture))!;
    c.audio.tracks = [c.tracks[0], c.tracks[1], c.tracks[0]];
    await f.viewport(t, const Size(390, 844));
    await t.pumpWidget(
      a.shell(
        c,
        SingleChildScrollView(
          child: QueuePanel(controller: c, onMore: (_) {}),
        ),
        scale: 1,
      ),
    );
    await t.pumpAndSettle();
    expect(find.text(c.tracks[0].title), findsNWidgets(2));
    c.render();
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await f.clean(t, c);
  });
  testWidgets('Titlebar44px controls anddragareadoubleclick', (t) async {
    final calls = <String>[], c = (await t.runAsync(a.makeController))!;
    var maximized = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          calls.add(call.method);
          if (call.method == 'isMaximized') return maximized;
          if (call.method == 'maximize') maximized = true;
          if (call.method == 'unmaximize') maximized = false;
          return null;
        });
    c.desktop.initialized = true;
    await f.viewport(t, const Size(1280, 860));
    await t.pumpWidget(
      a.shell(
        c,
        Align(
          alignment: Alignment.topCenter,
          child: DesktopTitleBar(controller: c),
        ),
        scale: 1,
      ),
    );
    await t.pumpAndSettle();
    expect(t.getSize(find.byKey(const Key('desktop-titlebar'))).height, 44);
    await t.tap(find.byKey(const Key('desktop-window-minimize')));
    await t.pump();
    expect(calls.where((x) => x == 'minimize').length, 1);
    await t.tap(find.byKey(const Key('desktop-window-maximize')));
    await t.pumpAndSettle();
    expect(maximized, isTrue);
    await t.tap(find.byKey(const Key('desktop-window-maximize')));
    await t.pumpAndSettle();
    expect(maximized, isFalse);
    final area = t.getRect(find.byType(DragToMoveArea));
    await t.tapAt(Offset(area.right - 30, area.center.dy));
    await t.pump(const Duration(milliseconds: 100));
    await t.tapAt(Offset(area.right - 30, area.center.dy));
    await t.pumpAndSettle();
    expect(maximized, isTrue);
    await f.screenshot(t, 'parity27-titlebar-1280');
    c.desktop.initialized = false;
    await f.clean(t, c);
  });
  testWidgets(
    'Home editor draft addslikes andgenremix thenreturnsorder at320',
    (t) async {
      final c = (await t.runAsync(a.makeController))!;
      await f.viewport(t, const Size(320, 740));
      List<Json>? result;
      await t.pumpWidget(
        a.shell(
          c,
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<List<Json>>(
                  context: context,
                  builder: (_) => HomeShelfEditor(controller: c),
                );
              },
              child: const Text('Open editor'),
            ),
          ),
          scale: 1.25,
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Open editor'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('home-pin-add-likes')));
      await t.tap(find.byKey(const Key('home-pin-add-likes')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('home-pin-genre')));
      await t.enterText(find.byKey(const Key('home-pin-genre')), 'ambient');
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('home-pin-add-mix')));
      await t.tap(find.byKey(const Key('home-pin-add-mix')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await f.screenshot(t, 'parity27-home-editor-320');
      await t.tap(find.byKey(const Key('home-save-shelf')));
      await t.pumpAndSettle();
      expect(result!.map((item) => item['type']).toList(), ['likes', 'mix']);
      expect(result!.last['genre'], 'ambient');
      await f.clean(t, c);
    },
  );
  testWidgets(
    'Personal token clears andopens existingprivate collectionpicker',
    (t) async {
      final c = (await t.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final api = TransferApi(),
            cache = MusicCache(api),
            audio = a.UiAudio(api, cache),
            c = f.LayoutController(api, cache, audio);
        c.preferences = await SharedPreferences.getInstance();
        c.user = WaveUser({
          'id': 'qa-owner',
          'displayName': 'QA',
          'plan': 'beta',
        });
        await c.restoreCustomizationScope();
        await c.customize({'language': 'en', 'reducedMotion': true});
        return c;
      }))!;
      await f.viewport(t, const Size(390, 844));
      await t.pumpWidget(
        a.shell(
          c,
          ProviderImport(controller: c, provider: 'spotify'),
          scale: 1.25,
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('provider-manual-token')));
      await t.tap(find.byKey(const Key('provider-manual-token')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('provider-access-token')));
      await t.enterText(
        find.byKey(const Key('provider-access-token')),
        'qa-personal-token',
      );
      await t.ensureVisible(find.byKey(const Key('provider-save-token')));
      await t.tap(find.byKey(const Key('provider-save-token')));
      await t.pumpAndSettle();
      expect((c.api as TransferApi).tokenChecked, isTrue);
      expect(find.byKey(const Key('provider-access-token')), findsNothing);
      expect(find.text('Original likes'), findsOneWidget);
      expect(t.takeException(), isNull);
      await f.screenshot(t, 'parity27-transfer-390');
      await f.clean(t, c);
    },
  );
  testWidgets(
    'Update banner hasavailable downloading andverifiedready actions at320',
    (t) async {
      final c = (await t.runAsync(a.makeController))!;
      final updater = PreviewUpdater(c.api);
      c.updater = updater;
      await f.viewport(t, const Size(320, 740));
      updater.present(UpdatePhase.available);
      await t.pumpWidget(
        a.shell(
          c,
          Align(
            alignment: Alignment.topCenter,
            child: WaveUpdateNotice(controller: c),
          ),
          scale: 1.25,
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Download'), findsOneWidget);
      await f.screenshot(t, 'parity27-update-available-320');
      updater.present(UpdatePhase.downloading);
      await t.pumpAndSettle();
      expect(find.text('Cancel download'), findsOneWidget);
      expect(find.textContaining('42%'), findsOneWidget);
      expect(t.takeException(), isNull);
      await f.screenshot(t, 'parity27-update-progress-320');
      updater.present(UpdatePhase.ready);
      await t.pumpAndSettle();
      expect(find.text('Install update'), findsOneWidget);
      expect(t.takeException(), isNull);
      await f.clean(t, c);
    },
  );
  testWidgets(
    'Whole main shell capturesdesktop andphone withcontext andshelf',
    (t) async {
      final c = (await t.runAsync(n.fixture))!;
      c.settings['homePins'] = [
        {'id': 'qa-likes', 'type': 'likes'},
        {'id': 'qa-mix', 'type': 'mix', 'genre': 'ambient', 'mood': 'personal'},
      ];
      for (final size in [
        const Size(1760, 1000),
        const Size(1440, 1000),
        const Size(768, 900),
        const Size(390, 844),
        const Size(320, 740),
      ]) {
        await f.viewport(t, size);
        await t.pumpWidget(
          RepaintBoundary(
            key: const Key('capture'),
            child: GlukWaveApp(controller: c),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await f.screenshot(t, 'parity27-home-${size.width.toInt()}');
      }
      await f.clean(t, c);
    },
  );

  testWidgets('Touch longpress wholequeue row lifts andcommitsonce', (t) async {
    final c = (await t.runAsync(queueFixture))!;
    await f.viewport(t, const Size(390, 844));
    await t.pumpWidget(
      a.shell(
        c,
        SingleChildScrollView(
          child: QueuePanel(controller: c, onMore: (_) {}),
        ),
        scale: 1,
      ),
    );
    await t.pumpAndSettle();
    final gesture = await t.startGesture(
      t.getCenter(find.text(c.tracks.first.title)),
      kind: PointerDeviceKind.touch,
    );
    await t.pump(const Duration(milliseconds: 550));
    await gesture.moveBy(const Offset(0, 100));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('queue-lifted-proxy')), findsOneWidget);
    await gesture.up();
    await t.pumpAndSettle();
    expect(c.moves, 1);
    expect(t.takeException(), isNull);
    await f.clean(t, c);
  });

  testWidgets(
    'Recommendation track andartist optout haveundo withoutdeletingmusic',
    (t) async {
      for (final artist in [false, true]) {
        final c = (await t.runAsync(() async {
          SharedPreferences.setMockInitialValues({});
          final api = TransferApi(),
              cache = MusicCache(api),
              audio = a.UiAudio(api, cache),
              c = f.LayoutController(api, cache, audio);
          c.preferences = await SharedPreferences.getInstance();
          c.user = WaveUser({
            'id': 'qa-owner',
            'displayName': 'QA',
            'plan': 'beta',
          });
          await c.restoreCustomizationScope();
          await c.customize({'language': 'en', 'reducedMotion': true});
          c.online = true;
          c.tracks = [
            WaveTrack({
              'id': 'qa-song',
              'title': 'Original test',
              'artist': 'Original artist',
              'source': 'local',
              'duration': 180,
            }),
          ];
          return c;
        }))!;
        await f.viewport(t, const Size(320, 740));
        await t.pumpWidget(
          a.shell(
            c,
            Builder(
              builder: (context) => TextButton(
                onPressed: () => excludeRecommendation(
                  context,
                  c,
                  c.tracks.first,
                  artist: artist,
                ),
                child: const Text('Exclude'),
              ),
            ),
            scale: 1.25,
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.text('Exclude'));
        await t.pumpAndSettle();
        expect(
          find.byKey(const Key('recommendation-undo-notice')),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        await f.screenshot(
          t,
          'parity27-exclude-${artist ? 'artist' : 'track'}-320',
        );
        await t.tap(find.text('Undo'));
        await t.pumpAndSettle();
        expect((c.api as TransferApi).excluded, [
          {'trackId': 'qa-song', 'artist': artist, 'remove': false},
          {'trackId': 'qa-song', 'artist': artist, 'remove': true},
        ]);
        expect(c.tracks.length, 1);
        expect(
          find.byKey(const Key('recommendation-undo-notice')),
          findsNothing,
        );
        expect(t.takeException(), isNull);
        await f.clean(t, c);
      }
    },
  );
}
