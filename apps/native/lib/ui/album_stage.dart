import '../l10n/wave_localizations.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import '../core/controller.dart';
import '../core/models.dart';
import 'widgets.dart';
import 'cover_planes.dart';

final _sleeveSceneHeights = <int, double>{};

/// One constant paper/round-disc envelope over the complete permitted turn.
/// Cache it by physical artwork size: gestures never repeat this calculation
/// or change the artwork dimensions. The circle includes the extended CD.
double referenceSleeveSceneHeight(double size) {
  final key = size.ceil(), cached = _sleeveSceneHeights[size.ceil()];
  if (cached != null) {
    return cached;
  }
  final side = key.toDouble(), geometry = <(double, double, double)>[];
  for (final z in [9.0, -9.0]) {
    for (final x in [-.5, .5]) {
      for (final y in [-.5, .5]) {
        geometry.add((x * side, y * side, z));
      }
    }
  }
  for (var angle = 0.0; angle < math.pi * 2; angle += math.pi / 24) {
    geometry.add((
      (.56 + .47 * math.cos(angle)) * side,
      .47 * math.sin(angle) * side,
      0,
    ));
  }
  var extent = side;
  for (var x = -38; x <= 38; x += 2) {
    final cx = math.cos(x * math.pi / 180), sx = math.sin(x * math.pi / 180);
    for (var y = -180; y <= 180; y += 5) {
      final cy = math.cos(y * math.pi / 180), sy = math.sin(y * math.pi / 180);
      for (final (px, py, pz) in geometry) {
        final rotatedZ = -sy * px + cy * pz;
        final projectedY = cx * py - sx * rotatedZ;
        final depth = sx * py + cx * rotatedZ;
        extent = math.max(
          extent,
          2 * (projectedY * 1100 / (1100 - depth)).abs(),
        );
      }
    }
  }
  final height = (extent + 24).ceilToDouble();
  _sleeveSceneHeights[key] = height;
  if (_sleeveSceneHeights.length > 64) {
    _sleeveSceneHeights.remove(_sleeveSceneHeights.keys.first);
  }
  return height;
}

/// Empty lower space at this angle is layout air, not part of the physical case.
/// The inner turn envelope stays constant; only the vertical flow wrapper packs.
double referenceSleeveLowerAir(double size, double x, double y) {
  var bottom = 0.0;
  final cx = math.cos(x), sx = math.sin(x), cy = math.cos(y), sy = math.sin(y);
  final points = <(double, double, double)>[];
  for (final z in [-9.0, 9.0]) {
    for (final px in [-.5, .5]) {
      for (final py in [-.5, .5]) {
        points.add((px * size, py * size, z));
      }
    }
  }
  for (var angle = 0.0; angle < math.pi * 2; angle += math.pi / 24) {
    points.add((
      (.56 + .47 * math.cos(angle)) * size,
      .47 * math.sin(angle) * size,
      0,
    ));
  }
  for (final (px, py, pz) in points) {
    final z = -sy * px + cy * pz,
        projectedY = cx * py - sx * z,
        depth = sx * py + cx * z;
    bottom = math.max(bottom, projectedY * 1100 / (1100 - depth));
  }
  return math.max(0, referenceSleeveSceneHeight(size) / 2 - bottom - 20);
}

