import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/core/parity.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/ui/app.dart';
import 'package:glukwave/ui/album_stage.dart';
import 'package:glukwave/ui/equalizer_panel.dart';
import 'package:glukwave/ui/parity_panels.dart';
import 'package:glukwave/ui/widgets.dart';
import 'audio_design_test.dart' as a;
import 'app_layout_test.dart' as f;
import 'helpers/fonts.dart';
import 'helpers/artwork_fixture.dart';

class Wave18Api extends f.LayoutApi {
  Json taste = {
    'artists': <Json>[],
    'genres': ['electronic'],
    'automatic': true,
    'onboardingCompleted': true,
    'onboardingStep': 3,
  };
  Json? savedTaste;
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    if (path == '/api/taste') {
      if (method == 'PUT') {
        savedTaste = object(data);
        taste = {...taste, ...savedTaste!};
      }
      return {'taste': taste, 'learnedArtists': <Json>[]};
    }
    if (path == '/api/artists') {
      return {
        'artists': <Json>[],
        'genres': ['electronic', 'ambient'],
      };
    }
    if (path == '/api/recommendations') {
      return {
        'tracks': <Json>[],
        'mode': query?['mode'],
        'mood': query?['mood'],
      };
    }
    return super.call(path, method: method, data: data, query: query);
  }
}

class Wave18Controller extends f.LayoutController {
  final requests = <Json>[];
  Completer<void>? waveGate;
  Wave18Controller(super.api, super.cache, super.audio);
  @override
  Future<void> startWave({
    String mood = 'personal',
    String mode = 'personal',
  }) async {
    requests.add({'mode': mode, 'mood': mood});
    if (waveGate != null) await waveGate!.future;
    waveMode = mode;
    waveMood = mood;
    waveActive = true;
    render();
  }
}

