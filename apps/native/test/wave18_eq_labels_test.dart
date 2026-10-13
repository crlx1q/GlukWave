import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/ui/equalizer_panel.dart';
import 'package:glukwave/ui/equalizer_curve.dart';
import 'wave18_ui_test.dart' as wave18;
import 'audio_design_test.dart' as a;
import 'app_layout_test.dart' as f;
import 'helpers/fonts.dart';
import 'helpers/artwork_fixture.dart';

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
  testWidgets(
    'Native EQ paints complete plus/minus12 at125 percent without changing curve handles',
    (tester) async {
      await installArtworkFixture();
      final c = (await tester.runAsync(wave18.fixture))!;
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
          scale: 1.25,
        ),
      );
      await tester.pumpAndSettle();
      final chart = tester.getRect(find.byKey(const Key('compact-eq-curve'))),
          labels = <Map<String, dynamic>>[];
      for (final axis in [('max', '+12'), ('zero', '0'), ('min', '−12')]) {
        final finder = find.byKey(Key('compact-eq-db-${axis.$1}'));
        final text = tester.widget<Text>(finder),
            paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: finder, matching: find.byType(RichText)),
            );
        final intrinsic = TextPainter(
          text: paragraph.text,
          textDirection: paragraph.textDirection,
          textScaler: paragraph.textScaler,
          maxLines: 1,
        )..layout();
        expect(text.data, axis.$2);
        expect(text.maxLines, 1);
        expect(text.softWrap, false);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(
          intrinsic.width,
          lessThanOrEqualTo(paragraph.size.width + .01),
          reason: 'Every dB glyph must fit the painted paragraph',
        );
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: axis.$2.length),
        );
        expect(boxes, isNotEmpty);
        expect(
          boxes.every((b) {
            final region = tester.getRect(
              find
                  .ancestor(of: finder, matching: find.byType(IgnorePointer))
                  .first,
            );
            final left = paragraph.localToGlobal(Offset(b.left, b.top)),
                right = paragraph.localToGlobal(Offset(b.right, b.bottom));
            return left.dx >= region.left - .01 &&
                right.dx <= region.right + .01 &&
                left.dy >= region.top - .01 &&
                right.dy <= region.bottom + .01;
          }),
          isTrue,
          reason:
              '${axis.$2}: paragraph ${paragraph.size}, intrinsic ${intrinsic.width}, boxes $boxes',
        );
        labels.add({
          'text': text.data,
          'intrinsicWidth': intrinsic.width,
          'paragraphWidth': paragraph.size.width,
          'boxCount': boxes.length,
        });
        intrinsic.dispose();
      }
      final metric = equalizerEditorCurve(
        c.customization.equalizer.bands,
        chart.size,
        c.customization.appearance.radius,
      ).computeMetrics().single;
      for (var i = 0; i < 10; i++) {
        final finder = find.byKey(Key('compact-eq-band-$i')),
            slider = tester.widget<Slider>(finder),
            bounds = tester.getRect(finder);
        expect(slider.padding, const EdgeInsets.symmetric(horizontal: 7));
        final thumb =
            Offset(
              bounds.center.dx,
              bounds.bottom -
                  7 -
                  (bounds.height - 14) * (slider.value + 12) / 24,
            ) -
            chart.topLeft;
        var closest = double.infinity;
        for (var distance = 0.0; distance <= metric.length; distance += .2) {
          final delta =
              (metric.getTangentForOffset(distance)!.position - thumb).distance;
          if (delta < closest) closest = delta;
        }
        expect(
          closest,
          lessThan(.3),
          reason: 'Band$i curve must still intersect actual thumb',
        );
      }
      expect(tester.takeException(), isNull);
      final name =
          'wave18-eq-labels-${DateTime.now().millisecondsSinceEpoch}-375-125';
      await f.screenshot(tester, name);
      final screenshot = 'work/qa/native-$name.png';
      await tester.runAsync(
        () => File('../../work/qa/wave18-eq-labels-proof.json').writeAsString(
          jsonEncode({
            'passed': true,
            'cases': 1,
            'width': 375,
            'height': 900,
            'textScale': 1.25,
            'radius': 38,
            'labels': labels,
            'allTenCurveHandlesUnchanged': true,
            'screenshots': [screenshot],
            'scope':
                'Actual Flutter text layout and paint bounds, isolated widget fixture; no physical device.',
          }),
        ),
      );
      clearArtworkFixture();
      await f.clean(tester, c);
    },
  );
}
