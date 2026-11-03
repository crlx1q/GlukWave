import 'package:flutter/material.dart';

/// The same simple provider marks as the web, drawn natively at any scale.
class SourceMark extends StatelessWidget {
  final String provider;
  final Color color;
  final double size;
  const SourceMark({
    super.key,
    required this.provider,
    required this.color,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      key: ValueKey('provider-mark-$provider'),
      dimension: size,
      child: switch (provider) {
        'spotify' ||
        'yandex' => CustomPaint(painter: _SourceMarkPainter(provider, color)),
        'soundcloud' => Icon(Icons.cloud_outlined, color: color, size: size),
        'youtube' => Icon(
          Icons.play_circle_outline_rounded,
          color: color,
          size: size,
        ),
        _ => Icon(Icons.hub_outlined, color: color, size: size),
      },
    ),
  );
}

class _SourceMarkPainter extends CustomPainter {
  final String provider;
  final Color color;
  const _SourceMarkPainter(this.provider, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()..color = color;
    if (provider == 'spotify') {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
        Path()
          ..moveTo(4.5, 8.2)
          ..cubicTo(9.2, 6.8, 14.9, 7.1, 19.5, 9.8)
          ..moveTo(5.5, 12.1)
          ..cubicTo(9.5, 11, 14.4, 11.3, 18, 13.6)
          ..moveTo(6.4, 15.8)
          ..cubicTo(9.7, 15.1, 13.4, 15.3, 16.4, 17.1),
        paint,
      );
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(12, 2)
          ..lineTo(14.5, 8.1)
          ..lineTo(21, 10)
          ..lineTo(15.3, 14.1)
          ..lineTo(16.1, 21)
          ..lineTo(10.9, 16.5)
          ..lineTo(4.5, 20)
          ..lineTo(7.1, 13.6)
          ..lineTo(2, 9)
          ..lineTo(8.7, 8.5)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SourceMarkPainter oldDelegate) =>
      provider != oldDelegate.provider || color != oldDelegate.color;
}
