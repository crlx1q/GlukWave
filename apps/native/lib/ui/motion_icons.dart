import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'theme.dart';
import '../l10n/audio_design_strings.dart';

/// Loading represents the real source lifecycle, shared by every play button.
/// The same travelling wave as the web SVG, with no platform spinner or asset.
class WavePlaybackIcon extends StatefulWidget {
  final bool playing, loading;
  final double size;
  final Color? color;
  const WavePlaybackIcon({
    super.key,
    required this.playing,
    required this.loading,
    this.size = 26,
    this.color,
  });
  @override
  State<WavePlaybackIcon> createState() => _WavePlaybackIconState();
}

class _WavePlaybackIconState extends State<WavePlaybackIcon>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final entry = AnimationController(
    vsync: this,
    value: widget.loading ? 1 : 0,
  );
  late final loop = AnimationController(vsync: this);
  late final blend = CurvedAnimation(
    parent: entry,
    curve: Curves.easeInOutCubic,
  );
  bool visible = true, animate = false;
  @override
  void initState() {
    super.initState();
    visible = ![
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ].contains(WidgetsBinding.instance.lifecycleState);
    WidgetsBinding.instance.addObserver(this);
  }

  void sync() {
    final v = waveVisuals(context), speed = v.speed.clamp(.3, 2.0);
    animate =
        visible &&
        TickerMode.of(context) &&
        !v.reducedMotion &&
        !MediaQuery.disableAnimationsOf(context);
    final period = Duration(milliseconds: (1200 / speed).round());
    entry.duration = Duration(milliseconds: (220 / speed).round());
    if (animate) {
      entry.animateTo(widget.loading ? 1 : 0);
    } else {
      entry.value = widget.loading ? 1 : 0;
    }
    if (widget.loading && animate) {
      if (loop.duration != period || !loop.isAnimating) {
        loop.duration = period;
        loop.repeat();
      }
    } else {
      loop.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sync();
  }

  @override
  void didUpdateWidget(WavePlaybackIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      visible = ![
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ].contains(state);
      sync();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    blend.dispose();
    entry.dispose();
    loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ?? IconTheme.of(context).color ?? waveVisuals(context).ink;
    return Semantics(
      label: widget.loading
          ? audioDesignText('loadingPlayback', context: context)
          : null,
      liveRegion: widget.loading,
      child: TickerMode(
        enabled: visible && TickerMode.of(context),
        child: SizedBox.square(
          dimension: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              FadeTransition(
                opacity: ReverseAnimation(blend),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 1, end: .88).animate(blend),
                  child: WavePlayPauseIcon(
                    playing: widget.playing,
                    size: widget.size,
                    color: color,
                  ),
                ),
              ),
              FadeTransition(
                opacity: blend,
                child: CustomPaint(
                  key: widget.loading
                      ? const Key('playback-loading-indicator')
                      : null,
                  size: Size.square(widget.size),
                  painter: _PlaybackWavePainter(loop, blend, color, animate),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaybackWavePainter extends CustomPainter {
  final Animation<double> phase, entry;
  final Color color;
  final bool animate;
  _PlaybackWavePainter(this.phase, this.entry, this.color, this.animate)
    : super(repaint: Listenable.merge([phase, entry]));
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final height = 6 * entry.value;
    final path = Path()
      ..moveTo(3, 12)
      ..cubicTo(5, 12, 5, 12 - height, 7.5, 12 - height)
      ..cubicTo(10, 12 - height, 10, 12 + height, 12.5, 12 + height)
      ..cubicTo(15, 12 + height, 15, 12 - height, 17.5, 12 - height)
      ..cubicTo(20, 12 - height, 20, 12, 21, 12);
    final pen = Paint()
      ..color = color.withValues(alpha: animate ? .18 : 1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, pen);
    if (animate) {
      final metric = path.computeMetrics().first;
      final length = metric.length,
          end = phase.value * (length * 1.32),
          start = end - length * .32;
      canvas.drawPath(
        metric.extractPath(start.clamp(0, length), end.clamp(0, length)),
        pen..color = color,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlaybackWavePainter old) =>
      old.phase != phase ||
      old.entry != entry ||
      old.color != color ||
      old.animate != animate;
}

/// Lyrics and queue use the same settling motion when their view is selected.
class WaveViewIcon extends StatelessWidget {
  final IconData icon;
  final bool active;
  final double size;
  const WaveViewIcon(
    this.icon, {
    super.key,
    required this.active,
    this.size = 19,
  });
  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context),
        reduced = v.reducedMotion || MediaQuery.disableAnimationsOf(context);
    return AnimatedRotation(
      turns: active && !reduced ? -.025 : 0,
      duration: reduced ? Duration.zero : v.duration(180),
      curve: Curves.easeOutCubic,
      child: WaveControlIcon(icon, size: size),
    );
  }
}

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
    motion.duration = Duration(
      milliseconds: (230 / waveVisuals(context).speed.clamp(.3, 2)).round(),
    );
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

/// Volume topology is shared by mobile, desktop, Connect and tray surfaces.
class WaveVolumeIcon extends StatelessWidget {
  final double volume, size;
  final Color? color;
  const WaveVolumeIcon({
    super.key,
    required this.volume,
    this.size = 22,
    this.color,
  });
  @override
  Widget build(BuildContext context) => WaveStateIcon(
    state: volume == 0
        ? 0
        : volume < .5
        ? 1
        : 2,
    icon: volume == 0
        ? Icons.volume_off_outlined
        : volume < .5
        ? Icons.volume_down_outlined
        : Icons.volume_up_outlined,
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
    Icons.volume_down_outlined,
    Icons.volume_off_outlined,
    Icons.shuffle_rounded,
    Icons.repeat_rounded,
    Icons.repeat_one_rounded,
    Icons.settings_rounded,
    Icons.devices_rounded,
    Icons.home_outlined,
    Icons.search_rounded,
    Icons.library_music_outlined,
    Icons.favorite_border_rounded,
    Icons.lyrics_outlined,
    Icons.queue_music_rounded,
    Icons.more_horiz_rounded,
    Icons.person_outline_rounded,
    Icons.spatial_audio_off_outlined,
    Icons.people_outline_rounded,
    Icons.album_outlined,
    Icons.explore_outlined,
    Icons.download_for_offline_outlined,
    Icons.download_rounded,
    Icons.offline_pin_outlined,
    Icons.qr_code_scanner_rounded,
    Icons.shield_outlined,
    Icons.battery_saver_outlined,
    Icons.chevron_right_rounded,
    Icons.arrow_back_rounded,
    Icons.keyboard_arrow_down_rounded,
    Icons.close_rounded,
    Icons.refresh_rounded,
    Icons.hub_outlined,
    Icons.nightlight_outlined,
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
        icon == Icons.volume_down_outlined ||
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
        if (icon == Icons.volume_up_outlined) {
          path.moveTo(18.5, 5.5);
          path.cubicTo(22.5, 9, 22.5, 15, 18.5, 18.5);
        }
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
    } else if (icon == Icons.home_outlined) {
      path.moveTo(3, 11);
      path.lineTo(12, 3.5);
      path.lineTo(21, 11);
      path.moveTo(5.5, 10);
      path.lineTo(5.5, 20);
      path.lineTo(10, 20);
      path.lineTo(10, 14);
      path.lineTo(14, 14);
      path.lineTo(14, 20);
      path.lineTo(18.5, 20);
      path.lineTo(18.5, 10);
    } else if (icon == Icons.search_rounded) {
      path.addOval(const Rect.fromLTWH(3, 3, 12.5, 12.5));
      line(14, 14, 21, 21);
    } else if (icon == Icons.library_music_outlined) {
      line(4, 4, 4, 20);
      line(9, 4, 9, 20);
      line(14, 5, 18, 20);
      line(19, 4, 22, 17);
    } else if (icon == Icons.favorite_border_rounded) {
      path.moveTo(12, 20);
      path.cubicTo(7, 16, 2.7, 12, 3, 7.7);
      path.cubicTo(3.4, 2.6, 9.6, 2.5, 12, 7);
      path.cubicTo(14.4, 2.5, 20.6, 2.6, 21, 7.7);
      path.cubicTo(21.3, 12, 17, 16, 12, 20);
      path.close();
    } else if (icon == Icons.lyrics_outlined) {
      line(5, 5, 19, 5);
      line(12, 5, 12, 20);
      line(9, 20, 15, 20);
      line(5, 5, 5, 8);
      line(19, 5, 19, 8);
    } else if (icon == Icons.queue_music_rounded) {
      line(3, 5, 20, 5);
      line(3, 11, 16, 11);
      line(3, 17, 10, 17);
      path.moveTo(17, 15);
      path.lineTo(22, 18);
      path.lineTo(17, 21);
      path.close();
    } else if (icon == Icons.more_horiz_rounded) {
      for (final x in [5.0, 12.0, 19.0]) {
        path.addOval(Rect.fromCircle(center: Offset(x, 12), radius: 1.25));
      }
    } else if (icon == Icons.person_outline_rounded ||
        icon == Icons.people_outline_rounded ||
        icon == Icons.spatial_audio_off_outlined) {
      path.addOval(const Rect.fromLTWH(8, 3, 8, 8));
      path.moveTo(4, 21);
      path.lineTo(4, 18);
      path.cubicTo(4, 12, 20, 12, 20, 18);
      path.lineTo(20, 21);
      if (icon != Icons.person_outline_rounded) {
        path.moveTo(19, 4);
        path.cubicTo(24, 5, 23, 10, 20, 11);
      }
    } else if (icon == Icons.album_outlined || icon == Icons.explore_outlined) {
      path.addOval(const Rect.fromLTWH(3, 3, 18, 18));
      path.addOval(const Rect.fromLTWH(10, 10, 4, 4));
      if (icon == Icons.explore_outlined) {
        line(8, 16, 10, 10);
        line(14, 14, 16, 8);
      }
    } else if (icon == Icons.download_for_offline_outlined ||
        icon == Icons.download_rounded ||
        icon == Icons.offline_pin_outlined) {
      line(12, 3, 12, 15);
      line(7, 10, 12, 15);
      line(12, 15, 17, 10);
      path.moveTo(4, 16);
      path.lineTo(4, 20);
      path.lineTo(20, 20);
      path.lineTo(20, 16);
    } else if (icon == Icons.chevron_right_rounded ||
        icon == Icons.arrow_back_rounded ||
        icon == Icons.keyboard_arrow_down_rounded) {
      if (icon == Icons.keyboard_arrow_down_rounded) {
        line(6, 9, 12, 15);
        line(12, 15, 18, 9);
      } else if (icon == Icons.arrow_back_rounded) {
        line(20, 12, 4, 12);
        line(4, 12, 10, 6);
        line(4, 12, 10, 18);
      } else {
        line(9, 5, 16, 12);
        line(16, 12, 9, 19);
      }
    } else if (icon == Icons.close_rounded) {
      line(6, 6, 18, 18);
      line(18, 6, 6, 18);
    } else if (icon == Icons.qr_code_scanner_rounded) {
      path.moveTo(8, 3);
      path.lineTo(3, 3);
      path.lineTo(3, 8);
      path.moveTo(16, 3);
      path.lineTo(21, 3);
      path.lineTo(21, 8);
      path.moveTo(21, 16);
      path.lineTo(21, 21);
      path.lineTo(16, 21);
      path.moveTo(8, 21);
      path.lineTo(3, 21);
      path.lineTo(3, 16);
      line(7, 9, 17, 9);
      line(7, 15, 17, 15);
      line(10, 7, 10, 17);
      line(14, 7, 14, 17);
    } else if (icon == Icons.shield_outlined) {
      path.moveTo(12, 2.5);
      path.lineTo(21, 6);
      path.lineTo(20, 13);
      path.quadraticBezierTo(19, 18, 12, 22);
      path.quadraticBezierTo(5, 18, 4, 13);
      path.lineTo(3, 6);
      path.close();
      line(8, 12, 11, 15);
      line(11, 15, 16, 9);
    } else if (icon == Icons.battery_saver_outlined) {
      path.addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(3, 6, 17, 12),
          const Radius.circular(2),
        ),
      );
      line(22, 10, 22, 14);
      line(11.5, 8, 9, 12);
      line(9, 12, 14, 12);
      line(14, 12, 11.5, 16);
    } else if (icon == Icons.refresh_rounded) {
      path.addArc(const Rect.fromLTWH(4, 4, 16, 16), .4, 5.0);
      line(19, 3, 19, 9);
      line(13, 9, 19, 9);
    } else if (icon == Icons.hub_outlined) {
      path.addOval(const Rect.fromLTWH(9, 9, 6, 6));
      for (final point in const [
        Offset(5, 4),
        Offset(19, 4),
        Offset(5, 20),
        Offset(19, 20),
      ]) {
        path.addOval(Rect.fromCircle(center: point, radius: 2));
        line(point.dx, point.dy, 12, 12);
      }
    } else if (icon == Icons.nightlight_outlined) {
      path.moveTo(17, 3);
      path.cubicTo(7, 2, 1, 14, 10, 20);
      path.cubicTo(15, 24, 22, 19, 22, 14);
      path.cubicTo(14, 18, 10, 8, 17, 3);
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

/// Shared short displacement for primary actions. No repeating animation and
/// no pointer highlight; keyboard focus remains with the actual button.
class WavePress extends StatefulWidget {
  final Widget child;
  const WavePress({super.key, required this.child});
  @override
  State<WavePress> createState() => _WavePressState();
}

class _WavePressState extends State<WavePress> {
  bool pressed = false, hovered = false;
  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context),
        still = v.reducedMotion || MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() {
        hovered = false;
        pressed = false;
      }),
      child: Listener(
        onPointerDown: (_) => setState(() => pressed = true),
        onPointerUp: (_) => setState(() => pressed = false),
        onPointerCancel: (_) => setState(() => pressed = false),
        child: AnimatedContainer(
          duration: still ? Duration.zero : v.duration(160),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(
            0,
            still
                ? 0
                : pressed
                ? 2
                : hovered
                ? -2
                : 0,
            0,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
