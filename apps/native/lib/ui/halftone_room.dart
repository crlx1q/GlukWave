import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'theme.dart';

/// An original, bounded dot field: two interfering sound rings, no image or
/// external shader. Only this repaint boundary ticks; forms remain stationary.
class HalftoneRoom extends StatefulWidget {
  const HalftoneRoom({super.key});
  @override
  State<HalftoneRoom> createState() => _HalftoneRoomState();
}

class _HalftoneRoomState extends State<HalftoneRoom>
    with SingleTickerProviderStateMixin {
  late final phase = AnimationController(vsync: this, duration: const Duration(seconds: 32));
  final clock = ValueNotifier<double>(0);
  int lastFrame = -1;
  @override
  void initState() {
    super.initState();
    phase.addListener(() {
      final frame = (phase.value * 32 * 24).floor();
      if (frame != lastFrame) { lastFrame = frame; clock.value = phase.value; }
    });
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) || waveVisuals(context).reducedMotion || !TickerMode.of(context)) {
      phase.stop();
    } else if (!phase.isAnimating) {
      phase.repeat();
    }
  }
  @override
  void dispose() { phase.dispose(); clock.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(child: RepaintBoundary(child: CustomPaint(
      painter: _RoomDots(clock, waveVisuals(context).accent),
      child: const SizedBox.expand(),
    ))),
  );
}

class _RoomDots extends CustomPainter {
  final ValueListenable<double> phase;
  final Color pigment;
  _RoomDots(this.phase, this.pigment) : super(repaint: phase);
  @override
  void paint(Canvas canvas, Size size) {
    final step = math.max(14.0, math.max(size.width / 76, size.height / 62));
    final clock = phase.value * math.pi * 2;
    final origin = Offset(size.width * .26, size.height * .48);
    final paint = Paint()..color = pigment.withValues(alpha: .32);
    for (double y = step / 2; y < size.height; y += step) {
      for (double x = step / 2; x < size.width; x += step) {
        final dx = (x - origin.dx) / math.max(1, size.width);
        final dy = (y - origin.dy) / math.max(1, size.height);
        final ring = math.sqrt(dx * dx + dy * dy * .65);
        final wave = (math.sin(ring * 27 - clock) + math.cos((dx - dy) * 13 + clock)) * .25 + .5;
        final envelope = math.exp(-ring * ring * 4.2);
        final radius = (.35 + wave * 3.1) * envelope;
        if (radius > .3) canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }
  @override
  bool shouldRepaint(_RoomDots old) => pigment != old.pigment || phase != old.phase;
}
