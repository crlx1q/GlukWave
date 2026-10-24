import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'theme.dart';

double wheelVolumeStep(double value, double delta) {
  if (delta == 0 || !delta.isFinite) return value.clamp(0, 1);
  final ticks = value.clamp(0, 1) * 20;
  return ((delta < 0 ? (ticks + 1e-7).floor() + 1 : (ticks - 1e-7).ceil() - 1) /
          20)
      .clamp(0, 1);
}

/// Drafts stay on this device. Only release or a quiet keyboard/wheel gesture
/// commits; changing the output/track scope discards an unfinished draft.
class DraftSlider extends StatefulWidget {
  final double value, min, max;
  final ValueChanged<double>? onChanged, onPreview;
  final VoidCallback? onCancel;
  final Object? scope;
  final bool wheel;
  final double? step;
  final double? wheelStep;
  final bool hoverHint;
  final Key? sliderKey;
  const DraftSlider({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 1,
    this.onChanged,
    this.onPreview,
    this.onCancel,
    this.scope,
    this.wheel = false,
    this.step,
    this.wheelStep,
    this.hoverHint = false,
    this.sliderKey,
  });
  @override
  State<DraftSlider> createState() => _DraftSliderState();
}

class _DraftSliderState extends State<DraftSlider> with WidgetsBindingObserver {
  double? draft;
  Timer? settle;
  bool dragging = false;
  Timer? hoverDelay;
  final hint = OverlayPortalController();
  final sliderBox = GlobalKey();
  late final FocusNode focus = FocusNode(onKeyEvent: handleKey);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    focus.addListener(() {
      if (!focus.hasFocus) hideHint();
    });
  }

  void hideHint() {
    hoverDelay?.cancel();
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) hint.hide();
      });
    } else {
      hint.hide();
    }
  }

  void startHint() {
    if (!widget.hoverHint || widget.onChanged == null) return;
    hoverDelay?.cancel();
    hoverDelay = Timer(const Duration(seconds: 1), () {
      if (mounted) hint.show();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) hideHint();
  }

  KeyEventResult handleKey(FocusNode node, KeyEvent event) {
    if (widget.wheelStep == null ||
        widget.onChanged == null ||
        event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      hideHint();
      return KeyEventResult.handled;
    }
    if (![
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
    ].contains(key)) {
      return KeyEventResult.ignored;
    }
    final positive =
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowRight;
    change(
      ((draft ?? widget.value) + (positive ? 1 : -1) * (widget.step ?? .02))
          .clamp(widget.min, widget.max),
      snap: false,
    );
    return KeyEventResult.handled;
  }

  @override
  void didUpdateWidget(DraftSlider old) {
    super.didUpdateWidget(old);
    if (!dragging && settle?.isActive != true && old.value != widget.value) {
      draft = null;
    }
    if (old.scope != widget.scope ||
        old.onChanged != null && widget.onChanged == null ||
        old.max != widget.max) {
      settle?.cancel();
      draft = null;
      dragging = false;
      hideHint();
    }
  }

  void commit() {
    settle?.cancel();
    final value = draft;
    if (value != null && widget.onChanged != null) widget.onChanged!(value);
    if (mounted) {
      setState(() {
        dragging = false;
      });
    }
  }

  void change(double value, {bool snap = true}) {
    final step = widget.step;
    if (snap && step != null) {
      value = ((value / step).round() * step).clamp(widget.min, widget.max);
    }
    setState(() => draft = value);
    widget.onPreview?.call(value);
    settle?.cancel();
    if (!dragging) settle = Timer(const Duration(milliseconds: 260), commit);
  }

  @override
  void dispose() {
    if (dragging || settle?.isActive == true) {
      final cancel = widget.onCancel;
      if (cancel != null) scheduleMicrotask(cancel);
    }
    settle?.cancel();
    hoverDelay?.cancel();
    focus.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: hint,
    overlayChildBuilder: (context) {
      final box = sliderBox.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return const SizedBox.shrink();
      final theme = SliderTheme.of(context), v = waveVisuals(context);
      final effective = theme.copyWith(
        thumbShape: theme.thumbShape ?? const RoundSliderThumbShape(),
        overlayShape: theme.overlayShape ?? const RoundSliderOverlayShape(),
        trackHeight: theme.trackHeight ?? 4,
      );
      final track = (theme.trackShape ?? const RoundedRectSliderTrackShape())
          .getPreferredRect(
            parentBox: box,
            sliderTheme: effective,
            isEnabled: widget.onChanged != null,
            isDiscrete: false,
          );
      var ratio =
          ((draft ?? widget.value) - widget.min) / (widget.max - widget.min);
      if (Directionality.of(context) == TextDirection.rtl) ratio = 1 - ratio;
      final global = box.localToGlobal(
        Offset(
          track.left + track.width * ratio.clamp(0, 1),
          track.center.dy - 12,
        ),
      );
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox;
      final point = overlay.globalToLocal(global),
          width = 48 * MediaQuery.textScalerOf(context).scale(1);
      return Positioned(
        left: (point.dx - width / 2).clamp(6, overlay.size.width - width - 6),
        top: point.dy.clamp(6, overlay.size.height - 6),
        width: width,
        child: FractionalTranslation(
          translation: const Offset(0, -1),
          child: IgnorePointer(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: v.reducedMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 140),
              builder: (_, value, child) =>
                  Opacity(opacity: value, child: child),
              child: Container(
                key: const Key('volume-thumb-hint'),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: v.surface,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: v.line),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  '${((draft ?? widget.value) * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: v.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    child: MouseRegion(
      onEnter: (_) => startHint(),
      onExit: (_) => hideHint(),
      child: Listener(
        onPointerCancel: (_) {
          settle?.cancel();
          hideHint();
          widget.onCancel?.call();
          setState(() {
            draft = null;
            dragging = false;
          });
        },
        onPointerSignal: (event) {
          if (widget.wheel &&
              event is PointerScrollEvent &&
              event.scrollDelta.dy != 0 &&
              widget.onChanged != null) {
            GestureBinding.instance.pointerSignalResolver.register(event, (_) {
              if (widget.wheelStep != null) {
                final next = wheelVolumeStep(
                  draft ?? widget.value,
                  event.scrollDelta.dy,
                );
                if (next != (draft ?? widget.value)) change(next, snap: false);
                return;
              }
              change(
                ((draft ?? widget.value) -
                        (widget.step != null
                            ? event.scrollDelta.dy.sign * widget.step!
                            : event.scrollDelta.dy /
                                  1200 *
                                  (widget.max - widget.min)))
                    .clamp(widget.min, widget.max),
              );
            });
          }
        },
        child: SizedBox(
          key: sliderBox,
          child: Slider(
            focusNode: focus,
            key: widget.sliderKey,
            value: (draft ?? widget.value).clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            divisions: widget.step == null || widget.wheelStep != null
                ? null
                : ((widget.max - widget.min) / widget.step!).round(),
            onChangeStart: widget.onChanged == null
                ? null
                : (_) {
                    settle?.cancel();
                    dragging = true;
                  },
            onChanged: widget.onChanged == null ? null : change,
            onChangeEnd: widget.onChanged == null ? null : (_) => commit(),
          ),
        ),
      ),
    ),
  );
}

class VolumeSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged, onPreview;
  final VoidCallback? onCancel;
  final Object? scope;
  final bool hoverHint;
  const VolumeSlider({
    super.key,
    required this.value,
    this.onChanged,
    this.onPreview,
    this.onCancel,
    this.scope,
    this.hoverHint = false,
  });
  @override
  Widget build(BuildContext context) => DraftSlider(
    value: value,
    onChanged: onChanged,
    onPreview: onPreview,
    onCancel: onCancel,
    scope: scope,
    wheel: true,
    step: .02,
    wheelStep: .05,
    hoverHint: hoverHint,
  );
}
