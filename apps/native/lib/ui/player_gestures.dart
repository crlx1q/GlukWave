import 'dart:async';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/models.dart';
import 'widgets.dart' show Artwork;
import 'theme.dart';

/// Move incoming cover/metadata in the queue direction without keeping a
/// duplicate player alive, delaying a command, or changing playback state.
class TrackMotion extends StatefulWidget {
  final WaveController controller;
  final Widget child;
  const TrackMotion({super.key, required this.controller, required this.child});
  @override
  State<TrackMotion> createState() => _TrackMotionState();
}

class _TrackMotionState extends State<TrackMotion>
    with SingleTickerProviderStateMixin {
  late final motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1,
  );
  String? trackId;
  double direction = 1;
  @override
  void initState() {
    super.initState();
    trackId = widget.controller.audio.viewCurrent?.id;
  }

  @override
  void didUpdateWidget(TrackMotion old) {
    super.didUpdateWidget(old);
    final c = widget.controller, nextId = c.audio.viewCurrent?.id;
    if (trackId == nextId) return;
    final before = c.audio.viewTracks.indexWhere((t) => t.id == trackId),
        after = c.audio.viewTracks.indexWhere((t) => t.id == nextId);
    direction = before >= 0 && after >= 0 && after < before ? -1 : 1;
    trackId = nextId;
    if (waveVisuals(context).reducedMotion ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.of(context) ||
        c.energySaving) {
      motion.value = 1;
    } else {
      motion.forward(from: 0);
    }
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: motion,
    child: widget.child,
    builder: (context, child) {
      final progress = Curves.easeOutCubic.transform(motion.value);
      return Opacity(
        opacity: .45 + .55 * progress,
        child: FractionalTranslation(
          key: const Key('player-track-motion'),
          translation: Offset((1 - progress) * .07 * direction, 0),
          child: child,
        ),
      );
    },
  );
}

/// Rejects the opposite vertical direction before the scroll view's arena is
/// decided. An upward movement on the cover therefore remains natural scroll.
class _PlayerPanRecognizer extends PanGestureRecognizer {
  bool opensPlayer;
  Offset origin = Offset.zero;
  bool decided = false;
  bool pointerCancelled = false;
  _PlayerPanRecognizer({required this.opensPlayer})
    : super(
        supportedDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
      ) {
    dragStartBehavior = DragStartBehavior.down;
  }
  @override
  void addAllowedPointer(PointerDownEvent event) {
    origin = event.localPosition;
    decided = false;
    pointerCancelled = false;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerCancelEvent) pointerCancelled = true;
    if (!decided && event is PointerMoveEvent) {
      final distance = event.localPosition - origin;
      if (distance.distance > 8) {
        decided = true;
        if (distance.dy.abs() > distance.dx.abs() &&
            (opensPlayer ? distance.dy > 0 : distance.dy < 0)) {
          resolve(GestureDisposition.rejected);
          return;
        }
      }
    }
    super.handleEvent(event);
  }
}

/// Only artwork/metadata and the dismiss handle use this surface. Sliders,
/// buttons, lyrics and queue scrolling remain outside its gesture arena.
class PlayerGestureSurface extends StatefulWidget {
  final WaveController controller;
  final Widget child;
  final bool opensPlayer, physicalOnly;
  final VoidCallback? onVerticalStart, onVerticalCancel;
  final ValueChanged<double>? onVerticalUpdate, onVerticalEnd;
  const PlayerGestureSurface({
    super.key,
    required this.controller,
    required this.child,
    this.opensPlayer = false,
    this.physicalOnly = false,
    this.onVerticalStart,
    this.onVerticalUpdate,
    this.onVerticalEnd,
    this.onVerticalCancel,
  });
  @override
  State<PlayerGestureSurface> createState() => _PlayerGestureSurfaceState();
}

class _PlayerGestureSurfaceState extends State<PlayerGestureSurface> {
  Offset distance = Offset.zero;
  Axis? axis;
  bool acceptsVertical = false;
  WaveTrack? preview;
  double swipe = 0, previewSide = 1;
  Timer? snap;
  @override
  void dispose() { snap?.cancel(); super.dispose(); }
  void snapBack() {
    if (!mounted) return;
    setState(() => swipe = 0);
    snap?.cancel();
    snap = Timer(const Duration(milliseconds: 280), () { if (mounted) setState(() => preview = null); });
  }
  void reset() {
    distance = Offset.zero;
    axis = null;
    acceptsVertical = false;
  }

