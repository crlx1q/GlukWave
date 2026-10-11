import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/appearance.dart';
import 'package:glukwave/core/equalizer.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/ui/cover_accent.dart';
import 'package:glukwave/ui/equalizer_panel.dart';
import 'package:glukwave/ui/motion_icons.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/theme.dart';
import 'package:glukwave/ui/widgets.dart';
import 'package:glukwave/l10n/audio_design_strings.dart';
import 'package:glukwave/l10n/wave_localizations.dart';
import 'app_layout_test.dart' as fixture;
import 'helpers/fonts.dart';

// UI tests keep the actual controller and preference writer. Only device DSP
// is replaced: these tests never open a physical audio output.
class UiAudio extends WaveAudioHandler {
  WaveEqualizer? applied;
  double? appliedRate;
  UiAudio(super.api, super.cache);
  @override
  bool get equalizerSupported => true;
  @override
  Future<void> applyProcessing(
    WaveEqualizer preference,
    double rate, {
    bool inRoom = false,
  }) async {
    applied = preference;
    appliedRate = rate;
  }
}

Future<fixture.LayoutController> makeController() async {
  SharedPreferences.setMockInitialValues({});
  final api = fixture.LayoutApi(), cache = MusicCache(api);
  final audio = UiAudio(api, cache);
  final c = fixture.LayoutController(api, cache, audio);
  c.preferences = await SharedPreferences.getInstance();
  await c.restoreCustomizationScope();
  await c.customize({
    'reducedMotion': true,
    'language': 'en',
    'equalizer': {'enabled': true},
  });
  c.loading = false;
  final tracks = List.generate(
    3,
    (i) => WaveTrack({
      'id': 'own-$i',
      'title': 'An original quiet evening $i',
      'artist': 'Wave verification',
      'duration': 240,
      'source': 'local',
      'artwork': '',
      'playback': {'kind': 'audio', 'url': '/own.wav'},
    }),
  );
  c.tracks = tracks;
  c.audio.tracks = tracks;
  c.audio.current = tracks.first;
  return c;
}

