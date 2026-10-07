import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/controller.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/ui/app.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/widgets.dart';
import 'helpers/fonts.dart';

class LayoutApi extends WaveApi {
  Json? savedLyrics;
  Completer<Json>? searchPending, lyricsPending;
  List<Json> lyricLines = [];
  LayoutApi() : super('http://127.0.0.1:4000');
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    if (path.endsWith('/lyrics')) {
      if (method == 'PUT') savedLyrics = object(data);
      if (method == 'GET' && lyricsPending != null) {
        return lyricsPending!.future;
      }
      return {'lines': lyricLines, 'synchronized': false};
    }
    if (path == '/api/search' && searchPending != null) {
      return searchPending!.future;
    }
    if (path.endsWith('/comments')) return {'comments': []};
    return {};
  }
}

class LayoutController extends WaveController {
  LayoutController(super.api, super.cache, super.audio);
  void render() => notifyListeners();
}

Future<LayoutController> controller() async {
  SharedPreferences.setMockInitialValues({});
  final api = LayoutApi(), cache = MusicCache(api);
  final audio = WaveAudioHandler(api, cache);
  final c = LayoutController(api, cache, audio);
  c.preferences = await SharedPreferences.getInstance();
  await c.restoreCustomizationScope();
  await c.customize({'reducedMotion': true, 'language': 'ru'});
  c.loading = false;
  return c;
}

Future<void> viewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
}

Future<void> screenshot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        tester.element(find.byKey(const Key('capture'))).findRenderObject()!
            as RenderRepaintBoundary;
    final bitmap = await boundary.toImage(pixelRatio: 1);
    final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
    final file = File('../../work/qa/native-$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    bitmap.dispose();
  });
}

