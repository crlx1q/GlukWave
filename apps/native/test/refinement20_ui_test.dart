import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/ui/app.dart';
import 'package:glukwave/ui/provider_import.dart';
import 'package:glukwave/ui/album_stage.dart';
import 'audio_design_test.dart' as audio;
import 'app_layout_test.dart' as base;
import 'native19_ui_test.dart' as fixture;
import 'helpers/fonts.dart';
import 'helpers/artwork_fixture.dart';

class ImportApi extends fixture.Native19Api {
  final requests = <Json>[];
  bool rejectFirst = true;
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    if (path == '/api/integrations/spotify/playlists') {
      return {
        'playlists': [
          {
            'id': 'quiet',
            'name': 'Тихий вечер',
            'trackCount': 2,
            'artwork': 'https://qa.invalid/coast.jpg',
          },
        ],
        'liked': {'id': 'liked', 'name': 'Любимые Spotify', 'trackCount': 2},
      };
    }
    if (path.contains('/playlists/') && path.endsWith('/tracks')) {
      return {
        'tracks': [
          {
            'id': query?['cursor'] == null ? 'one' : 'two',
            'sourceId': query?['cursor'] == null
                ? 'external-one'
                : 'external-two',
            'title': query?['cursor'] == null ? 'Первые лучи' : 'Тихий берег',
            'artist': 'Wave artist',
            'artwork': 'https://qa.invalid/coast.jpg',
            'source': 'spotify',
            'duration': 240,
          },
        ],
        'nextCursor': query?['cursor'] == null ? 'page2' : null,
      };
    }
    if (path == '/api/integrations/spotify/import') {
      requests.add(object(data));
      if (rejectFirst) {
        rejectFirst = false;
        throw StateError('Temporary import outage');
      }
      return {
        'playlist': null,
        'imported': 2,
        'deduplicated': 0,
        'tasteSeeded': true,
        'destination': 'likes',
      };
    }
    return super.call(path, method: method, data: data, query: query);
  }
}

