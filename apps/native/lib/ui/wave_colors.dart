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
    Color tone(double scale, double lift) => Color.from(
      alpha: 1,
      red: accent.r * scale + lift,
      green: accent.g * scale + lift,
      blue: accent.b * scale + lift,
    );
    return SilkPalette(
      tone(dark ? .82 : .56, 0),
      tone(dark ? .68 : .76, dark ? .30 : .03),
    );
  }
  Color atDepth(double depth) {
    final d = depth.clamp(0.0, 1.0);
    return Color.lerp(base, highlight, d * d * d)!;
  }
}
