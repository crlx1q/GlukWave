import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/appearance.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_layout_test.dart' as layout;
import 'audio_design_test.dart' as audio;
import 'package:glukwave/services/media_button.dart';
import 'package:glukwave/ui/theme.dart';
import 'package:glukwave/ui/studio31.dart';
import 'package:glukwave/ui/profile_crop.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/app.dart';
import 'package:glukwave/l10n/wave_localizations.dart';
import 'home_canvas_test.dart' as f;
import 'helpers/fonts.dart';
import 'helpers/artwork_fixture.dart';

class TransportAudio extends audio.UiAudio {
  final commands = <Json>[];
  TransportAudio(super.api, super.cache);
  @override
  Duration get position => const Duration(seconds: 1);
  @override
  bool get trackLoading => false;
  @override
  Future<void> localCommand(String command, [Json data = const {}]) async {
    commands.add({'command': command, ...data});
  }
}

const dir = '../../docs/verification/2026-10-31/studio/';
const boundary = Key('studio-capture');
Future<void> shot(WidgetTester t, String name) async {
  await t.pump();
  final render = t.renderObject<RenderRepaintBoundary>(find.byKey(boundary));
  await t.runAsync(() async {
    final image = await render
            .toImage(pixelRatio: 1)
            .timeout(const Duration(seconds: 10)),
        data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(dir).create(recursive: true);
    await File('$dir$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> configure(
  WidgetTester t,
  f.CanvasController c,
  Map<String, dynamic> patch,
) async {
  bool done = false;
  Object? error;
  unawaited(
    c
        .customize(patch)
        .then(
          (_) => done = true,
          onError: (Object value) {
            error = value;
            done = true;
          },
        ),
  );
  for (var i = 0; i < 20 && !done; i++) {
    await t.pump(const Duration(milliseconds: 100));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(error, isNull);
  expect(
    done,
    true,
    reason: 'Preference edit must finish without blocked fake-time I/O',
  );
}

Widget shell(f.CanvasController c, Widget child, {String mode = 'dark'}) =>
    RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ru'),
        supportedLocales: WaveStrings.supportedLocales,
        localizationsDelegates: WaveStrings.delegates,
        theme: buildWaveTheme(
          c.customization.merge({'theme': mode}),
          mode == 'light' ? Brightness.light : Brightness.dark,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
Future<void> size(WidgetTester t, double width, double height) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(width, height);
  await t.binding.setSurfaceSize(Size(width, height));
}

Future<void> frames(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 650));
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
  tearDown(clearArtworkFixture);
  test(
    'Studio portable settings preserve sparse wallpaper siblings and bound saved themes',
    () {
      final state = WaveCustomization.fromSettings({
        'wallpaper': {'url': '/api/profile-assets/own', 'dim': .25, 'blur': 6},
        'powerSaving': true,
        'savedThemes': [
          {
            'id': 'own',
            'name': 'Evening',
            'mode': 'dark',
            'colors': WavePalette.dark.toJson(),
          },
          {'id': 'bad', 'name': '', 'mode': 'dark', 'colors': {}},
        ],
        'appearance': {'miniBackground': 'pixels'},
      });
      final changed = state.merge({
        'wallpaper': {'dim': .6},
      });
      expect(changed.wallpaper, {
        'url': '/api/profile-assets/own',
        'dim': .6,
        'blur': 6.0,
      });
      expect(
        presentationPatch({
          'wallpaper': {'dim': .6},
        }, changed),
        {
          'wallpaper': {'dim': .6},
        },
      );
      expect(changed.savedThemes.length, 1);
      expect(changed.powerSaving, true);
      expect(changed.appearance.miniBackground, 'pixels');
      expect(
        normalizeWallpaper({
          'url': 'https://wrong.test/image',
          'blur': 99,
          'dim': -1,
        }),
        {'url': '', 'blur': 24, 'dim': 0},
      );
      expect(studioPalettes.length, 8);
      expect(
        requiresAdvancedAppearance({
          'appearance': {'miniBackground': 'pixels'},
        }),
        false,
      );
      expect(
        buildWaveTheme(
          state.merge({
            'theme': 'amoled',
            'appearance': {
              'amoled': {'bg': '#333333'},
            },
          }),
          Brightness.dark,
        ).scaffoldBackgroundColor,
        Colors.black,
      );
    },
  );
  testWidgets(
    'Media toggle resolves single double triple once and cancels scope/dispose',
    (t) async {
      final calls = <int>[];
      final gesture = MediaButtonGesture((count) async {
        calls.add(count);
      });
      gesture.press('a');
      await t.pump(const Duration(milliseconds: 351));
      expect(calls, [1]);
      gesture.press('a');
      await t.pump(const Duration(milliseconds: 80));
      gesture.press('a');
      await t.pump(const Duration(milliseconds: 351));
      expect(calls, [1, 2]);
      for (var i = 0; i < 3; i++) {
        gesture.press('a');
        await t.pump(const Duration(milliseconds: 70));
      }
      await t.pump(const Duration(milliseconds: 351));
      expect(calls, [1, 2, 3]);
      gesture.press('a');
      gesture.press('b');
      await t.pump(const Duration(milliseconds: 351));
      expect(calls, [1, 2, 3, 1]);
      gesture.press('b');
      gesture.dispose();
      await t.pump(const Duration(seconds: 1));
      expect(calls.length, 4);
    },
  );
  testWidgets(
    'Previous first restarts even at1second, repeated press and explicit hop bypass restart',
    (t) async {
      final fixture = (await t.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final api = layout.LayoutApi(),
            support = await Directory.systemTemp.createTemp('studio-prev-');
        final cache = MusicCache(api, supportDirectory: () async => support),
            output = TransportAudio(api, cache),
            c = layout.LayoutController(api, cache, output);
        c.preferences = await SharedPreferences.getInstance();
        return (controller: c, output: output, support: support);
      }))!;
      final c = fixture.controller,
          output = fixture.output,
          support = fixture.support;
      output.current = WaveTrack({
        'id': 'one',
        'title': 'First',
        'source': 'local',
      });
      output.tracks = [output.current!];
      await output.skipToPrevious();
      expect(output.commands, [
        {'command': 'seek', 'position': 0},
      ]);
      await output.skipToPrevious();
      expect(output.commands.last, {'command': 'previous', 'restart': false});
      output.current = WaveTrack({
        'id': 'two',
        'title': 'Second',
        'source': 'local',
      });
      await c.transport('previous');
      expect(output.commands.last, {'command': 'seek', 'position': 0});
      await c.transport('previous', {'restart': false});
      expect(output.commands.last, {'command': 'previous', 'restart': false});
      await layout.clean(t, c);
      await t.runAsync(() => support.delete(recursive: true));
    },
  );
  testWidgets(
    'Windows media registration is scoped and unregistered without counting explicit commands',
    (t) async {
      final toggles = <bool>[], events = <int>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(WindowsMediaButton.channel, (
        call,
      ) async {
        toggles.add(call.arguments as bool);
        return call.arguments;
      });
      final bridge = WindowsMediaButton((count) async {
        events.add(count);
      });
      await bridge.update(false, 'idle');
      expect(toggles, isEmpty);
      await bridge.update(true, 'trackA');
      expect(toggles, [true]);
      Future<void> press() async {
        await messenger.handlePlatformMessage(
          WindowsMediaButton.channel.name,
          WindowsMediaButton.channel.codec.encodeMethodCall(
            const MethodCall('press'),
          ),
          (_) {},
        );
      }

      await press();
      await bridge.update(true, 'trackB');
      await t.pump(const Duration(milliseconds: 351));
      expect(events, isEmpty);
      await press();
      await press();
      await t.pump(const Duration(milliseconds: 351));
      expect(events, [2]);
      await bridge.update(false, 'trackB');
      await press();
      await t.pump(const Duration(milliseconds: 351));
      expect(events, [2]);
      expect(toggles.last, false);
      bridge.dispose();
      await t.pump();
      messenger.setMockMethodCallHandler(WindowsMediaButton.channel, null);
    },
  );
  testWidgets(
    'Studio eight palettes fit320, manual power and saved themes persist',
    (t) async {
      final c = (await t.runAsync(f.fixture))!;
      try {
        await size(t, 320, 900);
        await t.pumpWidget(shell(c, StudioAppearance(controller: c)));
        await frames(t);
        expect(find.text('Энергосбережение'), findsOneWidget);
        for (final preset in studioPalettes) {
          expect(find.byKey(Key('studio-preset-${preset.id}')), findsOneWidget);
        }
        expect(t.takeException(), isNull);
        await shot(t, 'native-studio-320-dark');
        await t.tap(find.byKey(const Key('studio-power-saving')));
        await frames(t);
        expect(c.customization.powerSaving, true);
        await configure(t, c, {
          'savedThemes': [
            {
              'id': 'mine',
              'name': 'My studio',
              'mode': 'dark',
              'colors': WavePalette.dark.toJson(),
            },
          ],
        });
        await t.pumpWidget(shell(c, StudioAppearance(controller: c)));
        await frames(t);
        expect(find.text('My studio'), findsOneWidget);
        await configure(t, c, {'theme': 'light'});
        await size(t, 1440, 1000);
        await t.pumpWidget(
          shell(
            c,
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: StudioAppearance(controller: c),
              ),
            ),
            mode: 'light',
          ),
        );
        await frames(t);
        final heading = t.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text('Атмосфера'),
            matching: find.byType(RichText),
          ),
        );
        expect(
          heading.text.style?.color,
          hexColor(c.customization.appearance.light.ink),
        );
        for (final label in [
          'Энергосбережение',
          'Сохранить свою тему',
          'Выбрать изображение / GIF',
          'My studio',
        ]) {
          final rendered = t.renderObject<RenderParagraph>(
            find.descendant(
              of: find.text(label),
              matching: find.byType(RichText),
            ),
          );
          expect(
            rendered.text.style?.color,
            hexColor(c.customization.appearance.light.ink),
            reason: label,
          );
        }
        expect(
          t
              .widget<OutlinedButton>(
                find.byKey(const Key('studio-save-theme')),
              )
              .onPressed,
          isNotNull,
        );
        expect(
          t
              .widget<OutlinedButton>(
                find.byKey(const Key('studio-wallpaper-upload')),
              )
              .onPressed,
          isNotNull,
        );
        await shot(t, 'native-studio-1440-light');
        expect(t.takeException(), isNull);
      } finally {
        await f.clean(t, c);
      }
    },
  );
  testWidgets(
    'About heart reads Russian and has no repeated animation in power saving',
    (t) async {
      final c = (await t.runAsync(f.fixture))!;
      try {
        await configure(t, c, {'powerSaving': true});
        await size(t, 768, 600);
        await t.pumpWidget(shell(c, const Center(child: AboutHeartbeat())));
        await frames(t);
        expect(find.text('С любовью, GlukWave'), findsOneWidget);
        await t.tap(find.byKey(const Key('about-heartbeat')));
        await frames(t);
        await shot(t, 'native-about-heart');
        expect(t.takeException(), isNull);
      } finally {
        await f.clean(t, c);
      }
    },
  );
  testWidgets(
    'Actual application About route includes heartfelt signature and remains readable',
    (t) async {
      final c = (await t.runAsync(f.fixture))!;
      try {
        await configure(t, c, {
          'powerSaving': true,
          'theme': 'dark',
          'language': 'ru',
        });
        await size(t, 1440, 1000);
        await t.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: GlukWaveApp(controller: c),
          ),
        );
        await frames(t);
        await t.tap(find.byKey(const Key('nav-settings')));
        await frames(t);
        final link = find.byKey(const Key('settings-about'));
        await Scrollable.ensureVisible(t.element(link), alignment: .5);
        await t.pumpAndSettle();
        await t.tap(link);
        await frames(t);
        expect(find.byKey(const Key('about-heartbeat')), findsOneWidget);
        expect(find.text('С любовью, GlukWave'), findsOneWidget);
        await shot(t, 'native-about-full-1440');
        expect(t.takeException(), isNull);
      } finally {
        await f.clean(t, c);
      }
    },
  );
  testWidgets(
    'Profile crop pans zooms and confirms square or3to1 image output',
    (t) async {
      final record = ui.PictureRecorder(), canvas = Canvas(record);
      canvas.drawColor(Colors.blue, BlendMode.src);
      canvas.drawRect(
        const Rect.fromLTWH(200, 0, 200, 200),
        Paint()..color = Colors.orange,
      );
      final image = (await t.runAsync(
        () => record.endRecording().toImage(400, 200),
      ))!;
      for (final avatar in [true, false]) {
        Uint8List? result;
        await size(t, 768, 650);
        await t.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildWaveTheme(
                const WaveCustomization(),
                Brightness.light,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      result = await showDialog<Uint8List>(
                        context: context,
                        builder: (_) =>
                            ProfileCropDialog(image: image, avatar: avatar),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('Open'));
        await frames(t);
        await t.drag(
          find.byKey(const Key('profile-crop-image')),
          const Offset(-30, 0),
        );
        await t.tap(find.byKey(const Key('profile-crop-zoom')));
        await frames(t);
        await shot(t, avatar ? 'native-crop-avatar' : 'native-crop-banner');
        await t.tap(find.text('Done'));
        for (var i = 0; i < 30 && result == null; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await t.pump();
        }
        expect(result, isNotNull);
        final codec = (await t.runAsync(
              () => ui.instantiateImageCodec(result!),
            ))!,
            frame = (await t.runAsync(codec.getNextFrame))!;
        expect(frame.image.width, avatar ? 640 : 1600);
        expect(frame.image.height, avatar ? 640 : 533);
        frame.image.dispose();
        codec.dispose();
        expect(t.takeException(), isNull);
      }
      image.dispose();
      await t.pumpWidget(const SizedBox());
      await t.binding.setSurfaceSize(null);
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
  testWidgets(
    'Real bottom docks retain artwork atmosphere and power saving removes effects',
    (t) async {
      final c = (await t.runAsync(f.fixture))!;
      try {
        await installArtworkFixture();
        c.audio.current = c.tracks.first;
        c.audio.tracks = c.tracks;
        c.audio.current!.json['artwork'] = 'https://fixture.test/coast.jpg';
        for (final width in [390.0, 1440.0]) {
          await size(t, width, 360);
          await configure(t, c, {
            'powerSaving': false,
            'appearance': {'miniBackground': 'cover'},
          });
          await t.pumpWidget(
            shell(c, MiniPlayer(controller: c, onOpen: () {})),
          );
          await frames(t);
          expect(find.byType(MiniAtmosphere), findsOneWidget);
          await shot(t, 'native-mini-cover-${width.round()}');
          expect(t.takeException(), isNull);
        }
        await configure(t, c, {
          'appearance': {'miniBackground': 'pixels'},
        });
        await t.pumpWidget(shell(c, MiniPlayer(controller: c, onOpen: () {})));
        await frames(t);
        await shot(t, 'native-mini-pixels');
        await configure(t, c, {'powerSaving': true});
        await t.pumpWidget(shell(c, MiniAtmosphere(controller: c)));
        await frames(t);
        expect(find.byType(CustomPaint), findsNothing);
        expect(t.takeException(), isNull);
      } finally {
        await f.clean(t, c);
      }
    },
  );
}
