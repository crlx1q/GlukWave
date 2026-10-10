import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/controller.dart';
import 'widgets.dart';

/// Only a transform ticks. The filtered, decoded cover remains a static child.
class CoverAmbient extends StatefulWidget {
  final WaveController controller;
  final String artwork;
  final bool playing, active;
  const CoverAmbient({
    super.key,
    required this.controller,
    required this.artwork,
    required this.playing,
    this.active = true,
  });
  @override
  State<CoverAmbient> createState() => _CoverAmbientState();
}

class _CoverAmbientState extends State<CoverAmbient>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 32),
  );
  bool visible = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    motion();
  }

  @override
  void didUpdateWidget(CoverAmbient oldWidget) {
    super.didUpdateWidget(oldWidget);
    motion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    visible = state == AppLifecycleState.resumed;
    motion();
  }

  void motion() {
    final v = waveVisuals(context);
    final animate =
        widget.active &&
        widget.playing &&
        widget.artwork.isNotEmpty &&
        visible &&
        TickerMode.of(context) &&
        v.blur &&
        !v.reducedMotion &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate) {
      if (!drift.isAnimating) drift.repeat();
    } else {
      drift.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context);
    if (!v.blur || widget.artwork.isEmpty) return const SizedBox.shrink();
    final amoled = widget.controller.customization.theme == 'amoled';
    return IgnorePointer(
      child: ExcludeSemantics(
        child: ClipRect(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest.longestSide * 1.5;
              return AnimatedBuilder(
                animation: drift,
                child: RepaintBoundary(
                  child: Opacity(
                    opacity: amoled
                        ? .10
                        : v.brightness == Brightness.dark
                        ? .22
                        : .14,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 48, sigmaY: 48),
                      child: Artwork(
                        controller: widget.controller,
                        url: widget.artwork,
                        radius: 0,
                        size: size,
                      ),
                    ),
                  ),
                ),
                builder: (context, child) {
                  final phase = drift.value * math.pi * 2;
                  return OverflowBox(
                    maxWidth: size,
                    maxHeight: size,
                    child: Transform.translate(
                      key: const Key('cover-ambient-transform'),
                      offset: Offset(
                        math.sin(phase) * constraints.maxWidth * .055,
                        math.cos(phase) * constraints.maxHeight * .045,
                      ),
                      child: Transform.rotate(
                        angle: math.sin(phase) * .035,
                        child: child,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
