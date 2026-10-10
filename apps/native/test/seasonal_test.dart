import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/appearance.dart';
import 'package:glukwave/services/appearance_store.dart';
import 'package:glukwave/ui/seasonal.dart';
import 'package:glukwave/ui/widgets.dart';
import 'package:glukwave/l10n/wave_localizations.dart';
import 'package:glukwave/l10n/lan_strings.dart';
import 'helpers/fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'Season choice is opt-in, month auto detection and sparse edits preserve choices',
    () {
      const initial = WaveCustomization();
      expect(initial.seasonalEffects.enabled, false);
      final selected = initial.merge({
        'seasonalEffects': {
          'enabled': true,
          'mode': 'rain',
          'intensity': 'normal',
        },
      });
      final toggle = selected.merge({
        'seasonalEffects': {'enabled': false},
      });
      expect(toggle.seasonalEffects.mode, 'rain');
      expect(toggle.seasonalEffects.intensity, 'normal');
      expect(
        presentationPatch({
          'seasonalEffects': {'enabled': false},
        }, toggle),
        {
          'seasonalEffects': {'enabled': false},
        },
      );
      expect(
        requiresAdvancedAppearance({
          'seasonalEffects': {'enabled': true},
        }),
        false,
      );
      for (final month in [1, 2, 12]) {
        expect(
          const WaveSeasonalEffects().resolve(DateTime(2026, month)),
          'snow',
        );
      }
      expect(const WaveSeasonalEffects().resolve(DateTime(2026, 4)), 'rain');
      expect(const WaveSeasonalEffects().resolve(DateTime(2026, 7)), 'sun');
      expect(const WaveSeasonalEffects().resolve(DateTime(2026, 10)), 'leaves');
    },
  );
  test(
    'Guest seasonal settings survive restart and stay separate from another account',
    () async {
      final prefs = await SharedPreferences.getInstance(),
          api = WaveApi('http://127.0.0.1:4000');
      final store = AppearanceStore(api, prefs);
      await store.selectScope(null);
      await store.change({
        'seasonalEffects': {
          'enabled': true,
          'mode': 'leaves',
          'intensity': 'normal',
        },
      });
      await store.flushLocalWrites();
      store.dispose();
      final restored = AppearanceStore(api, prefs);
      await restored.selectScope(null);
      expect(restored.current.seasonalEffects.toJson(), {
        'enabled': true,
        'mode': 'leaves',
        'intensity': 'normal',
      });
      await restored.selectScope('other');
      expect(restored.current.seasonalEffects.enabled, false);
      restored.dispose();
    },
  );
  test(
    'Summer light is diffused, restrained, gently moving and intensity aware',
    () async {
      Future<({int maximum, int covered, List<int> samples})> render(
        double phase,
        String intensity,
        bool dark,
      ) async {
        final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
        SeasonalPainter(
          clock: AlwaysStoppedAnimation(phase),
          mode: 'sun',
          intensity: intensity,
          dark: dark,
          amoled: dark,
          preview: false,
        ).paint(canvas, const Size(320, 640));
        final picture = recorder.endRecording(),
            image = await picture.toImage(320, 640);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var maximum = 0, covered = 0;
        final samples = <int>[];
        for (var i = 3; i < bytes.lengthInBytes; i += 4) {
          final alpha = bytes.getUint8(i);
          maximum = mathMax(maximum, alpha);
          if (alpha > 0) covered++;
          if (i % 400 == 3) samples.add(alpha);
        }
        image.dispose();
        picture.dispose();
        return (maximum: maximum, covered: covered, samples: samples);
      }

      for (final dark in [false, true]) {
        final normal = await render(0, 'normal', dark);
        final subtle = await render(0, 'subtle', dark);
        final moved = await render(.25, 'normal', dark);
        final loop = await render(1, 'normal', dark);
        expect(normal.maximum, inInclusiveRange(9, 39));
        expect(normal.covered, greaterThan(320 * 640 * .6));
        expect(subtle.maximum, lessThan(normal.maximum));
        expect(moved.samples, isNot(equals(normal.samples)));
        expect(loop.samples, equals(normal.samples));
      }
    },
  );
  testWidgets(
    'Seasonal ticker stops/disappears for reduced motion, TickerMode and background; disabled preview stays still',
    (tester) async {
      Widget app({
        bool enabled = true,
        bool ticker = true,
        bool reduced = false,
        bool preview = false,
      }) => MaterialApp(
        theme: buildWaveTheme(const WaveCustomization(), Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: TickerMode(
            enabled: ticker,
            child: SizedBox(
              width: 390,
              height: 844,
              child: SeasonalAtmosphere(
                settings: WaveSeasonalEffects(enabled: enabled, mode: 'snow'),
                preview: preview,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 100));
      SeasonalPainter painter() =>
          tester
                  .widget<CustomPaint>(
                    find.byKey(const Key('seasonal-atmosphere')),
                  )
                  .painter!
              as SeasonalPainter;
      final clock = painter().clock;
      final value = clock.value;
      await tester.pump(const Duration(seconds: 1));
      expect(clock.value, greaterThan(value));
      await tester.pumpWidget(app(ticker: false));
      expect(find.byKey(const Key('seasonal-atmosphere')), findsNothing);
      final stopped = clock.value;
      await tester.pump(const Duration(seconds: 1));
      expect(clock.value, stopped);
      await tester.pumpWidget(app(reduced: true));
      expect(find.byKey(const Key('seasonal-atmosphere')), findsNothing);
      await tester.pumpWidget(app(enabled: false, preview: true));
      final staticClock = painter().clock;
      final staticValue = staticClock.value;
      await tester.pump(const Duration(seconds: 1));
      expect(staticClock.value, staticValue);
      await tester.pumpWidget(app());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(find.byKey(const Key('seasonal-atmosphere')), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byKey(const Key('seasonal-atmosphere')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  for (final language in ['en', 'ru', 'kk', 'uk', 'de', 'es']) {
    testWidgets(
      'Season settings narrow125 percent render and labels $language',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 850);
        await tester.binding.setSurfaceSize(const Size(320, 850));
        final prefs = await SharedPreferences.getInstance(),
            store = AppearanceStore(WaveApi('http://127.0.0.1:4000'), prefs);
        await store.selectScope(null);
        await store.change({'reducedMotion': true});
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('capture-season'),
            child: MaterialApp(
              locale: Locale(language),
              supportedLocales: WaveStrings.supportedLocales,
              localizationsDelegates: WaveStrings.delegates,
              theme: buildWaveTheme(store.current, Brightness.light),
              builder: (ctx, child) => MediaQuery(
                data: MediaQuery.of(
                  ctx,
                ).copyWith(textScaler: const TextScaler.linear(1.25)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: SeasonalSettings(store: store),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final key in [
          'account',
          'cache',
          'invitation',
          'network',
          'limit',
          'busy',
          'room',
        ]) {
          WaveStrings.current = WaveStrings(language);
          expect(lanText(key), isNot(key));
        }
        if (language == 'ru') {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('capture-season')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await File(
              '../../work/qa/native-seasonal-ru320.png',
            ).writeAsBytes(bytes.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        store.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.binding.setSurfaceSize(null);
      },
    );
  }
}

int mathMax(int a, int b) => a > b ? a : b;
