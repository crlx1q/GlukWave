import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A wheel gesture over volume belongs to volume, rather than the page behind it.
class VolumeSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged;
  const VolumeSlider({super.key, required this.value, this.onChanged});
  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: (event) {
      if (event is PointerScrollEvent && onChanged != null) {
        GestureBinding.instance.pointerSignalResolver.register(event, (_) {
          onChanged!((value - event.scrollDelta.dy / 1200).clamp(0, 1));
        });
      }
    },
    child: Slider(value: value.clamp(0, 1), onChanged: onChanged),
  );
}