Future<fixture.Native19Controller> importFixture() async {
  SharedPreferences.setMockInitialValues({});
  final api = ImportApi(),
      cache = MusicCache(api),
      out = audio.UiAudio(api, cache),
      c = fixture.Native19Controller(api, cache, out);
  c.preferences = await SharedPreferences.getInstance();
  await c.restoreCustomizationScope();
  await c.customize({
    'language': 'ru',
    'theme': 'dark',
    'reducedMotion': true,
    'appearance': {'radius': 28},
  });
  c.user = WaveUser({
    'id': 'import20',
    'username': 'wave',
    'displayName': 'Алишер',
    'plan': 'beta',
    'role': 'user',
  });
  c.loading = false;
  c.online = true;
  return c;
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
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 70)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> decodedSleeve(WidgetTester tester) async {
    final face = find.byKey(const Key('album-front-sleeve'));
    final image = find.descendant(of: face, matching: find.byType(RawImage));
    for (var attempt = 0; attempt < 12; attempt++) {
      if (image.evaluate().isNotEmpty &&
          tester.widget<RawImage>(image.first).image != null) {
        return;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(image, findsWidgets);
    expect(tester.widget<RawImage>(image.first).image, isNotNull);
  }

  Future<void> mount(
    WidgetTester tester,
    fixture.Native19Controller c,
    Size size,
  ) async {
    await base.viewport(tester, size);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('capture'),
        child: GlukWaveApp(controller: c),
      ),
    );
    await settle(tester);
  }

  for (final config in [
    (320.0, 568.0, 'light', 1.25),
    (375.0, 812.0, 'dark', 1.0),
    (938.0, 700.0, 'dark', 1.0),
    (1440.0, 900.0, 'dark', 1.0),
  ]) {
    testWidgets(
      'Refinement20 prominent device and opaque cover fit ${config.$1}',
      (tester) async {
        final c = (await tester.runAsync(
          () => fixture.fixture(mode: config.$3, scale: config.$4),
        ))!;
        await mount(tester, c, Size(config.$1, config.$2));
        expect(find.byKey(const Key('mini-active-device')), findsNothing);
        expect(tester.takeException(), isNull);
        await base.screenshot(tester, 'refinement20-${config.$1.toInt()}-home');
        await tester.tap(find.byKey(const Key('mini-gesture')));
        await settle(tester);
        await decodedSleeve(tester);
        expect(find.byKey(const Key('album-bottom-face')), findsOneWidget);
        expect(find.byKey(const Key('album-inner-face')), findsOneWidget);
        expect(tester.takeException(), isNull);
        final face = tester.getRect(
          find.byKey(const Key('album-front-sleeve')),
        );
        expect(face.top, greaterThanOrEqualTo(0));
        expect(face.bottom, lessThanOrEqualTo(config.$2));
        if (config.$1 == 320) {
          expect(face.height, greaterThanOrEqualTo(130));
          expect(face.width, greaterThanOrEqualTo(130));
          expect(
            find.byKey(const Key('player-compact-lyrics')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('mini-lyric-0')), findsOneWidget);
          expect(find.byKey(const Key('mini-lyric-1')), findsOneWidget);
          expect(find.byKey(const Key('mini-lyric-2')), findsNothing);
          expect(find.byKey(const Key('player-lyrics-toggle')), findsOneWidget);
          final original = tester.getSize(
            find.byKey(const Key('album-stage-bounds')),
          );
          await tester.ensureVisible(find.byKey(const Key('player-play')));
          await settle(tester);
          expect(
            tester.getRect(find.byKey(const Key('player-play'))).bottom,
            lessThanOrEqualTo(config.$2),
          );
          expect(
            tester.getSize(find.byKey(const Key('album-stage-bounds'))),
            original,
          );
          c.settings['lyricsUnderCover'] = false;
          c.render();
          await settle(tester);
          expect(find.byKey(const Key('player-compact-lyrics')), findsNothing);
        }
        await base.screenshot(
          tester,
          'refinement20-${config.$1.toInt()}-player',
        );
        await base.clean(tester, c);
        clearArtworkFixture();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
  testWidgets(
    'Refinement20 import pages, likes destination and idempotent retry remain usable on phone',
    (tester) async {
      final c = (await tester.runAsync(importFixture))!;
      await mount(tester, c, const Size(320, 568));
      unawaited(
        showProviderImport(
          tester.element(find.byType(Scaffold).first),
          c,
          'spotify',
          connected: true,
          publicMode: false,
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Любимые Spotify'));
      await settle(tester);
      expect(find.text('В любимые'), findsOneWidget);
      await tester.tap(find.text('Показать ещё треки'));
      await settle(tester);
      expect(find.byKey(const Key('import-track-two')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await base.screenshot(tester, 'refinement20-320-import');
      await tester.tap(find.text('Перенести в Wave'));
      await settle(tester);
      expect(find.textContaining('Temporary import outage'), findsOneWidget);
      await tester.tap(find.text('Повторить').last);
      await settle(tester);
      final api = c.api as ImportApi;
      expect(api.requests.length, 2);
      expect(api.requests[0]['requestId'], api.requests[1]['requestId']);
      expect(api.requests.last['destination'], 'likes');
      expect(api.requests.last.containsKey('trackIds'), isFalse);
      expect(find.text('Музыка уже в Gluk Wave'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await base.screenshot(tester, 'refinement20-320-import-result');
      await base.clean(tester, c);
      clearArtworkFixture();
    },
  );
  testWidgets(
    'Refinement20 physical sleeve hover extends record and full turn keeps opaque backside',
    (tester) async {
      final c = (await tester.runAsync(fixture.fixture))!;
      await mount(tester, c, const Size(1440, 900));
      await tester.tap(find.byKey(const Key('mini-gesture')));
      await settle(tester);
      final stage = tester.state(find.byType(AlbumStage));
      expect(stage.mounted, isTrue);
      expect(find.byKey(const Key('album-front-sleeve')), findsOneWidget);
      final gesture = tester.widget<GestureDetector>(
        find.byKey(const Key('album-3d')),
      );
      gesture.onLongPressStart!(const LongPressStartDetails());
      gesture.onLongPressMoveUpdate!(
        const LongPressMoveUpdateDetails(
          offsetFromOrigin: Offset(180 / .65, 0),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('album-back-sleeve')), findsOneWidget);
      expect(find.byKey(const Key('album-bottom-face')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await base.screenshot(tester, 'refinement20-backside');
      await base.clean(tester, c);
      clearArtworkFixture();
    },
  );
  testWidgets(
    'Refinement20 equalizer curve and continuous thumb agree during real pointer drag',
    (tester) async {
      final c = (await tester.runAsync(fixture.fixture))!;
      await tester.runAsync(
        () => c.customize({
          'equalizer': {'enabled': true},
        }),
      );
      await mount(tester, c, const Size(1440, 900));
      await tester.tap(find.byKey(const Key('mini-gesture')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('player-equalizer')));
      await settle(tester);
      final band = find.byKey(const Key('compact-eq-band-4'));
      final pointer = await tester.startGesture(tester.getCenter(band));
      await pointer.moveBy(const Offset(0, -50));
      await tester.pump();
      final slider = tester.widget<Slider>(band);
      expect(slider.divisions, isNull);
      expect(slider.value, c.customization.equalizer.bands[4]);
      expect(slider.value, greaterThan(5));
      expect(find.byKey(const Key('compact-eq-curve')), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const Key('compact-eq-curve')),
          matching: find.byType(TweenAnimationBuilder<List<double>>),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await base.screenshot(tester, 'refinement20-equalizer');
      await pointer.up();
      await base.clean(tester, c);
      clearArtworkFixture();
    },
  );
}
