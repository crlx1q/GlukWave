import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'theme.dart';

/// One reversible shape animation shared by every transport surface.
class WavePlayPauseIcon extends StatefulWidget {
  final bool playing;
  final double size;
  final Color? color;
  const WavePlayPauseIcon({
    super.key,
    required this.playing,
    this.size = 26,
    this.color,
  });
  @override
  State<WavePlayPauseIcon> createState() => _WavePlayPauseIconState();
}

class _WavePlayPauseIconState extends State<WavePlayPauseIcon>
    with SingleTickerProviderStateMixin {
  late final motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 230),
    value: widget.playing ? 1 : 0,
  );
  void sync() {
    final target = widget.playing ? 1.0 : 0.0;
    if (waveVisuals(context).reducedMotion ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.of(context)) {
      motion.value = target;
    } else {
      motion.animateTo(target, curve: Curves.easeInOutCubic);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sync();
  }

  @override
  void didUpdateWidget(WavePlayPauseIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    sync();
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedIcon(
    icon: AnimatedIcons.play_pause,
    progress: motion,
    size: widget.size,
    color: widget.color,
  );
}

/// Small state changes have a short settling motion, rather than an endless loop.
class WaveToggleIcon extends StatelessWidget {
  final bool active;
  final IconData activeIcon, inactiveIcon;
  final double size;
  final Color? color;
  const WaveToggleIcon({
    super.key,
    required this.active,
    required this.activeIcon,
    required this.inactiveIcon,
    this.size = 22,
    this.color,
  });
  @override
  Widget build(BuildContext context) => WaveStateIcon(
    state: active,
    icon: active ? activeIcon : inactiveIcon,
    size: size,
    color: color,
  );
}

class WaveStateIcon extends StatelessWidget {
  final Object state;
  final IconData icon;
  final double size;
  final Color? color;
  const WaveStateIcon({
    super.key,
    required this.state,
    required this.icon,
    this.size = 22,
    this.color,
  });
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: Duration(
      milliseconds:
          waveVisuals(context).reducedMotion ||
              MediaQuery.disableAnimationsOf(context) ||
              !TickerMode.of(context)
          ? 0
          : 180,
    ),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeIn,
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(
          begin: .72,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOutBack)).animate(animation),
        child: child,
      ),
    ),
    child: WaveControlIcon(
      icon,
      key: ValueKey(state),
      size: size,
      color: color,
    ),
  );
}

