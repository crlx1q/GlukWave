import 'dart:math';

import 'package:flutter/material.dart';

class WaveHero extends StatelessWidget {
  const WaveHero({super.key, required this.signal});

  final ValueListenable<double> signal;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: signal,
      builder: (context, value, _) {
        return CustomPaint(
          size: const Size(double.infinity, 120),
          painter: _WavePainter(amplitude: value),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.amplitude});

  final double amplitude;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..shader = const LinearGradient(
        colors: [Color(0xFF5B4DFF), Color(0xFF2AA8F2), Color(0xFFFF5A8A)],
      ).createShader(Offset.zero & size);

    final path = Path();
    final centerY = size.height / 2;
    final amp = (size.height / 3) * (0.4 + amplitude.abs());

    path.moveTo(0, centerY);
    for (double x = 0; x <= size.width; x += 4) {
      final y = centerY + sin((x / size.width) * 4 * pi + amplitude * pi) * amp;
      path.lineTo(x, y);
    }

    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.amplitude != amplitude;
  }
}
