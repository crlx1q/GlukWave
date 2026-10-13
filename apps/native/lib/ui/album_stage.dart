import '../l10n/wave_localizations.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import 'widgets.dart';

/// A rigid 18px sleeve based on the owner's Gluk-Wave-v2 cover scene. Front,
/// back, spine and every edge are opaque; the record sits inside the case.
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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  );
  late final drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );
  late final AnimationController inertia =
      AnimationController.unbounded(vsync: this)..addListener(() {
        if (mounted) setState(() => tilt = Offset(inertia.value, tilt.dy));
      });
  Offset tilt = Offset.zero;
  bool dragging = false, hovering = false, visible = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    visible = state == AppLifecycleState.resumed;
    motion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    motion();
  }

  @override
  void didUpdateWidget(AlbumStage old) {
    super.didUpdateWidget(old);
    if (old.track.id != widget.track.id) {
      inertia.stop();
      tilt = Offset.zero;
    }
    motion();
  }

  void motion() {
    final settings = widget.controller.customization;
    final moving =
        visible &&
        TickerMode.of(context) &&
        settings.appearance.cover3d &&
        !widget.controller.energySaving &&
        !settings.reducedMotion &&
        !MediaQuery.disableAnimationsOf(context);
    if (moving) {
      if (!drift.isAnimating) drift.repeat(reverse: true);
    } else {
      drift.stop();
      inertia.stop();
    }
    if (moving && widget.playing) {
      if (!spin.isAnimating) spin.repeat();
    } else {
      spin.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    spin.dispose();
    drift.dispose();
    inertia.dispose();
    super.dispose();
  }

  void finish(double velocity) {
    setState(() => dragging = false);
    final v = waveVisuals(context);
    if (!v.reducedMotion &&
        !widget.controller.energySaving &&
        velocity.abs() > 40) {
      inertia.value = tilt.dx;
      inertia.animateTo(
        tilt.dx + (velocity / 2000).clamp(-1.2, 1.2),
        duration: v.duration(750),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, v = waveVisuals(context), size = widget.size;
    final dimensional = c.customization.appearance.cover3d && !c.energySaving;
    final opaque = Color.alphaBlend(
      v.accent.withValues(alpha: .12),
      v.background,
    ).withValues(alpha: 1);
    final radius = v.corners(dimensional ? 3 : 14);
    Widget front() => Container(
      key: const Key('album-front-sleeve'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: opaque,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: v.blur
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .2),
                  blurRadius: 18,
                  offset: const Offset(0, 12),
                ),
              ]
            : [],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Artwork(
            key: widget.artworkKey,
            controller: c,
            trackLoading: c.trackLoading,
            url: widget.track.artwork,
            size: size,
            radius: dimensional ? 3 : 14,
            fit: BoxFit.contain,
          ),
          if (dimensional)
            IgnorePointer(
              child: DecoratedBox(
                key: const Key('album-sunlight-reflection'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-2 + math.sin(-.314 + tilt.dx) * 2, -1.2),
                    end: Alignment(2 + math.sin(-.314 + tilt.dx) * 2, 1.2),
                    colors: const [
                      Color(0x00ffffff),
                      Color(0x11ffffff),
                      Color(0x66fff7dc),
                      Color(0x11ffffff),
                      Color(0x00ffffff),
                    ],
                    stops: const [0, .28, .43, .52, 1],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (!dimensional) {
      return SizedBox(
        key: const Key('album-stage-bounds'),
        width: size + 32,
        height: size + 32,
        child: Center(
          child: RepaintBoundary(key: const Key('album-flat'), child: front()),
        ),
      );
    }
    final depth = math.min(18.0, size * .055);
    Widget edge(Key key, Matrix4 matrix, double width, double height) =>
        Transform(
          key: key,
          alignment: Alignment.center,
          transform: matrix,
          child: SizedBox(
            width: width,
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.lerp(opaque, v.ink, .24)!,
                    opaque,
                    Color.lerp(opaque, Colors.black, .35)!,
                  ],
                ),
                border: Border.all(
                  color: Colors.black.withValues(alpha: .25),
                  width: .5,
                ),
              ),
            ),
          ),
        );
    final disc = SizedBox(
      width: size * .94,
      height: size * .94,
      child: AnimatedBuilder(
        animation: spin,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: RecordPainter(
              c.customization.appearance.coverKind,
              v.accent,
              v.background,
            ),
            child: Center(
              child: ClipOval(
                child: Artwork(
                  controller: c,
                  url: widget.track.artwork,
                  size: size * .28,
                  radius: 0,
                ),
              ),
            ),
          ),
        ),
        builder: (_, child) => Stack(
          children: [
            Transform.rotate(angle: spin.value * math.pi * 2, child: child),
            Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: _RecordLight())),
            ),
          ],
        ),
      ),
    );
    return SizedBox(
      key: const Key('album-stage-bounds'),
      width: size * 1.5 + 24,
      height: size * 1.28 + 32,
      child: Center(
        child: Semantics(
          label: wt(
            'native.a0cc85a258',
            values: {'p0': widget.track.title},
            context: context,
          ),
          child: MouseRegion(
            onEnter: (_) => setState(() => hovering = true),
            onExit: (_) => setState(() => hovering = false),
            child: GestureDetector(
              key: const Key('album-3d'),
              behavior: HitTestBehavior.opaque,
              onLongPressStart: widget.touchTilt
                  ? null
                  : (_) {
                      inertia.stop();
                      setState(() => dragging = true);
                    },
              onLongPressMoveUpdate: widget.touchTilt
                  ? null
                  : (details) => setState(
                      () => tilt = Offset(
                        details.offsetFromOrigin.dx / 160,
                        (details.offsetFromOrigin.dy / 160).clamp(-.2, .2),
                      ),
                    ),
              onLongPressEnd: widget.touchTilt ? null : (_) => finish(0),
              onPanStart: widget.touchTilt
                  ? (_) {
                      inertia.stop();
                      setState(() => dragging = true);
                    }
                  : null,
              onPanUpdate: widget.touchTilt
                  ? (details) => setState(
                      () => tilt = Offset(
                        tilt.dx + details.delta.dx / 160,
                        (tilt.dy + details.delta.dy / 160).clamp(-.2, .2),
                      ),
                    )
                  : null,
              onPanEnd: widget.touchTilt
                  ? (details) => finish(details.velocity.pixelsPerSecond.dx)
                  : null,
              onPanCancel: widget.touchTilt ? () => finish(0) : null,
              child: AnimatedBuilder(
                animation: drift,
                builder: (_, _) {
                  final y =
                      -.314 +
                      tilt.dx +
                      (!dragging && !hovering
                          ? math.sin(drift.value * math.pi * 2) * .04
                          : 0);
                  final x = -.157 - tilt.dy;
                  final faceFront = math.cos(y) >= 0;
                  final matrix = Matrix4.identity()
                    ..setEntry(3, 2, 1 / 1100)
                    ..rotateX(x)
                    ..rotateY(y);
                  return Transform(
                    key: const Key('album-3d-transform'),
                    alignment: Alignment.center,
                    transform: matrix,
                    child: SizedBox(
                      width: size * 1.4,
                      height: size,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AnimatedPositioned(
                            duration: v.duration(600),
                            curve: Curves.easeOutCubic,
                            left: size * (hovering ? .46 : .36),
                            top: size * .03,
                            child: disc,
                          ),
                          if (!faceFront)
                            Positioned(
                              left: 0,
                              top: 0,
                              child: Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..translateByDouble(0, 0, -depth / 2, 1)
                                  ..rotateY(math.pi),
                                child: Container(
                                  key: const Key('album-back-sleeve'),
                                  width: size,
                                  height: size,
                                  padding: EdgeInsets.all(size * .08),
                                  color: opaque,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Brand(
                                        size: math.max(14, size * .07),
                                        animated: false,
                                      ),
                                      const Spacer(),
                                      Text(
                                        widget.track.title,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: size * .085,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        widget.track.artist,
                                        maxLines: 2,
                                        style: TextStyle(
                                          fontSize: size * .045,
                                          color: v.muted,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        'GLUK WAVE / 33⅓ RPM',
                                        style: TextStyle(
                                          fontSize: size * .028,
                                          letterSpacing: 1,
                                          color: v.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            left: -depth / 2,
                            top: 0,
                            child: edge(
                              const Key('album-spine-face'),
                              Matrix4.identity()..rotateY(-math.pi / 2),
                              depth,
                              size,
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: -depth / 2,
                            child: edge(
                              const Key('album-top-face'),
                              Matrix4.identity()..rotateX(math.pi / 2),
                              size,
                              depth,
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: size - depth / 2,
                            child: edge(
                              const Key('album-bottom-face'),
                              Matrix4.identity()..rotateX(-math.pi / 2),
                              size,
                              depth,
                            ),
                          ),
                          Positioned(
                            left: size - depth / 2,
                            top: 0,
                            child: edge(
                              const Key('album-inner-face'),
                              Matrix4.identity()..rotateY(math.pi / 2),
                              depth,
                              size,
                            ),
                          ),
                          if (faceFront)
                            Positioned(
                              left: 0,
                              top: 0,
                              child: Transform(
                                transform: Matrix4.identity()
                                  ..translateByDouble(0, 0, depth / 2, 1),
                                child: front(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
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

class _RecordLight extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawCircle(
      size.center(Offset.zero),
      size.shortestSide / 2,
      Paint()
        ..shader = const SweepGradient(
          startAngle: -.8,
          endAngle: 5.48,
          colors: [
            Color(0x00ffffff),
            Color(0x1cffffff),
            Color(0x00ffffff),
            Color(0x00ffffff),
            Color(0x18ffffff),
            Color(0x00ffffff),
          ],
          stops: [0, .07, .14, .48, .57, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_RecordLight old) => false;
}