  void cancel() {
    if (acceptsVertical) widget.onVerticalCancel?.call();
    reset();
    snapBack();
  }

  void update(DragUpdateDetails details) {
    distance += details.delta;
    if (axis == null && distance.distance > 8) {
      axis = distance.dx.abs() > distance.dy.abs()
          ? Axis.horizontal
          : Axis.vertical;
      acceptsVertical =
          axis == Axis.vertical &&
          (widget.opensPlayer ? distance.dy < 0 : distance.dy > 0);
      if (acceptsVertical) widget.onVerticalStart?.call();
    }
    if (axis == Axis.horizontal && widget.opensPlayer) {
      final c = widget.controller, list = widget.controller.audio.viewTracks;
      final index = list.indexWhere((track) => track.id == c.audio.viewCurrent?.id);
      final side = distance.dx < 0 ? 1 : -1, next = index + side;
      setState(() {
        previewSide = side.toDouble();
        preview = c.canControl && index >= 0 && next >= 0 && next < list.length ? list[next] : null;
        swipe = preview == null ? distance.dx * .12 : distance.dx;
      });
    }
    if (acceptsVertical) widget.onVerticalUpdate?.call(distance.dy);
  }

  void end(DragEndDetails details) {
    if (axis == Axis.horizontal &&
        (distance.dx.abs() > 56 ||
            (distance.dx.abs() > 12 &&
                details.velocity.pixelsPerSecond.dx.abs() > 700))) {
      final c = widget.controller;
      final index = c.audio.viewTracks.indexWhere(
        (track) => track.id == c.audio.viewCurrent?.id,
      );
      final next = index + (distance.dx < 0 ? 1 : -1);
      if (c.canControl &&
          index >= 0 &&
          next >= 0 &&
          next < c.audio.viewTracks.length) {
        unawaited(
          c.audio
              .skipToQueueItem(next)
              .catchError((Object error) => c.tell(error.toString())),
        );
      }
    } else if (acceptsVertical) {
      widget.onVerticalEnd?.call(details.velocity.pixelsPerSecond.dy);
    }
    reset();
    snapBack();
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: widget.physicalOnly
        ? HitTestBehavior.deferToChild
        : HitTestBehavior.opaque,
    gestures: {
      _PlayerPanRecognizer:
          GestureRecognizerFactoryWithHandlers<_PlayerPanRecognizer>(
            () => _PlayerPanRecognizer(opensPlayer: widget.opensPlayer),
            (recognizer) {
              recognizer.opensPlayer = widget.opensPlayer;
              recognizer.onDown = (_) { snap?.cancel(); reset(); };
              recognizer.onUpdate = update;
              recognizer.onEnd = (details) {
                if (recognizer.pointerCancelled) {
                  cancel();
                } else {
                  end(details);
                }
              };
              recognizer.onCancel = cancel;
            },
          ),
    },
    child: !widget.opensPlayer ? TrackMotion(controller: widget.controller, child: widget.child) : ClipRect(child: LayoutBuilder(builder: (context, bounds) {
      final v = waveVisuals(context), width = bounds.maxWidth;
      return Stack(clipBehavior: Clip.none, children: [
        AnimatedContainer(duration: axis == Axis.horizontal ? Duration.zero : const Duration(milliseconds: 260), curve: Curves.easeOutCubic, transform: Matrix4.translationValues(swipe, 0, 0), child: TrackMotion(controller: widget.controller, child: widget.child)),
        if (preview != null) Positioned.fill(child: IgnorePointer(child: ExcludeSemantics(child: AnimatedContainer(
          key: const Key('mini-swipe-preview'), duration: axis == Axis.horizontal ? Duration.zero : const Duration(milliseconds: 260), curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(swipe + previewSide * width, 0, 0),
          child: Row(children: [
            Artwork(controller: widget.controller, url: preview!.artwork, size: 44, radius: 8),
            const SizedBox(width: 10),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(preview!.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: v.onPlayer, fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(preview!.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: v.onPlayer.withValues(alpha: .7), fontSize: 10)),
            ])),
          ]),
        )))),
      ]);
    })),
  );
}
