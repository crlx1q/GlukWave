import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/ui/volume_slider.dart';
import 'package:glukwave/l10n/wave_localizations.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Manrope',
    )..addFont(rootBundle.load('assets/fonts/Manrope-Regular.ttf'))).load();
  });
  test(
    'automatic Kazakh resolves Russian; explicitly selected Kazakh is retained',
    () {
      expect(automaticLanguage('kk-KZ'), 'ru');
      expect(supportedLanguage('kk-KZ'), 'kk');
      expect(automaticLanguage('de'), 'de');
    },
  );
  testWidgets(
    'volume wheel moves five percent while keyboard retains two percent, drafts commit once after quiet time',
    (tester) async {
      final previews = <double>[], commits = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: VolumeSlider(
                  value: 0,
                  onPreview: previews.add,
                  onChanged: commits.add,
                ),
              ),
            ),
          ),
        ),
      );
      final point = tester.getCenter(find.byType(Slider));
      for (var i = 0; i < 5; i++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: point,
            scrollDelta: const Offset(0, -120),
          ),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(previews, [.05, .1, .15, .2, .25]);
      expect(commits, isEmpty);
      await tester.pump(const Duration(milliseconds: 300));
      expect(commits, [.25]);
      expect(tester.widget<Slider>(find.byType(Slider)).divisions, isNull);
      tester.widget<Slider>(find.byType(Slider)).focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 300));
      expect(commits.last, closeTo(.27, .00001));
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('volume wheel uses directional five-percent grid and clamps edges', () {
    expect(wheelVolumeStep(.37, -120), .4);
    expect(wheelVolumeStep(.37, 120), .35);
    expect(wheelVolumeStep(1, -120), 1);
    expect(wheelVolumeStep(0, 120), 0);
    expect(wheelVolumeStep(.37, 0), .37);
  });
  testWidgets(
    'volume hint waits one second, follows drafts and leaves no late popup',
    (tester) async {
      var scope = 'pc';
      final commits = <double>[];
      Widget shell() => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 26,
              child: ClipRect(
                child: VolumeSlider(
                  hoverHint: true,
                  scope: scope,
                  value: .5,
                  onChanged: commits.add,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(shell());
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(Slider)));
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.byKey(const Key('volume-thumb-hint')), findsNothing);
      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('50%'), findsOneWidget);
      final oldX = tester
          .getCenter(find.byKey(const Key('volume-thumb-hint')))
          .dx;
      expect(
        tester.getRect(find.byKey(const Key('volume-thumb-hint'))).bottom,
        lessThanOrEqualTo(tester.getCenter(find.byType(Slider)).dy - 5),
      );
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(Slider)),
          scrollDelta: const Offset(0, -120),
        ),
      );
      await tester.pump();
      expect(find.text('55%'), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(const Key('volume-thumb-hint'))).dx,
        greaterThan(oldX),
      );
      scope = 'phone';
      await tester.pumpWidget(shell());
      await tester.pump(const Duration(milliseconds: 300));
      expect(commits, isEmpty);
      expect(find.byKey(const Key('volume-thumb-hint')), findsNothing);
      await mouse.moveTo(Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(Slider)));
      await tester.pump(const Duration(milliseconds: 500));
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('volume-thumb-hint')), findsNothing);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('volume hint anchors actual track at endpoints in both themes at125%', (
    tester,
  ) async {
    final boundaryKey = GlobalKey(), rows = <Map<String, Object>>[];
    final shape = const RoundedRectSliderTrackShape();
    for (final brightness in [Brightness.dark, Brightness.light]) {
      for (final value in [0.0, .5, 1.0]) {
        final theme = ThemeData(
          fontFamily: 'Manrope',
          brightness: brightness,
          sliderTheme: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
            trackShape: shape,
          ),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: theme,
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(800, 600),
                  textScaler: TextScaler.linear(1.25),
                ),
                child: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 200,
                      height: 26,
                      child: ClipRect(
                        child: VolumeSlider(
                          key: ValueKey('$brightness$value'),
                          value: value,
                          hoverHint: true,
                          onChanged: (_) {},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.byType(Slider)));
        await tester.pump(const Duration(milliseconds: 1010));
        await tester.pump(const Duration(milliseconds: 150));
        final box = tester.renderObject<RenderBox>(find.byType(Slider));
        final track = shape.getPreferredRect(
          parentBox: box,
          sliderTheme: theme.sliderTheme,
          isEnabled: true,
          isDiscrete: false,
        );
        final thumb = box.localToGlobal(
          Offset(track.left + track.width * value, track.center.dy),
        );
        final label = tester.getRect(
          find.byKey(const Key('volume-thumb-hint')),
        );
        expect(label.center.dx, closeTo(thumb.dx, .01));
        expect(label.bottom, lessThanOrEqualTo(thumb.dy - 5));
        expect(label.left, greaterThanOrEqualTo(0));
        expect(label.right, lessThanOrEqualTo(800));
        rows.add({
          'theme': brightness.name,
          'value': value,
          'thumbX': thumb.dx,
          'labelX': label.center.dx,
          'gap': thumb.dy - label.bottom,
        });
        if (value == .5) {
          final render =
              boundaryKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await render.toImage(pixelRatio: 1),
                data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '../../docs/verification/2026-10-24/volume/native-volume-${brightness.name}125.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.runAsync(
      () =>
          File(
            '../../docs/verification/2026-10-24/volume/native-volume-geometry.json',
          ).writeAsString(
            jsonEncode({
              'passed': true,
              'scope':
                  'Isolated real VolumeSlider widget, not physical device or full app',
              'cases': rows,
            }),
          ),
    );
  });
}