Widget shell(
  fixture.LayoutController c,
  Widget child, {
  String mode = 'dark',
  double scale = 1.25,
}) => RepaintBoundary(
  key: const Key('capture'),
  child: MaterialApp(
    theme: buildWaveTheme(
      c.customization.merge({'theme': mode}),
      mode == 'light' ? Brightness.light : Brightness.dark,
      coverAccent: const Color(0xffad795d),
    ),
    locale: const Locale('en'),
    supportedLocales: WaveStrings.supportedLocales,
    localizationsDelegates: WaveStrings.delegates,
    builder: (context, page) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
      child: page!,
    ),
    home: Scaffold(body: child),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final runId = DateTime.now().millisecondsSinceEpoch;
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
    'Bounded chromatic sample, contrast, basic auto preference and six translated labels',
    () {
      final pixels = Uint8List.fromList([
        for (var i = 0; i < 80; i++) ...[190, 72, 30, 255],
        for (var i = 0; i < 100; i++) ...[240, 240, 240, 255],
        for (var i = 0; i < 100; i++) ...[0, 0, 255, 0],
      ]);
      final sample = sampleCoverAccent(pixels)!;
      expect(sample.r, closeTo(190 / 255, .001));
      expect(sample.b, closeTo(30 / 255, .001));
      expect(
        sampleCoverAccent(
          Uint8List.fromList([
            for (var i = 0; i < 20; i++) ...[120, 120, 120, 255],
          ]),
        ),
        isNull,
      );
      for (final mode in ['light', 'dark', 'amoled']) {
        final pref = const WaveCustomization().merge({'theme': mode});
        final normal = WaveVisuals.from(
          pref,
          mode == 'light' ? Brightness.light : Brightness.dark,
          coverAccent: sample,
        );
        final high = WaveVisuals.from(
          pref,
          mode == 'light' ? Brightness.light : Brightness.dark,
          coverAccent: sample,
          highContrast: true,
        );
        double ratio(Color a, Color b) {
          final x = a.computeLuminance(), y = b.computeLuminance();
          return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
        }

        expect(
          ratio(normal.accent, normal.background),
          greaterThanOrEqualTo(3),
        );
        expect(ratio(high.accent, high.background), greaterThanOrEqualTo(4.5));
        final manual = pref.merge({
          'appearance': {'coverAccent': false},
        });
        expect(
          WaveVisuals.from(
            manual,
            normal.brightness,
            coverAccent: sample,
          ).accent,
          isNot(normal.accent),
        );
        expect(pref.toSettings()['appearance']['coverAccent'], isTrue);
      }
      expect(
        requiresAdvancedAppearance({
          'appearance': {'coverAccent': true},
        }),
        isFalse,
      );
      for (final labels in audioDesignStrings.values) {
        expect(labels.length, 6);
        expect(labels.toSet().length, 6);
      }
    },
  );
  testWidgets(
    'Tiny image decode returns real colour; canceled cached callback cannot publish',
    (tester) async {
      final result = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 64, 64),
          Paint()..color = const Color(0xffaf4832),
        );
        final image = await recorder.endRecording().toImage(64, 64);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final sampler = CoverAccentSampler(), done = Completer<Color?>();
        sampler.read(
          'own',
          MemoryImage(bytes!.buffer.asUint8List()),
          done.complete,
        );
        final colour = await done.future.timeout(const Duration(seconds: 6));
        var stale = false;
        sampler.read(
          'own',
          MemoryImage(bytes.buffer.asUint8List()),
          (_) => stale = true,
        );
        sampler.cancel();
        await Future<void>.delayed(Duration.zero);
        sampler.dispose();
        return (colour, stale);
      });
      expect(result!.$1!.r, closeTo(175 / 255, .01));
      expect(result.$2, isFalse);
    },
  );
  for (final mode in ['dark', 'amoled', 'light']) {
    for (final width in [320.0, 390.0, 1440.0]) {
      testWidgets(
        'Actual anchored compact EQ fits $mode $width at125 percent font',
        (tester) async {
          final c = (await tester.runAsync(makeController))!;
          await fixture.viewport(tester, Size(width, 900));
          await tester.pumpWidget(
            shell(
              c,
              Align(
                alignment: Alignment.bottomCenter,
                child: Builder(
                  builder: (context) => SizedBox(
                    height: 84,
                    width: double.infinity,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        key: const Key('open-eq'),
                        onPressed: () => showPlayerEqualizer(context, c),
                        icon: const Icon(Icons.graphic_eq_rounded),
                      ),
                    ),
                  ),
                ),
              ),
              mode: mode,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('open-eq')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final rect = tester.getRect(
                find.byKey(const Key('player-eq-popover')),
              ),
              button = tester.getRect(find.byKey(const Key('open-eq')));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(rect.bottom, lessThan(button.top));
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.byType(Slider), findsNWidgets(12));
          expect(
            tester
                .widget<Slider>(find.byKey(const Key('compact-eq-band-0')))
                .max,
            12,
          );
          final chart = tester.getRect(
            find.byKey(const Key('compact-eq-curve')),
          );
          for (final axis in [
            ('max', '+12', chart.top + 24),
            ('zero', '0', chart.center.dy),
            ('min', '−12', chart.bottom - 24),
          ]) {
            final label = find.byKey(Key('compact-eq-db-${axis.$1}'));
            expect(label, findsOneWidget);
            final text = tester.widget<Text>(label),
                bounds = tester.getRect(label);
            expect(text.data, axis.$2);
            expect(text.semanticsLabel, '${axis.$2} dB');
            expect(bounds.left, greaterThanOrEqualTo(rect.left));
            expect(bounds.right, lessThanOrEqualTo(rect.right));
            expect(bounds.top, greaterThanOrEqualTo(rect.top));
            expect(bounds.bottom, lessThanOrEqualTo(rect.bottom));
            expect(bounds.center.dy, closeTo(axis.$3, .1));
            expect(
              tester
                  .widget<IgnorePointer>(
                    find
                        .ancestor(
                          of: label,
                          matching: find.byType(IgnorePointer),
                        )
                        .first,
                  )
                  .ignoring,
              isTrue,
            );
          }
          await fixture.screenshot(
            tester,
            'audio-design-$runId-$mode-$width-eq',
          );
          await tester.tap(find.byTooltip(wt('native.398c7d4f7b')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('player-eq-popover')), findsNothing);
          await fixture.clean(tester, c);
        },
      );
    }
  }
  testWidgets(
    'EQ actions update real controller, processing boundary and persisted custom curve',
    (tester) async {
      final c = (await tester.runAsync(makeController))!;
      await fixture.viewport(tester, const Size(390, 900));
      await tester.pumpWidget(
        shell(
          c,
          Center(
            child: SizedBox(
              width: 380,
              child: CompactEqualizerPanel(controller: c, onClose: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(wt('eq.bass')).last);
      await tester.pumpAndSettle();
      expect(c.customization.equalizer.bands.first, 5);
      expect(c.customization.equalizer.preamp, -5);
      final band = tester.widget<Slider>(
        find.byKey(const Key('compact-eq-band-0')),
      );
      band.onChanged!(12);
      await tester.pumpAndSettle();
      expect(c.customization.equalizer.bands.first, 12);
      tester
          .widget<Slider>(find.byKey(const Key('compact-eq-preamp')))
          .onChanged!(-12);
      tester
          .widget<Slider>(find.byKey(const Key('compact-eq-rate')))
          .onChanged!(1.25);
      await tester.pumpAndSettle();
      expect(c.customization.equalizer.preamp, -12);
      expect(c.customization.playbackRate, 1.25);
      expect((c.audio as UiAudio).applied!.bands.first, 12);
      expect((c.audio as UiAudio).appliedRate, 1.25);
      await tester.tap(find.byTooltip(audioDesignText('savePreset')));
      await tester.pumpAndSettle();
      expect(c.preferences.getString('eq-curve:null'), contains('12.0'));
      await tester.tap(find.byKey(const Key('compact-eq-enabled')));
      await tester.pumpAndSettle();
      expect(c.customization.equalizer.enabled, isFalse);
      expect(
        tester
            .widget<Slider>(find.byKey(const Key('compact-eq-band-0')))
            .onChanged,
        isNull,
      );
      await fixture.clean(tester, c);
    },
  );
  testWidgets('Native volume retains zero / one arc / two arc topology', (
    tester,
  ) async {
    for (final item in [
      (0.0, Icons.volume_off_outlined),
      (.25, Icons.volume_down_outlined),
      (.5, Icons.volume_up_outlined),
      (.75, Icons.volume_up_outlined),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: WaveVolumeIcon(volume: item.$1),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<WaveStateIcon>(find.byType(WaveStateIcon)).icon,
        item.$2,
      );
    }
  });
  testWidgets(
    'Expanded desktop retains cover transport middle lyrics and queue rail',
    (tester) async {
      final c = (await tester.runAsync(makeController))!;
      (c.api as fixture.LayoutApi).lyricLines = [
        for (var i = 0; i < 18; i++)
          {'time': i * 12, 'text': 'A quiet original line $i'},
      ];
      await fixture.viewport(tester, const Size(1440, 950));
      await tester.pumpWidget(
        shell(
          c,
          PlayerPage(controller: c, onMore: (_) {}),
          mode: 'dark',
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('player-queue-rail')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('desktop-lyrics-scroll')),
          matching: find.text('A quiet original line 0'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.byKey(const Key('player-equalizer'))).bottom,
        lessThanOrEqualTo(950),
      );
      expect(find.byKey(const Key('compact-eq-band-0')), findsNothing);
      await fixture.screenshot(tester, 'audio-design-$runId-dark-full-desktop');
      await fixture.clean(tester, c);
    },
  );
}
