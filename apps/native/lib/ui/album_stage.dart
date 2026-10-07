import '../l10n/wave_localizations.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import 'widgets.dart';

/// The cover is real track artwork. The record is drawn once inside its own
/// repaint boundary; only its transform rotates while this screen is visible.
class AlbumStage extends StatefulWidget {
  final WaveController controller;
  final WaveTrack track;
  final double size;
  final bool playing;
  final Key? artworkKey;
  final bool touchTilt;
  const AlbumStage({
    super.key,
    required this.controller,
    required this.track,
    required this.size,
    required this.playing,
    this.artworkKey,
    this.touchTilt = true,
  });
  @override
  State<AlbumStage> createState() => _AlbumStageState();
}

class _AlbumStageState extends State<AlbumStage>
    with SingleTickerProviderStateMixin {
  late final spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 15),
  );
  Offset tilt = Offset.zero;
  bool dragging = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    motion();
  }

  @override
  void didUpdateWidget(AlbumStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    motion();
  }

  void motion() {
    final settings = widget.controller.customization;
    if (widget.playing &&
        settings.appearance.cover3d &&
        !settings.reducedMotion &&
        !MediaQuery.disableAnimationsOf(context)) {
      if (!spin.isAnimating) spin.repeat();
    } else {
      spin.stop();
    }
  }

  @override
  void dispose() {
    spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = waveVisuals(context),
        appearance = widget.controller.customization.appearance;
    final size = widget.size;
    final coverSize = appearance.cover3d ? size * .81 : size;
    final cover = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(v.corners(14)),
        boxShadow: v.blur
            ? [
                BoxShadow(
                  color: v.accent.withValues(alpha: .25),
                  blurRadius: 28,
                  spreadRadius: 2,
                  offset: const Offset(0, 16),
                ),
              ]
            : [],
      ),
      child: Artwork(
        key: widget.artworkKey,
        controller: widget.controller,
        url: widget.track.artwork,
        size: coverSize,
        radius: 14,
      ),
    );
    return SizedBox(
      height: size + 45,
      child: Center(
        child: appearance.cover3d
            ? Semantics(
                label: wt(
                  'native.a0cc85a258',
                  values: {'p0': (widget.track.title)},
                  context: context,
                ),
                child: MouseRegion(
                  onHover: (event) {
                    if (!dragging) {
                      setState(
                        () => tilt = Offset(
                          (event.localPosition.dx / size - .5) * .7,
                          (event.localPosition.dy / size - .5) * .45,
                        ),
                      );
                    }
                  },
                  onExit: (_) => setState(() => tilt = Offset.zero),
                  child: GestureDetector(
                    key: const Key('album-3d'),
                    behavior: HitTestBehavior.opaque,
                    onLongPressStart: widget.touchTilt
                        ? null
                        : (_) => setState(() => dragging = true),
                    onLongPressMoveUpdate: widget.touchTilt
                        ? null
                        : (details) => setState(
                            () => tilt = Offset(
                              (details.offsetFromOrigin.dx / 160).clamp(
                                -.6,
                                .6,
                              ),
                              (details.offsetFromOrigin.dy / 160).clamp(
                                -.4,
                                .4,
                              ),
                            ),
                          ),
                    onLongPressEnd: widget.touchTilt
                        ? null
                        : (_) => setState(() {
                            dragging = false;
                            tilt = Offset.zero;
                          }),
                    onPanStart: widget.touchTilt
                        ? (_) => setState(() => dragging = true)
                        : null,
                    onPanUpdate: !widget.touchTilt
                        ? null
                        : (details) => setState(
                            () => tilt = Offset(
                              (tilt.dx + details.delta.dx / 160).clamp(-.6, .6),
                              (tilt.dy + details.delta.dy / 160).clamp(-.4, .4),
                            ),
                          ),
                    onPanEnd: !widget.touchTilt
                        ? null
                        : (_) => setState(() {
                            dragging = false;
                            tilt = Offset.zero;
                          }),
                    onPanCancel: !widget.touchTilt
                        ? null
                        : () => setState(() {
                            dragging = false;
                            tilt = Offset.zero;
                          }),
                    child: TweenAnimationBuilder<Offset>(
                      tween: Tween(begin: Offset.zero, end: tilt),
                      duration: dragging ? Duration.zero : v.duration(260),
                      builder: (context, value, child) => Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, .0014)
                          ..rotateX(-.06 - value.dy)
                          ..rotateY(-.2 + value.dx)
                          ..rotateZ(-.025),
                        child: child,
                      ),
                      child: SizedBox(
                        width: size,
                        height: size,
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              right: 0,
                              top: size * .12,
                              child: AnimatedBuilder(
                                animation: spin,
                                child: RepaintBoundary(
                                  child: SizedBox(
                                    width: size * .75,
                                    height: size * .75,
                                    child: CustomPaint(
                                      painter: RecordPainter(
                                        appearance.coverKind,
                                        v.accent,
                                        v.background,
                                      ),
                                      child: Center(
                                        child: ClipOval(
                                          child: Artwork(
                                            controller: widget.controller,
                                            url: widget.track.artwork,
                                            size: size * .18,
                                            radius: 0,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                builder: (context, child) => Transform.rotate(
                                  angle: spin.value * math.pi * 2,
                                  child: child,
                                ),
                              ),
                            ),
                            cover,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : Semantics(
                label: wt(
                  'native.02a22b9218',
                  values: {'p0': (widget.track.title)},
                  context: context,
                ),
                child: RepaintBoundary(
                  key: const Key('album-flat'),
                  child: cover,
                ),
              ),
      ),
    );
  }
}

class RecordPainter extends CustomPainter {
  final String kind;
  final Color accent, background;
  const RecordPainter(this.kind, this.accent, this.background);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), radius = size.shortestSide / 2;
    final disc = Paint()..color = const Color(0xff222323);
    if (kind == 'cd') {
      disc.shader = SweepGradient(
        colors: [
          const Color(0xffced8d3),
          accent,
          const Color(0xffe4dfb9),
          const Color(0xffb5ccd8),
          const Color(0xffe3c5dd),
          const Color(0xffced8d3),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    }
    canvas.drawCircle(center, radius, disc);
    final rings = Paint()
      ..color = Colors.white.withValues(alpha: kind == 'cd' ? .2 : .055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .6;
    for (var ring = kind == 'cd' ? 2 : 1; ring < 24; ring++) {
      canvas.drawCircle(center, radius * (.26 + ring * .029), rings);
    }
    canvas.drawCircle(center, radius * .145, Paint()..color = accent);
    canvas.drawCircle(center, radius * .055, Paint()..color = background);
  }

  @override
  bool shouldRepaint(RecordPainter old) =>
      old.kind != kind || old.accent != accent || old.background != background;
}
