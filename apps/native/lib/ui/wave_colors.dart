import 'package:flutter/material.dart';

/// Matches web wave-colors.ts. Only pigment changes; the field, input and
/// measured music response are untouched.
class SilkPalette {
  final Color base, highlight;
  const SilkPalette(this.base, this.highlight);
  factory SilkPalette.from(Color accent, Color background) {
    final dark =
        background.r * .2126 + background.g * .7152 + background.b * .0722 <
        .48;
    final channels = [accent.r, accent.g, accent.b]..sort();
    final middle = (channels.first + channels.last) / 2;
    double pigment(double channel) =>
        (middle + (channel - middle) * 1.4).clamp(0, 1);
    Color tone(double scale, double lift) => Color.from(
      alpha: 1,
      red: pigment(accent.r) * scale + lift,
      green: pigment(accent.g) * scale + lift,
      blue: pigment(accent.b) * scale + lift,
    );
    return SilkPalette(
      tone(dark ? .88 : .50, 0),
      tone(dark ? .82 : .72, dark ? .17 : .02),
    );
  }
  Color atDepth(double depth) {
    final d = depth.clamp(0.0, 1.0);
    return Color.lerp(base, highlight, d * d * d)!;
  }
}