/// A rigid 18px sleeve based on the owner's Gluk-Wave-v2 cover scene. Front,
/// back, spine and every edge are opaque; the record sits inside the case.
class AlbumStage extends StatefulWidget {
  final WaveController controller;
  final WaveTrack track;
  final double size;
  final bool playing;
  final Key? artworkKey;
  final bool touchTilt, compactVertical;
  const AlbumStage({
    super.key,
    required this.controller,
    required this.track,
    required this.size,
    required this.playing,
    this.artworkKey,
    this.touchTilt = true,
    this.compactVertical = false,
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
  late final Ticker inertia = createTicker(_tickInertia);
  double _inertiaVelocity = 0, _dragLast = 0;
  Duration _lastInertia = Duration.zero;
  Offset _dragBase = Offset.zero;
  Offset? _mouseOrigin;
  int? _mousePointer;
  void _tickInertia(Duration elapsed) {
    final delta = ((elapsed - _lastInertia).inMicroseconds / 16667).clamp(
      0.0,
      2.0,
    );
    _lastInertia = elapsed;
    setState(() => tilt = Offset(tilt.dx + _inertiaVelocity * delta, tilt.dy));
    _inertiaVelocity *= math.pow(.94, delta);
    if (_inertiaVelocity.abs() < .04 * math.pi / 180) inertia.stop();
  }

  void beginDrag() {
    inertia.stop();
    _dragBase = tilt;
    _dragLast = 0;
    _inertiaVelocity = 0;
    setState(() => dragging = true);
  }

  void updateDrag(Offset distance) {
    _inertiaVelocity = (distance.dx - _dragLast) * .32 * math.pi / 180;
    _dragLast = distance.dx;
    final x = (-9 - _dragBase.dy * 180 / math.pi - distance.dy * .22).clamp(
      -38.0,
      38.0,
    );
    setState(
      () => tilt = Offset(
        _dragBase.dx + distance.dx * .65 * math.pi / 180,
        (-9 - x) * math.pi / 180,
      ),
    );
  }

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
      // Reference retains its angle when idle.
    } else {
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
    inertia.dispose();
    super.dispose();
  }

  void finish(double velocity) {
    setState(() => dragging = false);
    final v = waveVisuals(context);
    if (!v.reducedMotion &&
        !widget.controller.energySaving &&
        visible &&
        TickerMode.of(context) &&
        _inertiaVelocity.abs() >= .04 * math.pi / 180) {
      _lastInertia = Duration.zero;
      inertia.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, v = waveVisuals(context), size = widget.size;
    final dimensional = c.customization.appearance.cover3d && !c.energySaving;
    const opaque = Color(0xff32312d);
    final radius = dimensional ? 2.0 : v.corners(14);
    Widget front() => Container(
      key: const Key('album-front-sleeve'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: opaque,
        borderRadius: BorderRadius.circular(radius),
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
            radius: dimensional ? 2 : 14,
            fit: BoxFit.cover,
          ),
          if (dimensional) ...[
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-.174, -.985),
                    end: Alignment(.174, .985),
                    colors: [
                      Color(0x11000000),
                      Color(0x00000000),
                      Color(0x55000000),
                    ],
                    stops: [0, .35, 1],
                  ),
                ),
              ),
            ),
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0x23ffffff),
                      Color(0x00ffffff),
                      Color(0x00000000),
                      Color(0x22000000),
                    ],
                    stops: [0, .03, .97, 1],
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: CustomPaint(
                key: const Key('album-sunlight-reflection'),
                painter: SleeveReflection(
                  (math.sin(-18 * math.pi / 180 + tilt.dx) + 1) * .5,
                  (-9 * math.pi / 180 - tilt.dy),
                ),
              ),
            ),
          ],
          Positioned(
            right: size * .069,
            bottom: size * .059,
            width: size * .08,
            height: size * .05,
            child: const IgnorePointer(
              child: CustomPaint(
                key: Key('album-front-brand'),
                painter: CoverBrandMark(),
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
    const depth = 18.0;
    Widget materialFace(Key key, {bool plastic = false}) => DecoratedBox(
      key: key,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: plastic
              ? const [Color(0xff596361), Color(0xffaab1ac), Color(0xff424b48)]
              : const [Color(0xff595249), Color(0xff948a7a), Color(0xff554e43)],
        ),
        border: Border.all(color: const Color(0xff4b4842), width: .5),
      ),
    );
    Widget back() => Container(
      key: const Key('album-back-sleeve'),
      width: size,
      height: size,
      padding: EdgeInsets.fromLTRB(
        size * .086,
        size * .093,
        size * .086,
        size * .07,
      ),
      color: c.customization.appearance.coverKind == 'cd'
          ? const Color(0xff262b2c)
          : opaque,
      child: SleeveBackMetadata(track: widget.track, size: size),
    );
    Widget tray() => Container(
      key: const Key('album-cd-tray'),
      decoration: BoxDecoration(
        color: const Color(0xff252a2b),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff414849), Color(0xff202526), Color(0xff343b3c)],
        ),
        border: Border.all(color: const Color(0xff89918d), width: 2),
      ),
      child: Center(
        child: Container(
          width: size * .87,
          height: size * .87,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xff15191a),
            border: Border.all(color: const Color(0xff626b69), width: 2),
          ),
        ),
      ),
    );
    Widget lidInner() => Container(
      key: const Key('album-cd-lid-inner'),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff515958), Color(0xff303637), Color(0xff404846)],
        ),
        border: Border.all(color: const Color(0xffaab2ae), width: 2),
      ),
      padding: EdgeInsets.all(size * .05),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xff727c77)),
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
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Artwork(
                      controller: c,
                      url: widget.track.artwork,
                      size:
                          size *
                          .94 *
                          (c.customization.appearance.coverKind == 'cd'
                              ? .74
                              : .30),
                      radius: 0,
                    ),
                    Container(
                      width: c.customization.appearance.coverKind == 'cd'
                          ? 26
                          : 13,
                      height: c.customization.appearance.coverKind == 'cd'
                          ? 26
                          : 13,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.customization.appearance.coverKind == 'cd'
                            ? const Color(0xff626764)
                            : const Color(0xff292a2b),
                        border: Border.all(
                          color: c.customization.appearance.coverKind == 'cd'
                              ? const Color(0xcccfd3d4)
                              : const Color(0xffd9d1c3),
                          width: c.customization.appearance.coverKind == 'cd'
                              ? 8
                              : 3,
                        ),
                      ),
                    ),
                  ],
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
    final stage = SizedBox(
      key: const Key('album-stage-bounds'),
      width: size * 1.6 + 24,
      height: referenceSleeveSceneHeight(size),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: (size * 1.6 + 24) * .10,
            bottom: 18,
            width: (size * 1.6 + 24) * .75,
            height: 20,
            child: IgnorePointer(
              child: CustomPaint(
                painter: CoverStageShadow(
                  v.brightness == Brightness.dark,
                  v.blur,
                ),
              ),
            ),
          ),
          Center(
            child: Semantics(
              label: wt(
                'native.a0cc85a258',
                values: {'p0': widget.track.title},
                context: context,
              ),
              child: MouseRegion(
                // Preserve a successful physical-face hit for the ancestor
                // queue recognizer. Empty stage space still defers to its child.
                opaque: true,
                hitTestBehavior: HitTestBehavior.deferToChild,
                onEnter: (_) => setState(() => hovering = true),
                onExit: (_) => setState(() => hovering = false),
                child: Listener(
                  onPointerDown: (event) {
                    if (event.kind == PointerDeviceKind.mouse &&
                        event.buttons == kPrimaryMouseButton) {
                      _mousePointer = event.pointer;
                      _mouseOrigin = event.position;
                      beginDrag();
                    }
                  },
                  onPointerMove: (event) {
                    if (event.pointer == _mousePointer &&
                        _mouseOrigin != null) {
                      updateDrag(event.position - _mouseOrigin!);
                    }
                  },
                  onPointerUp: (event) {
                    if (event.pointer == _mousePointer) {
                      _mousePointer = null;
                      _mouseOrigin = null;
                      finish(0);
                    }
                  },
                  onPointerCancel: (event) {
                    if (event.pointer == _mousePointer) {
                      _mousePointer = null;
                      _mouseOrigin = null;
                      inertia.stop();
                      setState(() => dragging = false);
                    }
                  },
                  child: GestureDetector(
                    key: const Key('album-3d'),
                    behavior: HitTestBehavior.deferToChild,
                    supportedDevices: const {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.stylus,
                      PointerDeviceKind.invertedStylus,
                    },
                    onLongPressStart: widget.touchTilt
                        ? null
                        : (_) => beginDrag(),
                    onLongPressMoveUpdate: widget.touchTilt
                        ? null
                        : (details) => updateDrag(details.offsetFromOrigin),
                    onLongPressEnd: widget.touchTilt ? null : (_) => finish(0),
                    onPanStart: widget.touchTilt ? (_) => beginDrag() : null,
                    onPanUpdate: widget.touchTilt
                        ? (details) => updateDrag(
                            Offset(
                              _dragLast + details.delta.dx,
                              (tilt.dy - _dragBase.dy) * 180 / math.pi / .22 +
                                  details.delta.dy,
                            ),
                          )
                        : null,
                    onPanEnd: widget.touchTilt
                        ? (details) =>
                              finish(details.velocity.pixelsPerSecond.dx)
                        : null,
                    onPanCancel: widget.touchTilt
                        ? () {
                            inertia.stop();
                            setState(() => dragging = false);
                          }
                        : null,
                    child: Builder(
                      builder: (_) {
                        final y = -18 * math.pi / 180 + tilt.dx;
                        final x = -9 * math.pi / 180 - tilt.dy;
                        final cd = c.customization.appearance.coverKind == 'cd';
                        final matrix = Matrix4.identity()
                          ..setEntry(3, 2, -1 / 1100)
                          ..translateByDouble(
                            -.12 * size * math.cos(y),
                            0,
                            0,
                            1,
                          )
                          ..rotateX(x)
                          ..rotateY(y);
                        final hinge = Matrix4.identity()
                          ..translateByDouble(0, 0, depth / 2, 1)
                          ..rotateY(-14 * math.pi / 180);
                        return TweenAnimationBuilder<double>(
                          tween: Tween(
                            end:
                                size *
                                (cd
                                    ? (hovering ? .59 : .53)
                                    : (hovering ? .54 : .46)),
                          ),
                          duration: v.duration(600),
                          curve: const Cubic(.2, .8, .2, 1),
                          child: disc,
                          builder: (context, discLeft, discChild) =>
                              AlbumPlaneScene(
                                key: const Key('album-3d-transform'),
                                camera: matrix,
                                size: size,
                                planes: [
                                  CoverPlane(
                                    discChild!,
                                    Matrix4.identity()..translateByDouble(
                                      discLeft,
                                      size * .03,
                                      0,
                                      1,
                                    ),
                                    size * .94,
                                    size * .94,
                                    twoSided: true,
                                    circle: true,
                                  ),
                                  if (cd)
                                    CoverPlane(
                                      tray(),
                                      Matrix4.identity()
                                        ..translateByDouble(0, 0, -1, 1),
                                      size,
                                      size,
                                    ),
                                  CoverPlane(
                                    back(),
                                    Matrix4.identity()
                                      ..translateByDouble(
                                        size,
                                        0,
                                        -depth / 2,
                                        1,
                                      )
                                      ..rotateY(math.pi),
                                    size,
                                    size,
                                  ),
                                  CoverPlane(
                                    materialFace(
                                      const Key('album-spine-face'),
                                      plastic: cd,
                                    ),
                                    Matrix4.identity()
                                      ..translateByDouble(0, 0, -depth / 2, 1)
                                      ..rotateY(-math.pi / 2),
                                    depth,
                                    size,
                                  ),
                                  CoverPlane(
                                    materialFace(
                                      const Key('album-inner-face'),
                                      plastic: cd,
                                    ),
                                    Matrix4.identity()
                                      ..translateByDouble(size, 0, depth / 2, 1)
                                      ..rotateY(math.pi / 2),
                                    depth,
                                    size,
                                  ),
                                  CoverPlane(
                                    materialFace(
                                      const Key('album-top-face'),
                                      plastic: cd,
                                    ),
                                    Matrix4.identity()
                                      ..translateByDouble(0, 0, -depth / 2, 1)
                                      ..rotateX(math.pi / 2),
                                    size,
                                    depth,
                                  ),
                                  CoverPlane(
                                    materialFace(
                                      const Key('album-bottom-face'),
                                      plastic: cd,
                                    ),
                                    Matrix4.identity()
                                      ..translateByDouble(0, size, depth / 2, 1)
                                      ..rotateX(-math.pi / 2),
                                    size,
                                    depth,
                                  ),
                                  if (!cd)
                                    CoverPlane(
                                      front(),
                                      Matrix4.identity()
                                        ..translateByDouble(0, 0, depth / 2, 1),
                                      size,
                                      size,
                                    ),
                                  if (cd) ...[
                                    CoverPlane(
                                      front(),
                                      hinge.clone()
                                        ..translateByDouble(0, 0, .75, 1),
                                      size,
                                      size,
                                    ),
                                    CoverPlane(
                                      lidInner(),
                                      hinge.clone()
                                        ..translateByDouble(size, 0, -.75, 1)
                                        ..rotateY(math.pi),
                                      size,
                                      size,
                                    ),
                                    CoverPlane(
                                      materialFace(
                                        const Key('album-cd-lid-top'),
                                        plastic: true,
                                      ),
                                      hinge.clone()
                                        ..translateByDouble(0, 0, -.75, 1)
                                        ..rotateX(math.pi / 2),
                                      size,
                                      1.5,
                                    ),
                                    CoverPlane(
                                      materialFace(
                                        const Key('album-cd-lid-bottom'),
                                        plastic: true,
                                      ),
                                      hinge.clone()
                                        ..translateByDouble(0, size, .75, 1)
                                        ..rotateX(-math.pi / 2),
                                      size,
                                      1.5,
                                    ),
                                    CoverPlane(
                                      materialFace(
                                        const Key('album-cd-lid-left'),
                                        plastic: true,
                                      ),
                                      hinge.clone()
                                        ..translateByDouble(0, 0, -.75, 1)
                                        ..rotateY(-math.pi / 2),
                                      1.5,
                                      size,
                                    ),
                                    CoverPlane(
                                      materialFace(
                                        const Key('album-cd-lid-right'),
                                        plastic: true,
                                      ),
                                      hinge.clone()
                                        ..translateByDouble(size, 0, .75, 1)
                                        ..rotateY(math.pi / 2),
                                      1.5,
                                      size,
                                    ),
                                  ],
                                ],
                              ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (!widget.compactVertical) return stage;
    final y = -18 * math.pi / 180 + tilt.dx, x = -9 * math.pi / 180 - tilt.dy;
    final height = referenceSleeveSceneHeight(size),
        air = referenceSleeveLowerAir(size, x, y);
    return SizedBox(
      key: const Key('album-packed-stage'),
      width: size * 1.6 + 24,
      height: height - air,
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: height,
        maxHeight: height,
        child: stage,
      ),
    );
  }
}

/// Reference's detached oval ground shadow, never attached to the sleeve face.
class CoverStageShadow extends CustomPainter {
  final bool dark, blur;
  const CoverStageShadow(this.dark, this.blur);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: dark ? .42 : .14);
    if (blur) paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-6 * math.pi / 180);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: size.width,
        height: size.height,
      ),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(CoverStageShadow old) =>
      old.dark != dark || old.blur != blur;
}

class RecordPainter extends CustomPainter {
  final String kind;
  final Color accent, background;
  const RecordPainter(this.kind, this.accent, this.background);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), radius = size.shortestSide / 2;
    final disc = Paint()..color = const Color(0xff1b1c1d);
    if (kind == 'cd') {
      disc.shader = SweepGradient(
        colors: [
          const Color(0xffd3ced3),
          const Color(0xffb5cabc),
          const Color(0xffe5dbb7),
          const Color(0xffaac2d0),
          const Color(0xffd9b7ce),
          const Color(0xffd3ced3),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    }
    canvas.drawCircle(center, radius, disc);
    if (kind != 'cd') {
      for (double r = 1; r < radius; r += 2.7) {
        canvas.drawCircle(
          center,
          r,
          Paint()
            ..color = const Color(0xff161718)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
        canvas.drawCircle(
          center,
          r + 1.5,
          Paint()
            ..color = const Color(0xff333638)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .5,
        );
      }
      canvas.drawCircle(
        center,
        radius - 1,
        Paint()
          ..color = const Color(0xff515355)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
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
          transform: GradientRotation(math.pi / 4),
          colors: [
            Color(0x00d8ddde),
            Color(0x27d8ddde),
            Color(0x00d8ddde),
            Color(0x00d8ddde),
            Color(0x28d8ddde),
            Color(0x00d8ddde),
            Color(0x00d8ddde),
          ],
          stops: [0, 22 / 360, 70 / 360, 150 / 360, 197 / 360, 230 / 360, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_RecordLight old) => false;
}

class SleeveReflection extends CustomPainter {
  final double reflection, pitch;
  const SleeveReflection(this.reflection, [this.pitch = 0]);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final rect = Rect.fromLTWH(
      -size.width * 1.2 * reflection,
      -size.height * math.sin(pitch) * .12,
      size.width * 2.2,
      size.height,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = const LinearGradient(
          begin: Alignment(-.906, -.423),
          end: Alignment(.906, .423),
          colors: [
            Color(0x00ffffff),
            Color(0x00ffffff),
            Color(0x08ffffff),
            Color(0x2dffffff),
            Color(0x00ffffff),
            Color(0x00ffffff),
          ],
          stops: [0, .15, .35, .47, .64, 1],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(SleeveReflection old) =>
      old.reflection != reflection || old.pitch != pitch;
}

class CoverBarcode extends CustomPainter {
  const CoverBarcode();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xffded6c4);
    for (double x = 0; x < size.width; x += 7) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), paint);
      canvas.drawRect(Rect.fromLTWH(x + 3, 0, 2, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(CoverBarcode old) => false;
}

/// Exact existing silhouette copied from assets/mark.svg, with no new icon.
class CoverBrandMark extends CustomPainter {
  const CoverBrandMark();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(2, 8)
      ..cubicTo(2, 6, 3.4, 5.3, 5, 7.5)
      ..lineTo(14.7, 21.8)
      ..cubicTo(17, 25.2, 19.6, 24.9, 20.9, 21.1)
      ..lineTo(25.5, 7.2)
      ..cubicTo(27.3, 1.8, 31.3, 1.1, 34.7, 6)
      ..lineTo(44.8, 20.8)
      ..cubicTo(47, 24.1, 49.8, 23.7, 51, 20)
      ..lineTo(55.5, 6.4)
      ..cubicTo(57.1, 1.5, 60.8, .7, 64, 5.2)
      ..lineTo(64, 19.4)
      ..lineTo(60.9, 15)
      ..cubicTo(58.7, 11.9, 56.1, 12.3, 54.9, 16)
      ..lineTo(50.3, 30)
      ..cubicTo(48.4, 35.6, 44.3, 36.4, 40.7, 31.1)
      ..lineTo(30.9, 17)
      ..cubicTo(28.8, 13.9, 26.1, 14.2, 24.9, 17.8)
      ..lineTo(20.4, 31.4)
      ..cubicTo(18.5, 37, 14.3, 37.8, 10.7, 32.5)
      ..lineTo(2, 19.7)
      ..lineTo(2, 8)
      ..close();
    canvas.save();
    canvas.scale(size.width / 64, size.height / 40);
    canvas.drawPath(p, Paint()..color = const Color(0xccf8f4e9));
    canvas.restore();
  }

  @override
  bool shouldRepaint(CoverBrandMark old) => false;
}

/// Printed sleeve information stays proportional to the physical paper. The
/// full title remains available to assistive technology even when abbreviated.
class SleeveBackMetadata extends StatelessWidget {
  final WaveTrack track;
  final double size;
  const SleeveBackMetadata({
    super.key,
    required this.track,
    required this.size,
  });
  String printKey(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[\s\-–—.,!?;:()\[\]{}"“”‘’]'),
    '',
  );
  @override
  Widget build(BuildContext context) {
    final album = track.album.trim();
    final showAlbum =
        album.isNotEmpty &&
        printKey(album) != printKey(track.title) &&
        printKey(album) != printKey(track.artist);
    final style = TextStyle(
      fontSize: size * .069,
      color: const Color(0xffebe4d3),
      letterSpacing: -size * .0023,
      height: 1.15,
      fontWeight: FontWeight.w800,
    );
    return MediaQuery.withNoTextScaling(
      child: Semantics(
        label: [
          track.title,
          track.artist,
          if (showAlbum) album,
          track.sourceName,
          if (track.duration.isFinite && track.duration > 0)
            clock(track.duration),
        ].where((part) => part.isNotEmpty).join(' · '),
        excludeSemantics: true,
        child: Column(
          key: const Key('album-back-metadata'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'GLUKWAVE / RECORD COLLECTION',
              style: TextStyle(
                fontSize: size * .022,
                letterSpacing: size * .002,
                height: 1.4,
                color: const Color(0xffc5ba9f),
              ),
            ),
            SizedBox(height: size * .05),
            LayoutBuilder(
              builder: (context, bounds) {
                var font = size * .069;
                while (font > size * .050) {
                  final painter = TextPainter(
                    text: TextSpan(
                      text: track.title,
                      style: style.copyWith(fontSize: font),
                    ),
                    textDirection: Directionality.of(context),
                    maxLines: 4,
                  )..layout(maxWidth: bounds.maxWidth);
                  final fits = !painter.didExceedMaxLines;
                  painter.dispose();
                  if (fits) break;
                  font -= size * .002;
                }
                return Text(
                  track.title,
                  key: const Key('album-back-title'),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(fontSize: font),
                );
              },
            ),
            SizedBox(height: size * .045),
            if (track.artist.isNotEmpty)
              Text(
                track.artist,
                key: const Key('album-back-artist'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: size * .038,
                  height: 1.4,
                  color: const Color(0xffded5c4),
                ),
              ),
            if (showAlbum) ...[
              SizedBox(height: size * .025),
              Text(
                album,
                key: const Key('album-back-album'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: size * .032,
                  height: 1.4,
                  color: const Color(0xffc5ba9f),
                ),
              ),
            ],
            const Spacer(),
            SizedBox(height: size * .035),
            SizedBox(
              width: size * .265,
              height: size * .056,
              child: const CustomPaint(painter: CoverBarcode()),
            ),
            SizedBox(height: size * .035),
            Row(
              children: [
                Expanded(
                  child: Text(
                    track.sourceName,
                    key: const Key('album-back-source'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: size * .030,
                      height: 1.4,
                      letterSpacing: size * .001,
                      color: const Color(0xffc5ba9f),
                    ),
                  ),
                ),
                if (track.duration.isFinite && track.duration > 0) ...[
                  SizedBox(width: size * .05),
                  Text(
                    clock(track.duration),
                    key: const Key('album-back-duration'),
                    style: TextStyle(
                      fontSize: size * .030,
                      height: 1.4,
                      color: const Color(0xffc5ba9f),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
