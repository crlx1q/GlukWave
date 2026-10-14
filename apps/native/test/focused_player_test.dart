import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/equalizer_panel.dart';
import 'app_layout_test.dart' as f;
import 'audio_design_test.dart' as audio;
import 'helpers/fonts.dart';

Future<void> settlePlayerTest(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pumpAndSettle();
}

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
  for (final theme in ['dark', 'amoled', 'light']) {
    for (final width in [1440.0, 1280.0, 390.0, 320.0]) {
      testWidgets(
        'Focused player $theme $width at125 percent, centered/split, preset menu and themed corners',
        (tester) async {
          final c = (await tester.runAsync(audio.makeController))!;
          final radius = width == 1280 || width == 320 ? 8.0 : 38.0;
          await tester.runAsync(
            () => c.customize({
              'appearance': {'radius': radius, 'cover3d': false},
            }),
          );
          c.settings['lyricsUnderCover'] = false;
          (c.api as f.LayoutApi).lyricSynchronized = true;
          (c.api as f.LayoutApi).lyricLines = [
            for (var i = 0; i < 12; i++)
              {
                'time': i * 12,
                'text': 'The evening takes its time, original line $i',
              },
          ];
          final height = width == 1280 ? 820.0 : 950.0;
          await f.viewport(tester, Size(width, height));
          await tester.pumpWidget(
            audio.shell(
              c,
              PlayerPage(controller: c, onMore: (_) {}),
              mode: theme,
            ),
          );
          await settlePlayerTest(tester);
          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('player-centered-view')), findsOneWidget);
          expect(find.textContaining('original line 0'), findsNothing);
          expect(find.byKey(const Key('player-queue-rail')), findsNothing);
          final cover = tester.getRect(
            find.byKey(const Key('player-cover-gesture')),
          );
          if (width > 1050) {
            // Wide reference layout gives the cover its own column instead of
            // shrinking it above the controls. Both columns stay visible.
            final transport = tester.getRect(
              find.byKey(const Key('player-transport-capsule')),
            );
            expect(cover.right, lessThan(transport.left));
            expect(cover.left, greaterThanOrEqualTo(0));
            expect(transport.right, lessThanOrEqualTo(width));
          } else {
            expect(cover.center.dx, closeTo(width / 2, 1));
          }
          await f.screenshot(
            tester,
            'focused-player-$runId-$theme-${width.toInt()}-centered',
          );
          await tester.tap(find.byKey(const Key('player-lyrics-toggle')));
          await settlePlayerTest(tester);
          expect(find.textContaining('original line 0'), findsOneWidget);
          expect(
            find.byKey(const Key('player-cover-gesture')),
            width >= 851 ? findsOneWidget : findsNothing,
          );
          if (width < 851) {
            expect(
              find.byKey(const Key('lyrics-persistent-controls')),
              findsOneWidget,
            );
          }
          expect(find.byKey(const Key('player-equalizer')), findsOneWidget);
          if (width >= 851) {
            final controls = tester.getRect(
                  find.byKey(const Key('player-equalizer')),
                ),
                pane = tester.getRect(
                  find.byKey(const Key('desktop-lyrics-scroll')),
                );
            expect(controls.right, lessThan(pane.left));
            expect(controls.top, greaterThanOrEqualTo(0));
            expect(controls.bottom, lessThanOrEqualTo(height));
          }
          await f.screenshot(
            tester,
            'focused-player-$runId-$theme-${width.toInt()}-lyrics',
          );
          await tester.tap(find.byKey(const Key('player-queue-toggle')));
          await settlePlayerTest(tester);
          expect(find.textContaining('original line 0'), findsNothing);
          expect(find.text('An original quiet evening 1'), findsOneWidget);
          await tester.tap(find.byKey(const Key('player-queue-toggle')));
          await settlePlayerTest(tester);
          expect(find.byKey(const Key('player-centered-view')), findsOneWidget);
          await tester.ensureVisible(find.byKey(const Key('player-equalizer')));
          await tester.tap(find.byKey(const Key('player-equalizer')));
          await settlePlayerTest(tester);
          final popup = find.byKey(const Key('player-eq-popover'));
          expect(popup, findsOneWidget);
          final rect = tester.getRect(popup);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(rect.bottom, lessThanOrEqualTo(height));
          final shape =
              tester.widget<Material>(popup).shape! as RoundedRectangleBorder;
          expect(
            shape.borderRadius.resolve(TextDirection.ltr).topLeft.x,
            closeTo(radius, .01),
          );
          final chart =
              tester
                      .widget<Container>(
                        find.byKey(const Key('compact-eq-chart')),
                      )
                      .decoration!
                  as BoxDecoration;
          expect(
            chart.borderRadius!.resolve(TextDirection.ltr).topLeft.x,
            closeTo(radius * 18 / 24, .01),
          );
          expect(find.byType(DropdownButtonFormField<String>), findsNothing);
          await tester.tap(find.byKey(const Key('compact-eq-presets')));
          await settlePlayerTest(tester);
          final option = find.byKey(const Key('compact-eq-preset-bass'));
          expect(option, findsOneWidget);
          expect(tester.getRect(option).right, lessThanOrEqualTo(width));
          await f.screenshot(
            tester,
            'focused-player-$runId-$theme-${width.toInt()}-presets',
          );
          await tester.tap(option);
          await settlePlayerTest(tester);
          expect(c.customization.equalizer.bands.first, 5);
          expect(c.customization.equalizer.preamp, -5);
          expect(tester.takeException(), isNull);
          await f.clean(tester, c);
        },
      );
    }
  }
  testWidgets(
    'Native preset keyboard opens/selects without changing track, slider touch overlay is quiet',
    (tester) async {
      final c = (await tester.runAsync(audio.makeController))!;
      await f.viewport(tester, const Size(390, 900));
      await tester.pumpWidget(
        audio.shell(
          c,
          Center(
            child: SizedBox(
              width: 360,
              child: CompactEqualizerPanel(controller: c, onClose: () {}),
            ),
          ),
        ),
      );
      await settlePlayerTest(tester);
      await tester.tap(find.byKey(const Key('compact-eq-presets')));
      await settlePlayerTest(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settlePlayerTest(tester);
      expect(c.audio.current?.id, 'own-0');
      expect(c.customization.equalizer.bands.first, isNot(0));
      final slider = find.byKey(const Key('compact-eq-band-0'));
      final context = tester.element(slider), theme = SliderTheme.of(context);
      expect(theme.overlayColor, Colors.transparent);
      expect(theme.showValueIndicator, ShowValueIndicator.never);
      expect(tester.takeException(), isNull);
      await f.clean(tester, c);
    },
  );
}
