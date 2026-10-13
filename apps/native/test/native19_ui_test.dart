import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/ui/app.dart';
import 'package:glukwave/ui/native19_guard.dart';
import 'package:glukwave/ui/native19_components.dart';
import 'package:glukwave/ui/native19_saved.dart';
import 'audio_design_test.dart' as audio;
import 'app_layout_test.dart' as base;
import 'helpers/fonts.dart';
import 'helpers/artwork_fixture.dart';

class Native19Api extends base.LayoutApi {
  int lyricsRequests = 0;
  bool commentsFail = false;
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    if (path.endsWith('/lyrics')) lyricsRequests++;
    if (path.endsWith('/comments') && commentsFail) {
      throw const SocketException('Isolated comment outage');
    }
    if (path == '/api/taste') {
      return {
        'taste': {
          'artists': [],
          'genres': ['ambient'],
          'automatic': true,
          'onboardingCompleted': true,
        },
      };
    }
    if (path.startsWith('/api/artists')) {
      return {
        'artists': [
          {
            'id': 'qa-artist',
            'name': 'Wave artist',
            'artwork': 'https://qa.invalid/coast.jpg',
          },
        ],
        'genres': ['ambient'],
      };
    }
    if (path == '/api/recommendations') return {'tracks': []};
    return super.call(path, method: method, data: data, query: query);
  }
}

class Native19Controller extends base.LayoutController {
  Native19Controller(super.api, super.cache, super.audio);
  String? savedPlayed, approved;
  int lookedUp = 0;
  Duration qrLifetime = const Duration(minutes: 1);
  @override
  Future<void> refresh() async {}
  @override
  Future<void> playSaved(WaveTrack track, {List<WaveTrack>? list}) async {
    savedPlayed = track.id;
  }

  @override
  Future<Json> qrInfo(String value) async {
    lookedUp++;
    return {
      'deviceName': 'Wave on Windows',
      'status': 'pending',
      'expiresAt': DateTime.now().add(qrLifetime).toIso8601String(),
    };
  }

  @override
  Future<void> approveQr(String value) async {
    approved = value;
  }
}