/// The same rounded outline language as the web transport, without a font asset.
class WaveControlIcon extends StatelessWidget {
  final IconData icon;
  final double? size;
  final Color? color;
  const WaveControlIcon(this.icon, {super.key, this.size, this.color});
  static const supported = [
    Icons.skip_previous_rounded,
    Icons.skip_next_rounded,
    Icons.graphic_eq_rounded,
    Icons.volume_up_outlined,
    Icons.volume_off_outlined,
    Icons.shuffle_rounded,
    Icons.repeat_rounded,
    Icons.repeat_one_rounded,
    Icons.settings_rounded,
    Icons.devices_rounded,
  ];
  @override
  Widget build(BuildContext context) {
    if (!supported.contains(icon)) return Icon(icon, size: size, color: color);
    final theme = IconTheme.of(context);
    return SizedBox(
      width: size ?? theme.size ?? 24,
      height: size ?? theme.size ?? 24,
      child: CustomPaint(
        painter: _WaveControlPainter(
          icon,
          color ?? theme.color ?? Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _WaveControlPainter extends CustomPainter {
  final IconData icon;
  final Color color;
  _WaveControlPainter(this.icon, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    void line(double x, double y, double endX, double endY) {
      path.moveTo(x, y);
      path.lineTo(endX, endY);
    }

    if (icon == Icons.skip_previous_rounded ||
        icon == Icons.skip_next_rounded) {
      if (icon == Icons.skip_next_rounded) {
        canvas.translate(24, 0);
        canvas.scale(-1, 1);
      }
      line(5.5, 5.5, 5.5, 18.5);
      path.moveTo(17.7, 6);
      path.lineTo(8.5, 11.4);
      path.quadraticBezierTo(7.6, 12, 8.5, 12.6);
      path.lineTo(17.7, 18);
      path.quadraticBezierTo(18.5, 18.5, 18.5, 17.5);
      path.lineTo(18.5, 6.5);
      path.quadraticBezierTo(18.5, 5.5, 17.7, 6);
      path.close();
    } else if (icon == Icons.graphic_eq_rounded) {
      line(5.5, 4, 5.5, 8);
      line(5.5, 13, 5.5, 20);
      line(12, 4, 12, 14);
      line(12, 19, 12, 20);
      line(18.5, 4, 18.5, 5);
      line(18.5, 10, 18.5, 20);
      for (final r in [
        const Rect.fromLTWH(3.5, 8, 4, 5),
        const Rect.fromLTWH(10, 14, 4, 5),
        const Rect.fromLTWH(16.5, 5, 4, 5),
      ]) {
        path.addRRect(RRect.fromRectAndRadius(r, const Radius.circular(1)));
      }
    } else if (icon == Icons.volume_up_outlined ||
        icon == Icons.volume_off_outlined) {
      path.moveTo(4, 9);
      path.lineTo(7.5, 9);
      path.lineTo(11.5, 5.5);
      path.lineTo(11.5, 18.5);
      path.lineTo(7.5, 15);
      path.lineTo(4, 15);
      path.close();
      if (icon == Icons.volume_off_outlined) {
        line(16.5, 9.5, 21, 14);
        line(21, 9.5, 16.5, 14);
      } else {
        path.moveTo(15.5, 8.5);
        path.cubicTo(18, 10.5, 18, 13.5, 15.5, 15.5);
        path.moveTo(18.5, 5.5);
        path.cubicTo(22.5, 9, 22.5, 15, 18.5, 18.5);
      }
    } else if (icon == Icons.shuffle_rounded) {
      path.moveTo(3.5, 6.5);
      path.lineTo(5.5, 6.5);
      path.cubicTo(10, 6.5, 13.5, 17.5, 18, 17.5);
      path.lineTo(20.5, 17.5);
      line(17.5, 14.5, 20.5, 17.5);
      line(20.5, 17.5, 17.5, 20.5);
      path.moveTo(3.5, 17.5);
      path.lineTo(5.5, 17.5);
      path.cubicTo(7.5, 17.5, 9, 15.5, 10, 14);
      path.moveTo(14, 10);
      path.cubicTo(15.5, 7.8, 16.5, 6.5, 18, 6.5);
      path.lineTo(20.5, 6.5);
      line(17.5, 3.5, 20.5, 6.5);
      line(20.5, 6.5, 17.5, 9.5);
    } else if (icon == Icons.repeat_rounded ||
        icon == Icons.repeat_one_rounded) {
      path.moveTo(5, 7);
      path.lineTo(17, 7);
      path.quadraticBezierTo(20.5, 7, 20.5, 10.5);
      path.lineTo(20.5, 12);
      line(8, 4, 5, 7);
      line(5, 7, 8, 10);
      path.moveTo(19, 17);
      path.lineTo(7, 17);
      path.quadraticBezierTo(3.5, 17, 3.5, 13.5);
      path.lineTo(3.5, 12);
      line(16, 14, 19, 17);
      line(19, 17, 16, 20);
      if (icon == Icons.repeat_one_rounded) {
        line(10.5, 11, 12, 9.5);
        line(12, 9.5, 12, 14.5);
      }
    } else if (icon == Icons.settings_rounded) {
      for (var i = 0; i < 36; i++) {
        final angle = i * math.pi / 18 - math.pi / 2,
            radius = i % 6 < 3 ? 9.1 : 7.5;
        final x = 12 + math.cos(angle) * radius,
            y = 12 + math.sin(angle) * radius;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      path.addOval(const Rect.fromLTWH(8.8, 8.8, 6.4, 6.4));
    } else {
      path.addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(2.5, 4.5, 15, 11),
          const Radius.circular(1.5),
        ),
      );
      line(7, 19, 13, 19);
      line(10, 15.5, 10, 19);
      path.addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(17, 10.5, 5, 10.5),
          const Radius.circular(1),
        ),
      );
    }
    canvas.drawPath(path, pen);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WaveControlPainter old) =>
      old.icon != icon || old.color != color;
}
