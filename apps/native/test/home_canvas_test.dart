import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/home_layout.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/ui/theme.dart';
import 'package:glukwave/l10n/wave_localizations.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/ui/home_canvas.dart';
import 'package:glukwave/ui/app.dart';
import 'app_layout_test.dart' as f;
import 'audio_design_test.dart' as a;
import 'native19_ui_test.dart' as n;
import 'helpers/fonts.dart';
import 'helpers/artwork_fixture.dart';

class CanvasApi extends f.LayoutApi {
  final patches = <Json>[];
  bool failSave = false;
  int revision = 0;
  Completer<Json>? pendingSave;
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    if (path == '/api/settings' && method == 'PATCH') {
      patches.add(object(data));
      if (failSave) throw StateError('Isolated offline fixture');
      if (pendingSave != null) return pendingSave!.future;
      return {'settings': object(data), 'revision': ++revision};
    }
    if (path == '/api/recommendations') return {'tracks': []};
    return super.call(path, method: method, data: data, query: query);
  }
}

class CanvasController extends f.LayoutController {
  int plays = 0;
  Object? saveError;
  CanvasController(super.api, super.cache, super.audio);
  @override
  Future<void> updateSettings(Json changes) async {
    try {
      await super.updateSettings(changes);
    } catch (error) {
      saveError = error;
      rethrow;
    }
  }

  @override
  Future<void> play(
    WaveTrack item, {
    List<WaveTrack>? list,
    bool preserveWave = false,
  }) async {
    plays++;
  }
}

Future<CanvasController> fixture() async {
  SharedPreferences.setMockInitialValues({});
  final api = CanvasApi()..token = 'isolated-home-account-a';
  final support = await Directory.systemTemp.createTemp('gw-home-canvas-');
  final cache = MusicCache(api, supportDirectory: () async => support),
      audio = a.UiAudio(api, cache);
  final c = CanvasController(api, cache, audio);
  c.preferences = await SharedPreferences.getInstance();
  c.user = WaveUser({
    'id': 'canvas-a',
    'username': 'canvas',
    'displayName': 'Wave',
    'plan': 'beta',
  });
  await c.restoreCustomizationScope();
  await c.customize({'language': 'en', 'reducedMotion': true});
  await c.appearanceStore!.flush();
  api.patches.clear();
  c.loading = false;
  c.online = true;
  c.tracks = List.generate(
    8,
    (i) => WaveTrack({
      'id': 'canvas-$i',
      'title': 'Quiet coast $i',
      'artist': 'Studio sessions',
      'artwork': '',
      'source': 'local',
      'duration': 210,
    }),
  );
  c.playlists = [
    {
      'id': 'owned',
      'name': 'After midnight',
      'trackIds': c.tracks.take(4).map((t) => t.id).toList(),
    },
  ];
  return c;
}

List<Json> smallWidgets() => [
  {'id': 'likes', 'type': 'likes', 'size': 'small', 'view': 'compact'},
  {
    'id': 'mix',
    'type': 'mix',
    'genre': 'ambient',
    'mood': 'personal',
    'size': 'small',
    'view': 'compact',
  },
  {'id': 'recent', 'type': 'recent', 'size': 'large', 'view': 'list'},
];
Widget canvas(CanvasController c, {String mode = 'dark'}) => RepaintBoundary(
  key: const Key('capture'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildWaveTheme(
      c.customization.merge({'theme': mode}),
      mode == 'light' ? Brightness.light : Brightness.dark,
    ),
    locale: const Locale('en'),
    supportedLocales: WaveStrings.supportedLocales,
    localizationsDelegates: WaveStrings.delegates,
    builder: (context, page) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(1.25), disableAnimations: true),
      child: page!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: NativeHomeCanvas(
            controller: c,
            waveBuilder: (_) => const SizedBox(
              key: Key('actual-wave'),
              height: 150,
              child: Text('My Wave'),
            ),
            recommendations: c.tracks,
            onRetry: () {},
            onLikes: () {},
            onCreatePlaylist: () {},
            onPlaylist: (_) {},
          ),
        ),
      ),
    ),
  ),
);
Future<void> edit(WidgetTester t) async {
  await t.tap(find.byKey(const Key('home-canvas-edit')));
  await t.pumpAndSettle();
}