Future<void> clean(WidgetTester tester, LayoutController c) async {
  await tester.pumpWidget(const SizedBox());
  c.dispose();
  final release = tester.runAsync(
    () => c.audio.release().timeout(const Duration(seconds: 5)),
  );
  await tester.pump();
  await release;
  c.api.dio.close(force: true);
  await tester.binding.setSurfaceSize(null);
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
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
  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    testWidgets(
      'Actual auth, offline Lo-Fi, profile and settings fit width $width without setup copy',
      (tester) async {
        final c = (await tester.runAsync(controller))!;
        await viewport(tester, Size(width, 900));
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('capture'),
            child: GlukWaveApp(controller: c),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('http://'), findsNothing);
        expect(find.textContaining('Firebase'), findsNothing);
        expect(find.textContaining('API'), findsNothing);
        if (width == 390) await screenshot(tester, 'auth-mobile');
        await tester.ensureVisible(find.text('Место для выдоха'));
        await tester.tap(find.text('Место для выдоха'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('lofi-clock')), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (width == 390) await screenshot(tester, 'lofi-mobile');
        await tester.ensureVisible(find.byKey(const Key('lofi-scene-2')));
        await tester.tap(find.byKey(const Key('lofi-scene-2')));
        await tester.pumpAndSettle();
        expect(c.preferences.getInt('lofiScene'), 2);
        await tester.ensureVisible(find.byKey(const Key('lofi-atmos-rain')));
        await tester.tap(find.byKey(const Key('lofi-atmos-rain')));
        await tester.pumpAndSettle();
        expect(c.preferences.getString('lofiAtmosphere'), 'rain');
        await tester.ensureVisible(find.byKey(const Key('lofi-zen')));
        await tester.tap(find.byKey(const Key('lofi-zen')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('lofi-clock')), findsOneWidget);
        expect(find.byKey(const Key('lofi-rain-level')), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('lofi-zen')));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        c.user = WaveUser({
          'id': 'layout-fixture',
          'displayName': 'Слушатель',
          'username': 'listener',
          'email': 'listener@example.test',
          'plan': 'free',
        });
        c.render();
        await tester.pumpAndSettle();
        expect(find.text('Моя волна'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (width == 390 || width == 1280) {
          await screenshot(tester, 'home-${width.toInt()}');
        }
        await tester.tap(find.byKey(const Key('profile-link')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Твой маленький мир'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Настройки').last);
        await tester.tap(find.text('Настройки').last);
        await tester.pumpAndSettle();
        expect(find.textContaining('В твоём ритме'), findsOneWidget);
        expect(find.text('Сервер'), findsNothing);
        expect(find.textContaining('Firebase'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const Key('settings-appearance')),
        );
        await tester.tap(find.byKey(const Key('settings-appearance')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('open-appearance')));
        await tester.tap(find.byKey(const Key('open-appearance')));
        await tester.pumpAndSettle();
        if (width == 390 || width == 1280) {
          await screenshot(tester, 'appearance-${width.toInt()}');
        }
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Закрыть оформление'));
        await tester.pumpAndSettle();
        for (final value in [
          'playback',
          'storage',
          'connections',
          'notifications',
          'devices',
          'hotkeys',
          'about',
          'account',
        ]) {
          await tester.ensureVisible(find.byKey(Key('settings-$value')));
          await tester.tap(find.byKey(Key('settings-$value')));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Settings $value at $width',
          );
          if (value == 'playback') {
            await tester.tap(find.byKey(const Key('settings-cover-3d')));
            await tester.pumpAndSettle();
            expect(c.customization.appearance.cover3d, isFalse);
            await tester.tap(find.byKey(const Key('settings-cover-cd')));
            await tester.pumpAndSettle();
            expect(c.customization.appearance.coverKind, 'cd');
          }
          if (value == 'hotkeys') {
            await tester.tap(find.byKey(const Key('settings-hotkeys-toggle')));
            await tester.pumpAndSettle();
            expect(c.preferences.getBool('nativeHotkeys'), isFalse);
          }
        }
        if (width == 390 || width == 1280) {
          await screenshot(tester, 'settings-${width.toInt()}');
        }
        await clean(tester, c);
      },
    );
  }

  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    testWidgets(
      'Fullscreen, real bounded queue gestures and scrolling at $width',
      (tester) async {
        final c = (await tester.runAsync(controller))!;
        c.user = WaveUser({'id': 'gesture-fixture', 'username': 'listener'});
        final tracks = List.generate(
          3,
          (index) => WaveTrack({
            'id': 'gesture-$index',
            'title': 'Тестовый трек ${index + 1}',
            'artist': 'Исполнитель',
            'duration': 4800,
            'playback': {'kind': 'audio', 'offline': false},
          }),
        );
        c.tracks = tracks;
        c.audio.tracks = tracks;
        c.audio.current = tracks[1];
        c.audio.mediaItem.add(c.audio.item(tracks[1]));
        c.likedIds = [tracks[1].id];
        final commands = <String>[];
        c.audio.onTransport = (command, payload) async {
          if (command == 'track') {
            final track = tracks.firstWhere(
              (item) => item.id == payload['trackId'],
            );
            commands.add(track.id);
            c.audio.current = track;
            c.audio.mediaItem.add(c.audio.item(track));
            c.render();
          }
          return true;
        };
        (c.api as LayoutApi).lyricLines = List.generate(
          16,
          (index) => {
            'text': 'Настоящая строка текста для проверки прокрутки $index',
          },
        );
        await viewport(tester, Size(width, 900));
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('capture'),
            child: GlukWaveApp(controller: c),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (width < 900) {
          expect(find.byKey(const Key('nav-home')), findsOneWidget);
          expect(find.byKey(const Key('nav-search')), findsOneWidget);
          expect(find.byKey(const Key('nav-library')), findsOneWidget);
          expect(find.byKey(const Key('nav-rooms')), findsNothing);
        }
        if (width == 390) await screenshot(tester, 'v6-mini-mobile');
        await tester.drag(
          find.byKey(const Key('mini-gesture')),
          const Offset(-110, 0),
        );
        await tester.pumpAndSettle();
        expect(c.audio.current!.id, tracks[2].id);
        await tester.drag(
          find.byKey(const Key('mini-gesture')),
          const Offset(-110, 0),
        );
        await tester.pumpAndSettle();
        expect(commands, [tracks[2].id]);
        await tester.drag(
          find.byKey(const Key('mini-gesture')),
          const Offset(110, 0),
        );
        await tester.pumpAndSettle();
        expect(c.audio.current!.id, tracks[1].id);
        final cancelled = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('mini-gesture'))),
        );
        await cancelled.moveBy(const Offset(-100, 0));
        await cancelled.cancel();
        await tester.pumpAndSettle();
        expect(c.audio.current!.id, tracks[1].id);
        final open = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('mini-gesture'))),
        );
        await open.moveBy(const Offset(0, -170));
        await open.moveBy(const Offset(0, -40));
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const Key('full-player')), findsOneWidget);
        expect(
          find.byKey(const Key('player-cover-transition')),
          findsOneWidget,
        );
        await open.up();
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const Key('full-player'))).size,
          Size(width, 900),
        );
        expect(tester.getRect(find.byKey(const Key('full-player'))).top, 0);
        expect(find.text('1:20:00'), findsWidgets);
        expect(tester.takeException(), isNull);
        if (width == 390 || width == 1280) {
          await screenshot(tester, 'v6-player-${width.toInt()}');
        }
        await tester.drag(
          find.byKey(const Key('player-cover-gesture')),
          const Offset(-120, 0),
        );
        await tester.pumpAndSettle();
        expect(c.audio.current!.id, tracks[2].id);
        await tester.tap(find.text('Текст').last);
        await tester.pumpAndSettle();
        final scroll = tester.widget<SingleChildScrollView>(
          find.byKey(const Key('player-content-scroll')),
        );
        expect(scroll.scrollDirection, Axis.vertical);
        await tester.drag(
          find.byKey(const Key('player-content-scroll')),
          const Offset(0, -250),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('full-player')), findsOneWidget);
        await tester.tap(find.text('Трек').last);
        await tester.pumpAndSettle();
        final close = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('player-dismiss-handle'))),
        );
        await close.moveBy(const Offset(0, 190));
        await close.moveBy(const Offset(0, 50));
        await tester.pump();
        expect(
          tester.getRect(find.byKey(const Key('full-player'))).top,
          greaterThan(0),
        );
        await close.up();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('full-player')), findsNothing);
        expect(c.audio.current!.id, tracks[2].id);
        expect(tester.takeException(), isNull);
        await clean(tester, c);
      },
    );
  }

  testWidgets(
    'Search and lyric skeletons follow pending API work, without fake waits',
    (tester) async {
      final c = (await tester.runAsync(controller))!;
      c.user = WaveUser({'id': 'pending-fixture', 'username': 'listener'});
      final api = c.api as LayoutApi;
      api.searchPending = Completer<Json>();
      await viewport(tester, const Size(390, 850));
      await tester.pumpWidget(GlukWaveApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-search')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Запрос');
      await tester.tap(find.byTooltip('Искать'));
      await tester.pump();
      expect(find.byKey(const Key('search-loading')), findsOneWidget);
      expect(find.text('Пока ничего не нашли'), findsNothing);
      api.searchPending!.complete({'tracks': []});
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('search-loading')), findsNothing);
      expect(find.text('Пока ничего не нашли'), findsOneWidget);
      final track = WaveTrack({
        'id': 'pending-track',
        'title': 'Проверка текста',
        'source': 'soundcloud',
      });
      api.lyricsPending = Completer<Json>();
      await tester.pumpWidget(
        MaterialApp(
          theme: waveTheme,
          home: Scaffold(
            body: PlayerPage(
              controller: c,
              initialTrack: track,
              onMore: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Текст'));
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is WaveLoadingList && widget.label == 'Загружаем текст',
        ),
        findsOneWidget,
      );
      expect(find.text('Здесь будут слова'), findsNothing);
      api.lyricsPending!.complete({'lines': [], 'synchronized': false});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Здесь будут слова'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await clean(tester, c);
    },
  );

  testWidgets(
    'External track accepts personal lyrics through the actual mobile editor',
    (tester) async {
      final c = (await tester.runAsync(controller))!;
      c.user = WaveUser({'id': 'layout-fixture', 'username': 'listener'});
      c.online = true;
      final track = WaveTrack({
        'id': 'external-fixture',
        'title': 'Внешний трек',
        'artist': 'Исполнитель',
        'source': 'soundcloud',
        'duration': 200,
      });
      await viewport(tester, const Size(390, 850));
      await tester.pumpWidget(
        MaterialApp(
          theme: waveTheme,
          home: Scaffold(
            body: PlayerPage(
              controller: c,
              initialTrack: track,
              onMore: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Текст'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить текст'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Текст или LRC'),
        '[00:10.00] Моя строка',
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect((c.api as LayoutApi).savedLyrics, {
        'text': '[00:10.00] Моя строка',
      });
      expect(tester.takeException(), isNull);
      await clean(tester, c);
    },
  );
}
