import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/ui/equalizer_curve.dart';

void main() {
  const bands = [0.0, 0.0, -12.0, 12.0, 0.0, 7.0, -5.0, 0.0, 0.0, 0.0];
  test(
    'Actual editor curve preserves endpoints and stays within legal gains',
    () {
      for (final radius in [0.0, 8.0, 24.0, 48.0]) {
        final path = equalizerEditorCurve(bands, const Size(300, 180), radius);
        final metric = path.computeMetrics().single;
        expect(metric.getTangentForOffset(0)!.position.dx, closeTo(15, .01));
        expect(
          metric.getTangentForOffset(metric.length)!.position.dx,
          closeTo(285, .01),
        );
        for (var i = 0; i < 300; i++) {
          final point = metric
              .getTangentForOffset(metric.length * i / 300)!
              .position;
          expect(point.dy, greaterThanOrEqualTo(6.99));
          expect(point.dy, lessThanOrEqualTo(173.01));
        }
      }
    },
  );
  test(
    'User radius changes the interpolated shape without moving exact handles',
    () {
      final sharp = equalizerEditorCurve(bands, const Size(300, 180), 0);
      final soft = equalizerEditorCurve(bands, const Size(300, 180), 24);
      expect(
        soft.computeMetrics().single.length,
        isNot(closeTo(sharp.computeMetrics().single.length, .1)),
      );
      expect(soft.getBounds().left, sharp.getBounds().left);
      expect(soft.getBounds().right, sharp.getBounds().right);
      expect(
        equalizerEditorCurve([], const Size(300, 180), 24).computeMetrics(),
        isEmpty,
      );
    },
  );
}