Future<Native19Controller> fixture({
  String mode = 'dark',
  double scale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  final api = Native19Api(),
      cache = MusicCache(api),
      out = audio.UiAudio(api, cache),
      c = Native19Controller(api, cache, out);
  c.preferences = await SharedPreferences.getInstance();
  await c.restoreCustomizationScope();
  await c.customize({
    'language': 'ru',
    'theme': mode,
    'reducedMotion': true,
    'fontScale': scale,
    'appearance': {'radius': 28, 'cover3d': true},
  });
  c.loading = false;
  c.online = true;
  c.user = WaveUser({
    'id': 'native19-ui',
    'username': 'wave',
    'displayName': 'Алишер',
    'plan': 'beta',
    'role': 'user',
    'email': 'fixture@example.test',
  });
  c.tracks = List.generate(
    6,
    (i) => WaveTrack({
      'id': 'native19-$i',
      'title': [
        'Там, где тихо',
        'Сквозь облака',
        'Солнечный берег',
        'Снова рядом',
        'Медленный свет',
        'После дождя',
      ][i],
      'artist': i.isEven ? 'Wave artist' : 'Тёплые дни',
      'artwork': 'https://qa.invalid/coast-$i.jpg',
      'source': 'local',
      'duration': 240,
      'playback': {'kind': 'audio', 'url': '/own.wav', 'offline': true},
    }),
  );
  out.tracks = c.tracks;
  out.current = c.tracks.first;
  c.playlists = [
    {
      'id': 'quiet-hours',
      'name': 'Тихий вечер',
      'description': 'Музыка для своих моментов',
      'artwork': c.tracks[1].artwork,
      'trackIds': c.tracks.take(3).map((t) => t.id).toList(),
    },
  ];
  c.likedIds.add(c.tracks.first.id);
  api.lyricSynchronized = true;
  api.lyricLines = [
    for (var i = 0; i < 14; i++)
      {
        'time': i * 12,
        'text': [
          'Там, где тихо — мы услышим море',
          'И увидим свет в твоём окне',
          'Этот миг останется с тобою',
          'Музыка напомнит обо мне',
        ][i % 4],
      },
  ];
  cache.entries = {
    for (var i = 0; i < 3; i++)
      c.tracks[i].id: {
        'track': c.tracks[i].json,
        'manual': i < 2,
        'bytes': 8 * 1024 * 1024,
      },
  };
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final captures = <String>[], checks = <String>[];
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
  tearDownAll(() async {
    await File('../../work/qa/native19-ui-proof.json').writeAsString(
      jsonEncode({
        'passed': false,
        'status': 'awaiting_cli_result',
        'cases': checks.length,
        'checks': checks,
        'screenshots': captures,
        'scope':
            'Actual Flutter widget tree and real controller rendering; isolated catalogue/artwork/audio/camera transport. No physical device or OS-battery verification.',
      }),
    );
  });
  Future<void> shot(WidgetTester tester, String name) async {
    // File and codec completions started in the widget zone need pump turns.
    for (var frame = 0; frame < 8; frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    await base.screenshot(tester, 'native19-$name');
    captures.add('work/qa/native-native19-$name.png');
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> clean(WidgetTester tester, Native19Controller c) async {
    await base.clean(tester, c);
    clearArtworkFixture();
    debugDefaultTargetPlatformOverride = null;
  }

  Future<void> mount(
    WidgetTester tester,
    Native19Controller c,
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

  void cleanExceptions(WidgetTester tester) {
    expect(tester.takeException(), isNull);
  }

  for (final config in [
    (320.0, 568.0, 'light', 1.25),
    (375.0, 812.0, 'dark', 1.0),
    (768.0, 1024.0, 'amoled', 1.0),
    (938.0, 600.0, 'dark', 1.0),
    (1440.0, 900.0, 'dark', 1.0),
  ]) {
    testWidgets(
      'Native branded home/player/lyrics/queue fit ${config.$1} ${config.$3}',
      (tester) async {
        final c = (await tester.runAsync(
          () => fixture(mode: config.$3, scale: config.$4),
        ))!;
        await mount(tester, c, Size(config.$1, config.$2));
        cleanExceptions(tester);
        await shot(tester, '${config.$1.toInt()}-${config.$3}-home');
        await tester.tap(find.byKey(const Key('mini-gesture')));
        await settle(tester);
        cleanExceptions(tester);
        final stage = tester.getRect(
          find.byKey(const Key('album-stage-bounds')),
        );
        expect(stage.top, greaterThanOrEqualTo(0));
        expect(stage.bottom, lessThanOrEqualTo(config.$2));
        await shot(tester, '${config.$1.toInt()}-${config.$3}-player');
        await tester.tap(find.byKey(const Key('player-lyrics-toggle')));
        await settle(tester);
        cleanExceptions(tester);
        expect(find.byKey(const Key('player-play')), findsOneWidget);
        if (config.$1 < 851) {
          expect(find.byKey(const Key('album-stage-bounds')), findsNothing);
          expect(
            find.byKey(const Key('lyrics-persistent-controls')),
            findsOneWidget,
          );
        }
        await shot(tester, '${config.$1.toInt()}-${config.$3}-lyrics');
        await tester.tap(find.byKey(const Key('player-queue-toggle')));
        await settle(tester);
        cleanExceptions(tester);
        await shot(tester, '${config.$1.toInt()}-${config.$3}-queue');
        checks.add(
          'home/player/lyrics/queue ${config.$1}x${config.$2} ${config.$3} scale ${config.$4}',
        );
        await clean(tester, c);
      },
    );
  }
  testWidgets(
    'Saved remains reachable offline, separates pin/cache and selects only saved session',
    (tester) async {
      final c = (await tester.runAsync(fixture))!;
      c.online = false;
      await mount(tester, c, const Size(375, 812));
      cleanExceptions(tester);
      await tester.tap(find.byKey(const Key('nav-library')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('library-saved')));
      await settle(tester);
      cleanExceptions(tester);
      expect(find.byType(NativeSavedView), findsOneWidget);
      expect(find.text('Сохранено тобой'), findsOneWidget);
      expect(find.text('Кеш прослушивания'), findsOneWidget);
      await shot(tester, '375-offline-saved');
      await tester.tap(find.byKey(const Key('saved-play')));
      await settle(tester);
      expect(c.savedPlayed, c.tracks.first.id);
      checks.add('offline saved access/pin/cache/local session');
      await clean(tester, c);
    },
  );
  testWidgets(
    'Phone Guard accepts manual fallback and requires explicit target confirmation',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final c = (await tester.runAsync(fixture))!;
      await mount(tester, c, const Size(375, 812));
      await tester.tap(find.byKey(const Key('mobile-guard')));
      await settle(tester);
      cleanExceptions(tester);
      expect(find.byType(WaveGuardPage), findsOneWidget);
      expect(find.byKey(const Key('guard-scan')), findsOneWidget);
      await shot(tester, '375-guard');
      await tester.tap(find.byKey(const Key('guard-manual')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('guard-manual-code')),
        'own-challenge-code',
      );
      await tester.tap(find.byKey(const Key('guard-inspect')));
      await settle(tester);
      expect(c.lookedUp, 1);
      expect(c.approved, isNull);
      expect(find.text('Wave on Windows'), findsOneWidget);
      await shot(tester, '375-guard-confirm');
      await tester.tap(find.byKey(const Key('guard-approve')));
      await settle(tester);
      expect(c.approved, 'own-challenge-code');
      cleanExceptions(tester);
      checks.add('phone Guard manual/target/explicit approval');
      await clean(tester, c);
    },
  );
  testWidgets(
    'Energy setting is device local and coherent with settings/search/Connect',
    (tester) async {
      final c = (await tester.runAsync(fixture))!;
      await mount(tester, c, const Size(1440, 900));
      await tester.tap(find.byKey(const Key('nav-search')));
      await settle(tester);
      cleanExceptions(tester);
      await shot(tester, '1440-search');
      await tester.tap(find.byKey(const Key('nav-devices')));
      await settle(tester);
      cleanExceptions(tester);
      await shot(tester, '1440-connect');
      await tester.tap(find.byKey(const Key('nav-settings')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('settings-playback')));
      await settle(tester);
      cleanExceptions(tester);
      expect(find.byType(NativeEnergyPanel), findsOneWidget);
      await tester.tap(find.byKey(const Key('energy-mode-on')));
      await settle(tester);
      expect(c.energySaving, isTrue);
      await shot(tester, '1440-settings-energy');
      checks.add('desktop search/Connect/settings/device energy');
      await clean(tester, c);
    },
  );
  testWidgets(
    'Logged-out phone has no displayed QR and retains branded sign-in',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final c = (await tester.runAsync(() => fixture(mode: 'amoled')))!;
      c.user = null;
      await mount(tester, c, const Size(375, 812));
      cleanExceptions(tester);
      expect(find.byKey(const Key('auth-qr')), findsNothing);
      expect(find.byKey(const Key('auth-submit')), findsOneWidget);
      await shot(tester, '375-auth-amoled');
      checks.add('phone sign-in/no display QR');
      await clean(tester, c);
    },
  );
}
