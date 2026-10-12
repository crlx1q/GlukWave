import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Drafts stay on this device. Only release or a quiet keyboard/wheel gesture
/// commits; changing the output/track scope discards an unfinished draft.
class DraftSlider extends StatefulWidget {
  final double value, min, max;
  final ValueChanged<double>? onChanged;
  final Object? scope;
  final bool wheel;
  final Key? sliderKey;
  const DraftSlider({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 1,
    this.onChanged,
    this.scope,
    this.wheel = false,
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
    if (!dragging && old.value != widget.value) draft = null;
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
    setState(() => draft = value);
    settle?.cancel();
    if (!dragging) settle = Timer(const Duration(milliseconds: 260), commit);
  }

  @override
  void dispose() {
    settle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerCancel: (_) {
      settle?.cancel();
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
                    event.scrollDelta.dy / 1200 * (widget.max - widget.min))
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
  final ValueChanged<double>? onChanged;
  final Object? scope;
  const VolumeSlider({
    super.key,
    required this.value,
    this.onChanged,
    this.scope,
  });
  @override
  Widget build(BuildContext context) => DraftSlider(
    value: value,
    onChanged: onChanged,
    scope: scope,
    wheel: true,
  );
}
