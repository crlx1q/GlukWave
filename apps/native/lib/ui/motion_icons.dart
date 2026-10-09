import 'package:flutter/material.dart';
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
    child: Icon(icon, key: ValueKey(state), size: size, color: color),
  );
}
