import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/appearance.dart';
import 'package:glukwave/services/appearance_store.dart';
import 'package:glukwave/ui/appearance_panel.dart';
import 'package:glukwave/ui/widgets.dart';
import 'package:glukwave/l10n/wave_localizations.dart';
import 'helpers/fonts.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
  });
  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    testWidgets('Live custom palette and controls fit width $width', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final api = WaveApi('http://127.0.0.1:4000');
      final store = AppearanceStore(api, prefs);
      await store.selectScope(null);
      WaveStrings.current = const WaveStrings('ru');
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 850);
      await tester.binding.setSurfaceSize(Size(width, 850));
      await tester.pumpWidget(
        MaterialApp(
          theme: waveTheme,
          home: Scaffold(body: AppearancePanel(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('theme-dark')));
      await tester.pumpAndSettle();
      final surface = find.byType(Surface).first;
      expect(Theme.of(tester.element(surface)).brightness, Brightness.dark);
      expect(
        waveVisuals(tester.element(surface)).background,
        hexColor(WavePalette.dark.bg),
      );
      final accent = find.byKey(const Key('accent-#7ca8bb'));
      await tester.ensureVisible(accent);
      await tester.pumpAndSettle();
      await tester.tap(accent);
      await tester.pumpAndSettle();
      expect(store.current.appearance.dark.accent, '#7ca8bb');
      expect(waveVisuals(tester.element(surface)).accent, hexColor('#7ca8bb'));
      expect(store.current.appearance.light.accent, WavePalette.light.accent);

      final colors = find.byKey(const Key('all-colors'));
      await tester.ensureVisible(colors);
      await tester.tap(find.text('Все цвета'));
      await tester.pumpAndSettle();
      final background = find.descendant(
        of: find.byKey(const ValueKey('bg-editor-dark')),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(background);
      await tester.enterText(background, '#1b2028');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        waveVisuals(tester.element(surface)).background,
        hexColor('#1b2028'),
      );
      await tester.ensureVisible(colors);
      await tester.tap(find.text('Все цвета'));
      await tester.pumpAndSettle();

      for (final key in [
        'compact-toggle',
        'blur-toggle',
        'cover3d-toggle',
        'motion-toggle',
      ]) {
        final target = find.byKey(Key(key));
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(store.current.appearance.compact, isTrue);
      expect(store.current.appearance.blur, isFalse);
      expect(store.current.appearance.cover3d, isFalse);
      expect(store.current.reducedMotion, isTrue);
      expect(waveVisuals(tester.element(surface)).compact, isTrue);
      final particles = find.byKey(const Key('wave-particles'));
      await tester.ensureVisible(particles);
      await tester.tap(particles);
      await tester.pumpAndSettle();
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<WavePainter>()
          .single;
      expect(painter.style, 'particles');
      expect(painter.accentColor, hexColor('#7ca8bb'));

      final reset = find.byKey(const Key('reset-appearance'));
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(store.current.appearance.dark.toJson(), WavePalette.dark.toJson());
      expect(
        store.current.appearance.light.toJson(),
        WavePalette.light.toJson(),
      );
      expect(store.current.appearance.compact, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      api.dio.close(force: true);
      await tester.binding.setSurfaceSize(null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets(
    'System mode follows OS brightness and custom corners/density apply to real components',
    (tester) async {
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      SharedPreferences.setMockInitialValues({});
      final api = WaveApi('http://127.0.0.1:4000');
      final store = AppearanceStore(api, await SharedPreferences.getInstance());
      await store.selectScope(null);
      await store.change({
        'theme': 'system',
        'appearance': {'radius': 38, 'compact': true},
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppearancePanel(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      final surface = find.byType(Surface).first,
          context = tester.element(find.byType(Surface).first);
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(Theme.of(context).visualDensity, VisualDensity.compact);
      final container = tester.widget<Container>(
        find.descendant(of: surface, matching: find.byType(Container)).first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, hexColor(WavePalette.dark.surface));
      expect(
        (decoration.borderRadius! as BorderRadius).topLeft.x,
        closeTo(38 * 22 / 24, .001),
      );
      expect(container.padding, const EdgeInsets.all(15) * .75);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      api.dio.close(force: true);
    },
  );
}
