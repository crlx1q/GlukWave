import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'wave_colors.dart';

double _seed(int index) {
  final value = math.sin(index * 127.1 + 311.7) * 43758.5453123;
  return value - value.floor();
}

final _seeds = Float32List.fromList([
  for (var index = 0; index < 4200; index++) ...[
    _seed(index * 4),
    _seed(index * 4 + 1) * 2 - 1,
    _seed(index * 4 + 2) * 1000,
    _seed(index * 4 + 3),
  ],
]);

/// Same folded ribbon field as apps/web/src/wave-silk.ts, adapted from the
/// owner's index(3).html. Eight native batches keep points out of the widget tree.
void drawSilkWave(
  Canvas canvas,
  Size size,
  double phase,
  double energy,
  Color accent,
  Offset pointer,
  double pointerActive, {
  Color background = const Color(0xff141517),
  Offset velocity = Offset.zero,
}) {
  final count = size.width < 500 ? 2400 : 4200;
  final positions = List.generate(8, (_) => <double>[]);
  final t = phase * .24;
  final radius = (size.height * .42).clamp(65, 145);
  for (var index = 0; index < count; index++) {
    final at = index * 4,
        u = _seeds[at].toDouble(),
        v = _seeds[at + 1].toDouble(),
        seed = _seeds[at + 2].toDouble(),
        depth = _seeds[at + 3].toDouble(),
        envelope = math.sin(u * math.pi);
    final fa = math.exp(-math.pow((u - .31) / .13, 2)),
        fb = math.exp(-math.pow((u - .70) / .105, 2));
    final layer = (seed % 3).floor() - 1;
    final cy =
        .62 * math.sin(u * 5.15 + t) +
        .27 * math.sin(u * 12.4 - t * .72) +
        .14 * math.cos(u * 23 + t * .37) +
        .16 * math.sin(u * 7.1 + 1.7) +
        .10 * math.cos(u * 13.7 - 2.2) +
        fa * .48 * math.cos((u - .31) * 14 - t * .18) -
        fb * .55 * math.cos((u - .70) * 17 + t * .24) +
        layer * .13 * math.sin(u * 9.2 + t * .44);
    final span =
        ((.56 * (.48 + .52 * math.sin(u * 8 + 1.2) * math.sin(u * 3.7 - 2)))
                .abs() +
            .10) *
        (.62 + (.5 + .5 * math.sin(u * 4.3 + 2.4)) * .56) *
        (1.48 + energy * .44);
    final angle =
            u * 13.5 + math.sin(u * 7.2 + t) * 1.15 + energy * .24 + layer * .2,
        yy =
            v * span * math.cos(angle) +
            math.sin(seed * 31 + phase * 1.3) * .012,
        zz =
            v * span * math.sin(angle) +
            math.cos(seed * 19 + phase * .9) * .012;
    var x =
            .018 +
            u * .964 +
            envelope *
                (fa * .026 * math.sin((u - .31) * 18 + t * .42) +
                    fb * .020 * math.sin((u - .70) * 24 - t * .36)),
        y = .57 + (cy + yy) * .19;
    final dx = (x - pointer.dx) * size.width,
        dy = (y - pointer.dy) * size.height,
        influence =
            math.exp(-(dx * dx + dy * dy) / (radius * radius)) * pointerActive,
        turn = influence * velocity.distance.clamp(0, 1.8) * 1.05;
    y +=
        (yy * math.cos(turn) - zz * math.sin(turn) - yy) * .19 +
        influence * (pointer.dy - y) * .17 +
        influence * velocity.dy * .025;
    x += influence * velocity.dx * .012 * envelope;
    positions[(depth * 8).floor().clamp(0, 7)].addAll([
      x * size.width,
      y * size.height,
    ]);
  }
  final palette = SilkPalette.from(accent, background);
  final paint = Paint()..strokeCap = StrokeCap.round;
  for (var band = 0; band < positions.length; band++) {
    paint.color = palette
        .atDepth((band + .5) / 8)
        .withValues(alpha: .32 + (band + .5) / 8 * .50);
    paint.strokeWidth = .84 + (band + .5) / 8 * .84;
    canvas.drawRawPoints(
      ui.PointMode.points,
      Float32List.fromList(positions[band]),
      paint,
    );
  }
}
