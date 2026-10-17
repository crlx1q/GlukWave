import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'theme.dart';

/// Rows settle independently after a discrete cue/seek. There is no scrolling
/// clock between cues; each tile receives only the committed scroll offset.
class LyricTile extends StatefulWidget {
  final Widget child;
  final int revision, distance;
  final double offset;
  final bool active;
  const LyricTile({super.key, required this.child, required this.revision, required this.distance, required this.offset, required this.active});
  @override
  State<LyricTile> createState() => _LyricTileState();
}

class _LyricTileState extends State<LyricTile> with SingleTickerProviderStateMixin {
  late final spring = AnimationController.unbounded(vsync: this);
  Timer? delay;
  bool get still => MediaQuery.disableAnimationsOf(context) || waveVisuals(context).reducedMotion || !TickerMode.of(context);
  @override
  void didUpdateWidget(LyricTile old) {
    super.didUpdateWidget(old);
    if (old.revision == widget.revision) return;
    delay?.cancel();
    spring.stop();
    if (still) { spring.value = 0; return; }
    spring.value = widget.offset;
    delay = Timer(Duration(milliseconds: widget.distance.clamp(0, 5) * 22), () {
      if (mounted) spring.animateWith(SpringSimulation(const SpringDescription(mass: 1, stiffness: 170, damping: 22), spring.value, 0, 0));
    });
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (still) { delay?.cancel(); spring.stop(); spring.value = 0; }
  }
  @override
  void dispose() { delay?.cancel(); spring.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: spring,
    child: AnimatedScale(scale: widget.active ? 1 : .985, alignment: Alignment.centerLeft, duration: still ? Duration.zero : const Duration(milliseconds: 360), child: widget.child),
    builder: (_, child) => Transform.translate(key: const Key('lyric-tile-offset'), offset: Offset(0, spring.value), child: child),
  );
}
