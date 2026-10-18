import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Drafts stay on this device. Only release or a quiet keyboard/wheel gesture
/// commits; changing the output/track scope discards an unfinished draft.
class DraftSlider extends StatefulWidget {
  final double value, min, max;
  final ValueChanged<double>? onChanged, onPreview;
  final VoidCallback? onCancel;
  final Object? scope;
  final bool wheel;
  final double? step;
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
    this.sliderKey,
  });
  @override
  State<DraftSlider> createState() => _DraftSliderState();
}

class _DraftSliderState extends State<DraftSlider> {
  double? draft;
  Timer? settle;
  bool dragging = false;
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

  void change(double value) {
    final step = widget.step;
    if (step != null) {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerCancel: (_) {
      settle?.cancel();
      widget.onCancel?.call();
      setState(() {
        draft = null;
        dragging = false;
      });
    },
    onPointerSignal: (event) {
      if (widget.wheel &&
          event is PointerScrollEvent &&
          widget.onChanged != null) {
        GestureBinding.instance.pointerSignalResolver.register(event, (_) {
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
    child: Slider(
      key: widget.sliderKey,
      value: (draft ?? widget.value).clamp(widget.min, widget.max),
      min: widget.min,
      max: widget.max,
      divisions: widget.step == null
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
  );
}

class VolumeSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged, onPreview;
  final VoidCallback? onCancel;
  final Object? scope;
  const VolumeSlider({
    super.key,
    required this.value,
    this.onChanged,
    this.onPreview,
    this.onCancel,
    this.scope,
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
  );
}