Future<void> finishSave(WidgetTester t) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await t.pump();
    if (find.byKey(const Key('home-canvas-save')).evaluate().isEmpty) return;
  }
  fail('Save did not finish within the bounded real storage wait.');
}

Future<void> shot(WidgetTester t, String name) async {
  for (var frame = 0; frame < 8; frame++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await t.pump();
  }
  await f.screenshot(t, name);
}

Future<void> option(WidgetTester t, String id, String label) async {
  await t.ensureVisible(find.byKey(Key('home-canvas-options-$id')));
  await t.tap(find.byKey(Key('home-canvas-options-$id')));
  await t.pumpAndSettle();
  final checked = find.ancestor(
    of: find.text(label).last,
    matching: find.byType(CheckedPopupMenuItem<String>),
  );
  final plain = find.ancestor(
    of: find.text(label).last,
    matching: find.byType(PopupMenuItem<String>),
  );
  await t.tap(checked.evaluate().isNotEmpty ? checked.first : plain.first);
  await t.pumpAndSettle();
}

Future<void> clean(WidgetTester tester, f.LayoutController c) async {
  final support = c is CanvasController
      ? await tester.runAsync(c.cache.supportDirectory)
      : null;
  await f.clean(tester, c);
  if (support != null) {
    await tester.runAsync(() => support.delete(recursive: true));
  }
  clearArtworkFixture();
}

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
  test(
    'Default hierarchy, safe legacy ids, explicit empty and malformed cache recovery',
    () {
      final defaults = defaultHomeCanvas([
        for (var i = 0; i < 3; i++) {'id': 'x' * 100, 'type': 'likes'},
      ]);
      expect(defaults.take(2).map((w) => w['type']), ['wave', 'playlists']);
      expect(defaults.map((w) => w['id']).toSet().length, defaults.length);
      expect(
        defaults.every((w) => RegExp(r'^[\w-]{1,80}$').hasMatch(w['id'])),
        true,
      );
      expect(resolveHomeCanvas({'version': 1, 'widgets': []}), isEmpty);
      expect(
        resolveHomeCanvas({
          'version': 1,
          'widgets': [
            {'type': 'invalid'},
          ],
        }).first['type'],
        'wave',
      );
      final normalized = resolveHomeCanvas({
        'version': 1,
        'widgets': [
          {'id': '-safe', 'type': 'wave', 'size': 'large', 'view': 'cards'},
          {'id': 'duplicate', 'type': 'wave', 'size': 'small', 'view': 'list'},
          {
            'id': 'missing',
            'type': 'playlist',
            'playlistId': 'deleted',
            'size': 'small',
            'view': 'compact',
          },
        ],
      }, ownedPlaylists: {});
      expect(normalized.length, 2);
      expect(normalized.last['playlistId'], 'deleted');
      expect(homeCanvasWidth(1000, 'small'), closeTo((1000 - 32) / 3, .01));
      expect(homeCanvasWidth(320, 'small'), 152);
      expect(homeCanvasWidth(320, 'medium'), 320);
    },
  );
  testWidgets(
    'Default Wave then playlists; no shelf/day above it and no migration patch',
    (t) async {
      final c = (await t.runAsync(fixture))!;
      await f.viewport(t, const Size(390, 844));
      await t.pumpWidget(canvas(c));
      await t.pumpAndSettle();
      expect(
        t.getTopLeft(find.byKey(const Key('actual-wave'))).dy,
        lessThan(t.getTopLeft(find.text('Your playlists')).dy),
      );
      expect((c.api as CanvasApi).patches, isEmpty);
      expect(c.settings['homeLayout'], isNull);
      expect(t.takeException(), isNull);
      await clean(t, c);
    },
  );
  testWidgets(
    'Inline resize and views are real, Cancel/Escape/Reset produce no patch; Done once persists',
    (t) async {
      final c = (await t.runAsync(fixture))!, api = c.api as CanvasApi;
      c.settings['homeLayout'] = homeCanvasSettings(smallWidgets());
      await f.viewport(t, const Size(1000, 900));
      await t.pumpWidget(canvas(c));
      await t.pumpAndSettle();
      await edit(t);
      final before = t
          .getSize(find.byKey(const ValueKey('canvas-likes')))
          .width;
      await option(t, 'likes', 'Large');
      expect(
        t.getSize(find.byKey(const ValueKey('canvas-likes'))).width,
        greaterThan(before * 2),
      );
      await option(t, 'recent', 'Covers');
      expect(api.patches, isEmpty);
      await t.tap(find.byKey(const Key('home-canvas-cancel')));
      await t.pumpAndSettle();
      expect(
        t.getSize(find.byKey(const ValueKey('canvas-likes'))).width,
        closeTo(before, 1),
      );
      await edit(t);
      await t.tap(find.byKey(const Key('home-canvas-reset')));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(api.patches, isEmpty);
      await edit(t);
      await option(t, 'likes', 'Medium');
      await t.tap(find.byKey(const Key('home-canvas-save')));
      await finishSave(t);
      expect(api.patches.length, 1);
      expect(
        object(api.patches.single['homeLayout'])['widgets'][0]['size'],
        'medium',
      );
      expect(object(c.settings['homeLayout'])['widgets'][0]['size'], 'medium');
      expect(t.takeException(), isNull);
      await clean(t, c);
    },
  );
  testWidgets(
    'Reset only writes null on Done, retains pins, and late account A save cannot overwrite B',
    (t) async {
      final c = (await t.runAsync(fixture))!, api = c.api as CanvasApi;
      c.settings['homePins'] = [
        {'id': 'kept', 'type': 'likes'},
      ];
      c.settings['homeLayout'] = homeCanvasSettings(smallWidgets());
      await f.viewport(t, const Size(390, 844));
      await t.pumpWidget(canvas(c));
      await t.pumpAndSettle();
      await edit(t);
      await t.tap(find.byKey(const Key('home-canvas-reset')));
      await t.pumpAndSettle();
      expect(api.patches, isEmpty);
      await t.tap(find.byKey(const Key('home-canvas-save')));
      await finishSave(t);
      expect(api.patches.single, {'homeLayout': null});
      expect(c.settings['homePins'], [
        {'id': 'kept', 'type': 'likes'},
      ]);
      expect(c.settings['homeLayout'], isNull);
      await edit(t);
      api.pendingSave = Completer<Json>();
      await t.tap(find.byKey(const Key('home-canvas-save')));
      await t.pump();
      c.api.token = 'isolated-home-account-b';
      c.user = WaveUser({'id': 'canvas-b', 'displayName': 'Other'});
      c.settings['homeLayout'] = homeCanvasSettings([]);
      c.render();
      await t.pumpAndSettle();
      api.pendingSave!.complete({
        'settings': {'homeLayout': homeCanvasSettings(smallWidgets())},
        'revision': 10,
      });
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pumpAndSettle();
      expect(object(c.settings['homeLayout'])['widgets'], isEmpty);
      expect(find.byKey(const Key('home-canvas-save')), findsNothing);
      expect(api.patches.length, 2);
      expect(t.takeException(), isNull);
      await clean(t, c);
    },
  );
  testWidgets(
    'Mouse X-axis pickup and touch cancel restore draft without playback or writes',
    (t) async {
      final c = (await t.runAsync(fixture))!, api = c.api as CanvasApi;
      c.settings['homeLayout'] = homeCanvasSettings(smallWidgets());
      await f.viewport(t, const Size(390, 844));
      await t.pumpWidget(canvas(c));
      await t.pumpAndSettle();
      await edit(t);
      final first = t.getCenter(
        find.byKey(const Key('home-canvas-grab-likes')),
      );
      final second = t.getCenter(find.byKey(const ValueKey('canvas-mix')));
      final mouse = await t.startGesture(first, kind: PointerDeviceKind.mouse);
      await mouse.moveBy(const Offset(15, 0));
      await t.pump();
      expect(find.byKey(const Key('home-canvas-lifted')), findsOneWidget);
      await mouse.moveTo(second);
      await t.pump(const Duration(milliseconds: 40));
      await mouse.up();
      await t.pumpAndSettle();
      expect(
        t.getTopLeft(find.byKey(const ValueKey('canvas-likes'))).dx,
        greaterThan(t.getTopLeft(find.byKey(const ValueKey('canvas-mix'))).dx),
      );
      final touch = await t.startGesture(
        t.getCenter(find.byKey(const ValueKey('canvas-mix'))),
        kind: PointerDeviceKind.touch,
      );
      await t.pump(const Duration(milliseconds: 430));
      await touch.moveTo(
        t.getCenter(find.byKey(const ValueKey('canvas-likes'))),
      );
      await t.pump();
      await touch.cancel();
      await t.pumpAndSettle();
      expect(
        t.getTopLeft(find.byKey(const ValueKey('canvas-likes'))).dx,
        greaterThan(t.getTopLeft(find.byKey(const ValueKey('canvas-mix'))).dx),
      );
      expect(api.patches, isEmpty);
      expect(c.plays, 0);
      await t.tap(find.byKey(const Key('home-canvas-save')));
      await finishSave(t);
      expect(api.patches.length, 1);
      expect(
        object(api.patches.single['homeLayout'])['widgets'][0]['id'],
        'mix',
      );
      expect(object(c.settings['homeLayout'])['widgets'][0]['id'], 'mix');
      expect(t.takeException(), isNull);
      await clean(t, c);
    },
  );
  testWidgets(
    'Keyboard movement, ordinary touch scrolling, held edge autoscroll and Escape cleanup',
    (t) async {
      final c = (await t.runAsync(fixture))!, api = c.api as CanvasApi;
      c.settings['homeLayout'] = homeCanvasSettings([
        for (var index = 0; index < 16; index++)
          {
            'id': 'tile-$index',
            'type': 'likes',
            'size': 'small',
            'view': 'compact',
          },
      ]);
      await f.viewport(t, const Size(390, 844));
      await t.pumpWidget(canvas(c));
      await t.pumpAndSettle();
      await edit(t);
      await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await t.pumpAndSettle();
      expect(
        t.getTopLeft(find.byKey(const ValueKey('canvas-tile-0'))).dx,
        greaterThan(
          t.getTopLeft(find.byKey(const ValueKey('canvas-tile-1'))).dx,
        ),
      );
      final scroll = t
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final swipe = await t.startGesture(
        t.getCenter(find.byKey(const ValueKey('canvas-tile-1'))),
        kind: PointerDeviceKind.touch,
      );
      await swipe.moveBy(const Offset(0, -90));
      await t.pump(const Duration(milliseconds: 100));
      await swipe.moveBy(const Offset(0, -60));
      await t.pump(const Duration(milliseconds: 40));
      expect(find.byKey(const Key('home-canvas-lifted')), findsNothing);
      await swipe.up();
      await t.pumpAndSettle();
      expect(scroll.pixels, greaterThan(0));
      scroll.jumpTo(0);
      await t.pumpAndSettle();
      final held = await t.startGesture(
        t.getCenter(find.byKey(const ValueKey('canvas-tile-1'))),
        kind: PointerDeviceKind.touch,
      );
      await t.pump(const Duration(milliseconds: 430));
      await held.moveTo(const Offset(180, 760));
      await t.pump(const Duration(milliseconds: 600));
      expect(scroll.pixels, greaterThan(100));
      expect(find.byKey(const Key('home-canvas-lifted')), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(find.byKey(const Key('home-canvas-lifted')), findsNothing);
      await held.up();
      await t.pumpAndSettle();
      expect(api.patches, isEmpty);
      expect(c.plays, 0);
      await t.tap(find.byKey(const Key('home-canvas-cancel')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await clean(t, c);
    },
  );
  testWidgets(
    'Save failure retains draft; remote and account changes cannot commit an old draft',
    (t) async {
      final c = (await t.runAsync(fixture))!, api = c.api as CanvasApi;
      c.settings['homeLayout'] = homeCanvasSettings(smallWidgets());
      await f.viewport(t, const Size(390, 844));
      await t.pumpWidget(canvas(c));
      await t.pumpAndSettle();
      await edit(t);
      await option(t, 'likes', 'Medium');
      api.failSave = true;
      await t.tap(find.byKey(const Key('home-canvas-save')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('home-canvas-error')), findsOneWidget);
      expect(find.byKey(const Key('home-canvas-save')), findsOneWidget);
      c.settings['homeLayout'] = homeCanvasSettings([]);
      c.render();
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('home-canvas-save')))
            .onPressed,
        isNull,
      );
      c.api.token = 'isolated-home-account-b';
      c.user = WaveUser({'id': 'canvas-b', 'displayName': 'Other'});
      c.render();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('home-canvas-save')), findsNothing);
      expect(api.patches.length, 1);
      expect(t.takeException(), isNull);
      await clean(t, c);
    },
  );
  testWidgets(
    'Gallery add/remove, 320px 125% dark/light controls and mixed sizes stay reachable',
    (t) async {
      final c = (await t.runAsync(fixture))!, api = c.api as CanvasApi;
      c.settings['homeLayout'] = homeCanvasSettings(smallWidgets());
      for (final mode in ['dark', 'light']) {
        await f.viewport(t, const Size(320, 840));
        await t.pumpWidget(canvas(c, mode: mode));
        await t.pumpAndSettle();
        await edit(t);
        await t.tap(find.byKey(const Key('home-canvas-add')));
        await t.pumpAndSettle();
        await shot(t, 'home-canvas-gallery-320-$mode');
        await t.tap(find.byKey(const Key('home-canvas-gallery-wave')));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('canvas-native-')), findsNothing);
        await option(t, 'likes', 'Remove');
        expect(find.byKey(const ValueKey('canvas-likes')), findsNothing);
        await t.ensureVisible(find.text('Your home, your rhythm'));
        await t.pumpAndSettle();
        await shot(t, 'home-canvas-editor-320-$mode');
        expect(
          find.byKey(const Key('home-canvas-save')).hitTestable(),
          findsOneWidget,
        );
        await t.tap(find.byKey(const Key('home-canvas-cancel')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
      expect(api.patches, isEmpty);
      await clean(t, c);
    },
  );
  testWidgets(
    'Actual main screen default and mixed canvas captures at 1440/768/390',
    (t) async {
      final c = (await t.runAsync(n.fixture))!;
      for (final width in [1440, 768, 390]) {
        await f.viewport(t, Size(width.toDouble(), 1000));
        await t.pumpWidget(
          RepaintBoundary(
            key: const Key('capture'),
            child: GlukWaveApp(controller: c),
          ),
        );
        await t.pumpAndSettle();
        await shot(t, 'home-canvas-main-default-$width');
        expect(t.takeException(), isNull);
      }
      c.settings['homeLayout'] = homeCanvasSettings([
        {'id': 'wave', 'type': 'wave', 'size': 'medium', 'view': 'cards'},
        {
          'id': 'playlists',
          'type': 'playlists',
          'size': 'medium',
          'view': 'cards',
        },
        {'id': 'likes', 'type': 'likes', 'size': 'small', 'view': 'compact'},
        {
          'id': 'mix',
          'type': 'mix',
          'genre': 'ambient',
          'mood': 'personal',
          'size': 'small',
          'view': 'compact',
        },
        {'id': 'recent', 'type': 'recent', 'size': 'small', 'view': 'list'},
      ]);
      c.render();
      await f.viewport(t, const Size(1440, 1000));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('home-canvas-edit')));
      await t.pumpAndSettle();
      await shot(t, 'home-canvas-main-edit-1440');
      expect(t.takeException(), isNull);
      await clean(t, c);
    },
  );
  tearDownAll(() async {
    final directory = Directory(
      '../../docs/verification/2026-10-19/home-canvas',
    );
    await directory.create(recursive: true);
    for (final file
        in Directory('../../work/qa').listSync().whereType<File>().where(
          (f) =>
              f.path.contains('native-home-canvas-') && f.path.endsWith('.png'),
        )) {
      await file.copy('${directory.path}/${file.uri.pathSegments.last}');
    }
    await File('${directory.path}/native-scope.json').writeAsString(
      jsonEncode({
        'captureType':
            'Actual Flutter widget tree on desktop test harness; narrow width is not Android hardware.',
        'transport':
            'Isolated original music fixtures; no owner credentials or production writes.',
        'sizes': [320, 390, 768, 1440],
        'textScale': 1.25,
      }),
    );
  });
}
