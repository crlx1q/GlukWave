import 'package:flutter/material.dart';
import '../core/appearance.dart';

Color hexColor(String hex) =>
    Color(0xff000000 | int.parse(hex.substring(1), radix: 16));

class WaveVisuals extends ThemeExtension<WaveVisuals> {
  final Color background, surface, ink, accent;
  final Brightness brightness;
  final double radius, speed;
  final bool compact, blur, reducedMotion;
  final String waveStyle;
  const WaveVisuals({
    required this.background,
    required this.surface,
    required this.ink,
    required this.accent,
    required this.brightness,
    required this.radius,
    required this.speed,
    required this.compact,
    required this.blur,
    required this.reducedMotion,
    required this.waveStyle,
  });
  factory WaveVisuals.from(
    WaveCustomization customization,
    Brightness brightness,
  ) {
    final a = customization.appearance;
    final p = customization.theme == 'amoled'
        ? a.amoled
        : brightness == Brightness.dark
        ? a.dark
        : a.light;
    return WaveVisuals(
      background: hexColor(p.bg),
      surface: hexColor(p.surface),
      ink: hexColor(p.ink),
      accent: hexColor(p.accent),
      brightness: brightness,
      radius: a.radius,
      speed: a.speed,
      compact: a.compact,
      blur: a.blur,
      reducedMotion: customization.reducedMotion,
      waveStyle: a.waveStyle,
    );
  }
  Color get muted => Color.lerp(background, ink, .72)!;
  Color get accentSoft => Color.lerp(background, accent, .18)!;
  Color get line => ink.withValues(alpha: .11);
  Color get player => surface;
  Color get onPlayer => ink;
  double corners([double original = 24]) => radius * original / 24;
  Duration duration(int milliseconds) =>
      Duration(milliseconds: reducedMotion ? 0 : milliseconds);
  @override
  WaveVisuals copyWith({
    Color? background,
    Color? surface,
    Color? ink,
    Color? accent,
    Brightness? brightness,
    double? radius,
    double? speed,
    bool? compact,
    bool? blur,
    bool? reducedMotion,
    String? waveStyle,
  }) => WaveVisuals(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    ink: ink ?? this.ink,
    accent: accent ?? this.accent,
    brightness: brightness ?? this.brightness,
    radius: radius ?? this.radius,
    speed: speed ?? this.speed,
    compact: compact ?? this.compact,
    blur: blur ?? this.blur,
    reducedMotion: reducedMotion ?? this.reducedMotion,
    waveStyle: waveStyle ?? this.waveStyle,
  );
  @override
  WaveVisuals lerp(covariant WaveVisuals? other, double t) {
    if (other == null) return this;
    return other.copyWith(
      background: Color.lerp(background, other.background, t),
      surface: Color.lerp(surface, other.surface, t),
      ink: Color.lerp(ink, other.ink, t),
      accent: Color.lerp(accent, other.accent, t),
      radius: radius + (other.radius - radius) * t,
    );
  }
}

WaveVisuals waveVisuals(BuildContext context) =>
    Theme.of(context).extension<WaveVisuals>() ??
    WaveVisuals.from(const WaveCustomization(), Theme.of(context).brightness);
double waveRadius(BuildContext context, double original) =>
    waveVisuals(context).corners(original);

ThemeData buildWaveTheme(
  WaveCustomization customization,
  Brightness brightness,
) {
  final v = WaveVisuals.from(customization, brightness);
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(v.corners(16)),
  );
  final padding = EdgeInsets.symmetric(
    horizontal: v.compact ? 16 : 20,
    vertical: v.compact ? 11 : 16,
  );
  final border = OutlineInputBorder(
    borderSide: BorderSide(color: v.line),
    borderRadius: BorderRadius.circular(v.corners(14)),
  );
  return ThemeData(
    fontFamily: 'Manrope',
    fontFamilyFallback: const ['Nunito'],
    useMaterial3: true,
    brightness: brightness,
    extensions: [v],
    scaffoldBackgroundColor: v.background,
    canvasColor: v.background,
    visualDensity: v.compact ? VisualDensity.compact : VisualDensity.standard,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: v.accent,
          brightness: brightness,
        ).copyWith(
          primary: v.ink,
          secondary: v.accent,
          surface: v.surface,
          onPrimary: v.background,
          onSecondary: v.ink,
          onSurface: v.ink,
          surfaceContainer: v.surface,
          surfaceContainerHighest: v.accentSoft,
          outline: v.line,
        ),
    textTheme: TextTheme(
      bodyMedium: TextStyle(color: v.ink, fontSize: 14),
      bodySmall: TextStyle(color: v.muted, fontSize: 12),
    ),
    dividerColor: v.line,
    iconTheme: IconThemeData(color: v.ink, size: 22),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: v.ink,
        foregroundColor: v.background,
        padding: padding,
        shape: shape,
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontFamilyFallback: ['Nunito'],
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: v.ink,
        side: BorderSide(color: v.line),
        padding: padding,
        shape: shape,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: v.surface,
      isDense: v.compact,
      labelStyle: TextStyle(color: v.muted),
      hintStyle: TextStyle(color: v.muted),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: v.accent, width: 1.5),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: v.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(v.radius),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: v.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(v.radius)),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: v.accent,
      inactiveTrackColor: v.line,
      thumbColor: v.accent,
      trackHeight: 3,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? v.surface : v.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? v.ink : v.line,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: v.ink,
      contentTextStyle: TextStyle(
        fontFamily: 'Manrope',
        fontFamilyFallback: const ['Nunito'],
        color: v.background,
      ),
      behavior: SnackBarBehavior.floating,
      shape: shape,
    ),
  );
}

final waveTheme = buildWaveTheme(const WaveCustomization(), Brightness.light);