Future<Wave18Controller> fixture() async {
  SharedPreferences.setMockInitialValues({});
  final api = Wave18Api(),
      cache = MusicCache(api),
      audio = a.UiAudio(api, cache);
  final c = Wave18Controller(api, cache, audio);
  c.preferences = await SharedPreferences.getInstance();
  await c.restoreCustomizationScope();
  await c.customize({
    'language': 'en',
    'reducedMotion': true,
    'theme': 'dark',
    'equalizer': {'enabled': true},
    'appearance': {'radius': 38, 'cover3d': true},
  });
  c.loading = false;
  c.user = WaveUser({
    'id': 'wave18-ui',
    'username': 'wave',
    'displayName': 'Wave',
    'plan': 'beta',
    'role': 'user',
    'email': 'fixture@example.test',
  });
  c.tracks = [
    WaveTrack({
      'id': 'own-wave18',
      'title': 'A quiet place',
      'artist': 'Wave verification',
      'artwork': 'https://qa.invalid/own-coast.jpg',
      'duration': 240,
      'source': 'local',
      'playback': {'kind': 'audio', 'url': '/own.wav'},
    }),
  ];
  c.audio.tracks = c.tracks;
  c.audio.current = c.tracks.first;
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final stamp = DateTime.now().millisecondsSinceEpoch,
      checks = <String>[],
      captures = <String>[];
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
    clearArtworkFixture();
    await File('../../work/qa/wave18-ui-native-proof.json').writeAsString(
      jsonEncode({
        'passed': checks.length == 5,
        'cases': checks.length,
        'checks': checks,
        'screenshots': captures,
        'scope':
            'Actual Flutter widget rendering/controllers; isolated API/audio output, no physical install.',
      }),
    );
  });
  Future<void> capture(WidgetTester tester, String name) async {
    await f.screenshot(tester, 'wave18-ui-$stamp-$name');
    captures.add('work/qa/native-wave18-ui-$stamp-$name.png');
  }

  for (final width in [375.0, 1440.0]) {
    testWidgets(
      'Native wave separates four modes and mood, uses actual pending logo at $width',
      (tester) async {
        final c = (await tester.runAsync(fixture))!;
        c.waveGate = Completer<void>();
        await f.viewport(tester, Size(width, 900));
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('capture'),
            child: GlukWaveApp(controller: c),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('wave-mode-personal')), findsOneWidget);
        expect(find.byKey(const Key('wave-mode-popular')), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const Key('wave-mode-favorites')),
        );
        await tester.tap(find.byKey(const Key('wave-mode-favorites')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('wave-mood-happy')));
        await tester.tap(find.byKey(const Key('wave-mood-happy')));
        await tester.pumpAndSettle();
        final play = find.descendant(
          of: find.byType(WaveHero),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        );
        await tester.ensureVisible(play);
        await tester.tap(play);
        await tester.pump();
        expect(c.requests.single, {'mode': 'favorites', 'mood': 'happy'});
        expect(
          find.descendant(
            of: find.byType(WaveHero),
            matching: find.byKey(const Key('playback-loading-indicator')),
          ),
          findsOneWidget,
        );
        c.waveGate!.complete();
        await tester.pumpAndSettle();
        expect(c.waveActive, isTrue);
        expect(tester.takeException(), isNull);
        for (final scroll in tester.stateList<ScrollableState>(
          find.byType(Scrollable),
        )) {
          if (scroll.position.axis == Axis.vertical) scroll.position.jumpTo(0);
        }
        await tester.pumpAndSettle();
        await capture(tester, 'home-${width.toInt()}');
        checks.add('Native actual mode/mood + pending state $width');
        clearArtworkFixture();
        await f.clean(tester, c);
      },
    );
  }
  testWidgets(
    'Native genre selector persists controlled favorites and preserves automatic taste',
    (tester) async {
      final c = (await tester.runAsync(fixture))!, parity = WaveParity(c.api);
      await tester.runAsync(parity.refreshTaste);
      await f.viewport(tester, const Size(375, 900));
      await tester.pumpWidget(
        a.shell(c, TastePage(controller: c, parity: parity)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('taste-genre-pop')));
      await tester.tap(find.byKey(const Key('taste-genre-pop')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilterChip>(find.byKey(const Key('taste-genre-pop')))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<FilterChip>(find.byKey(const Key('taste-genre-electronic')))
            .selected,
        isTrue,
      );
      await capture(tester, 'taste-375');
      await tester.ensureVisible(find.byKey(const Key('taste-save')));
      await tester.tap(find.byKey(const Key('taste-save')));
      await tester.pumpAndSettle();
      final saved = (c.api as Wave18Api).savedTaste!;
      expect(saved['genres'], containsAll(['electronic', 'pop']));
      expect(saved['automatic'], isTrue);
      expect(tester.takeException(), isNull);
      checks.add('Native genre save preserves automatic taste');
      parity.dispose();
      clearArtworkFixture();
      await f.clean(tester, c);
    },
  );
  testWidgets(
    'Native EQ curve responds to radius setting without sharp peak at38',
    (tester) async {
      final c = (await tester.runAsync(fixture))!;
      await tester.runAsync(
        () => c.customize({
          'equalizer': {
            'bands': [0, 0, -12, 12, 0, 7, -5, 0, 0, 0],
          },
        }),
      );
      await f.viewport(tester, const Size(375, 900));
      await tester.pumpWidget(
        a.shell(
          c,
          Center(
            child: SizedBox(
              width: 355,
              child: CompactEqualizerPanel(controller: c, onClose: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('compact-eq-curve')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'eq-radius38');
      checks.add('Native actual rounded EQ editor');
      clearArtworkFixture();
      await f.clean(tester, c);
    },
  );
  testWidgets(
    'Native cover reflection follows rotation with fixed artwork size',
    (tester) async {
      final c = (await tester.runAsync(fixture))!;
      await f.viewport(tester, const Size(938, 860));
      await tester.pumpWidget(
        a.shell(
          c,
          Center(
            child: AlbumStage(
              controller: c,
              track: c.tracks.first,
              size: 320,
              playing: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester.getSize(
            find.byKey(const Key('album-front-sleeve')),
          ),
          light = tester
              .widget<DecoratedBox>(
                find.byKey(const Key('album-sunlight-reflection')),
              )
              .decoration;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('album-3d'))),
      );
      await gesture.moveBy(const Offset(60, 10));
      await tester.pump();
      final moved = tester
          .widget<DecoratedBox>(
            find.byKey(const Key('album-sunlight-reflection')),
          )
          .decoration;
      expect(
        (moved as BoxDecoration).gradient,
        isNot((light as BoxDecoration).gradient),
      );
      expect(
        tester.getSize(find.byKey(const Key('album-front-sleeve'))),
        before,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, 'cover-reflection-938');
      checks.add('Native sunlight and fixed cover scene');
      clearArtworkFixture();
      await f.clean(tester, c);
    },
  );
}
