import 'dart:ui';

/// Interpolates the editor through the actual handles, with no gain overshoot.
Path equalizerEditorCurve(List<double> bands, Size size, double radius) {
  final points = List.generate(
    bands.length,
    (i) => Offset(
      size.width * (i + .5) / bands.length,
      7 + (size.height - 14) * (.5 - bands[i].clamp(-12, 12) / 24),
    ),
  );
  final curve = Path();
  if (points.isEmpty) return curve;
  curve.moveTo(points.first.dx, points.first.dy);
  if (points.length == 1) return curve;
  final strength = (radius / 24).clamp(0.0, 1.0);
  if (strength == 0) {
    for (final point in points.skip(1)) {
      curve.lineTo(point.dx, point.dy);
    }
    return curve;
  }
  final spacing = size.width / bands.length;
  final slopes = List.generate(
    points.length - 1,
    (i) => (points[i + 1].dy - points[i].dy) / spacing,
  );
  final tangents = List.generate(
    points.length,
    (i) => i == 0
        ? slopes.first
        : i == points.length - 1
        ? slopes.last
        : slopes[i - 1] * slopes[i] <= 0
        ? 0.0
        : 2 * slopes[i - 1] * slopes[i] / (slopes[i - 1] + slopes[i]),
  );
  for (var i = 0; i < points.length - 1; i++) {
    final start = points[i], end = points[i + 1], diff = end.dy - start.dy;
    final low = start.dy < end.dy ? start.dy : end.dy;
    final high = start.dy > end.dy ? start.dy : end.dy;
    final first =
        (start.dy +
                (diff * (1 - strength) + tangents[i] * spacing * strength) / 3)
            .clamp(low, high);
    final second =
        (end.dy -
                (diff * (1 - strength) + tangents[i + 1] * spacing * strength) /
                    3)
            .clamp(low, high);
    curve.cubicTo(
      start.dx + spacing / 3,
      first,
      end.dx - spacing / 3,
      second,
      end.dx,
      end.dy,
    );
  }
  return curve;
}
