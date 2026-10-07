import 'dart:async';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../core/controller.dart';

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
  final bool opensPlayer;
  final VoidCallback? onVerticalStart, onVerticalCancel;
  final ValueChanged<double>? onVerticalUpdate, onVerticalEnd;
  const PlayerGestureSurface({
    super.key,
    required this.controller,
    required this.child,
    this.opensPlayer = false,
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
  void reset() {
    distance = Offset.zero;
    axis = null;
    acceptsVertical = false;
  }

  void cancel() {
    if (acceptsVertical) widget.onVerticalCancel?.call();
    reset();
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
    if (acceptsVertical) widget.onVerticalUpdate?.call(distance.dy);
  }

  void end(DragEndDetails details) {
    if (axis == Axis.horizontal &&
        (distance.dx.abs() > 56 ||
            (distance.dx.abs() > 12 &&
                details.velocity.pixelsPerSecond.dx.abs() > 700))) {
      final c = widget.controller;
      final index = c.audio.tracks.indexWhere(
        (track) => track.id == c.audio.current?.id,
      );
      final next = index + (distance.dx < 0 ? 1 : -1);
      if (c.canControl &&
          index >= 0 &&
          next >= 0 &&
          next < c.audio.tracks.length) {
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
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: {
      _PlayerPanRecognizer:
          GestureRecognizerFactoryWithHandlers<_PlayerPanRecognizer>(
            () => _PlayerPanRecognizer(opensPlayer: widget.opensPlayer),
            (recognizer) {
              recognizer.opensPlayer = widget.opensPlayer;
              recognizer.onDown = (_) => reset();
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
    child: widget.child,
  );
}
