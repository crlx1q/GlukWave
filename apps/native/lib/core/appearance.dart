import '../l10n/wave_localizations.dart';
import 'models.dart';
import 'equalizer.dart';

String normalizeHex(String value) {
  var hex = value.trim().toLowerCase();
  if (!hex.startsWith('#')) hex = '#$hex';
  if (RegExp(r'^#[0-9a-f]{3}$').hasMatch(hex)) {
    hex = '#${hex[1]}${hex[1]}${hex[2]}${hex[2]}${hex[3]}${hex[3]}';
  }
  if (!RegExp(r'^#[0-9a-f]{6}$').hasMatch(hex)) {
    throw FormatException(wt('native.644d7351d1'));
  }
  return hex;
}

/// A presentation patch changes only the controls the user actually edited.
/// Keeping it sparse preserves the other palette when another device edits it.
Json mergeAppearancePatch(Json previous, Json changes) => {
  ...previous,
  for (final entry in changes.entries)
    entry.key: entry.value is Map && previous[entry.key] is Map
        ? mergeAppearancePatch(object(previous[entry.key]), object(entry.value))
        : entry.value,
};

/// Keep edits made while a request was in flight, including a newer value of
/// the same field. Already acknowledged values must not overwrite later edits
/// from another device on the next retry.
Json unacknowledgedAppearancePatch(Json pending, Json acknowledged) {
  final remaining = <String, dynamic>{};
  for (final entry in pending.entries) {
    final sent = acknowledged[entry.key];
    if (entry.value is Map && sent is Map) {
      final children = unacknowledgedAppearancePatch(
        object(entry.value),
        object(sent),
      );
      if (children.isNotEmpty) remaining[entry.key] = children;
    } else if (!acknowledged.containsKey(entry.key) || entry.value != sent) {
      remaining[entry.key] = entry.value;
    }
  }
  return remaining;
}

Json presentationPatch(Json changes, WaveCustomization normalized) {
  final settings = normalized.toSettings();
  final result = <String, dynamic>{};
  for (final key in ['theme', 'reducedMotion', 'language', 'playbackRate']) {
    if (changes.containsKey(key)) result[key] = settings[key];
  }
  if (changes['equalizer'] is Map) {
    final changed = object(changes['equalizer']);
    result['equalizer'] = {
      for (final key in ['enabled', 'preamp', 'bands'])
        if (changed.containsKey(key)) key: object(settings['equalizer'])[key],
    };
  }
  if (changes['appearance'] is Map) {
    final changed = object(changes['appearance']);
    final appearance = object(settings['appearance']);
    result['appearance'] = {
      for (final key in [
        'radius',
        'speed',
        'compact',
        'blur',
        'waveStyle',
        'cover3d',
        'coverKind',
      ])
        if (changed.containsKey(key)) key: appearance[key],
      for (final mode in ['light', 'dark', 'amoled'])
        if (changed[mode] is Map)
          mode: {
            for (final key in ['bg', 'surface', 'ink', 'accent'])
              if (object(changed[mode]).containsKey(key))
                key: object(appearance[mode])[key],
          },
    };
  }
  return result;
}

class WavePalette {
  final String bg, surface, ink, accent;
  const WavePalette(this.bg, this.surface, this.ink, this.accent);
  static const light = WavePalette('#efede3', '#f8f7f1', '#302f2c', '#a08369');
  static const dark = WavePalette('#141517', '#202225', '#eeeae3', '#b1a2de');
  static const amoled = WavePalette('#000000', '#0b0b0b', '#f4f1f7', '#b1a2de');
  Json toJson() => {'bg': bg, 'surface': surface, 'ink': ink, 'accent': accent};
  WavePalette merge(Json values) {
    String color(String key, String fallback) {
      if (values[key] is! String) return fallback;
      try {
        return normalizeHex(values[key] as String);
      } on FormatException {
        return fallback;
      }
    }

    return WavePalette(
      color('bg', bg),
      color('surface', surface),
      color('ink', ink),
      color('accent', accent),
    );
  }
}

class WaveAppearance {
  final WavePalette light, dark, amoled;
  final double radius, speed;
  final bool compact, blur, cover3d;
  final String waveStyle, coverKind;
  const WaveAppearance({
    this.light = WavePalette.light,
    this.dark = WavePalette.dark,
    this.amoled = WavePalette.amoled,
    this.radius = 24,
    this.speed = 1,
    this.compact = false,
    this.blur = true,
    this.waveStyle = 'silk',
    this.cover3d = true,
    this.coverKind = 'vinyl',
  });
  Json toJson() => {
    'light': light.toJson(),
    'dark': dark.toJson(),
    'amoled': amoled.toJson(),
    'radius': radius,
    'speed': speed,
    'compact': compact,
    'blur': blur,
    'waveStyle': waveStyle,
    'cover3d': cover3d,
    'coverKind': coverKind,
  };
  WaveAppearance merge(Json values) => WaveAppearance(
    light: light.merge(object(values['light'])),
    dark: dark.merge(object(values['dark'])),
    amoled: amoled.merge(object(values['amoled'])),
    radius: number(values['radius'], radius).clamp(8, 38).toDouble(),
    speed: number(values['speed'], speed).clamp(.3, 2).toDouble(),
    compact: values['compact'] is bool ? values['compact'] as bool : compact,
    blur: values['blur'] is bool ? values['blur'] as bool : blur,
    waveStyle: ['silk', 'particles', 'bloom'].contains(values['waveStyle'])
        ? values['waveStyle'] as String
        : waveStyle,
    cover3d: values['cover3d'] is bool ? values['cover3d'] as bool : cover3d,
    coverKind: ['vinyl', 'cd'].contains(values['coverKind'])
        ? values['coverKind'] as String
        : coverKind,
  );
}

class WaveCustomization {
  final String theme;
  final String language;
  final WaveAppearance appearance;
  final bool reducedMotion;
  final WaveEqualizer equalizer;
  final double playbackRate;
  const WaveCustomization({
    this.theme = 'light',
    this.language = 'auto',
    this.appearance = const WaveAppearance(),
    this.reducedMotion = false,
    this.equalizer = const WaveEqualizer(),
    this.playbackRate = 1,
  });
  factory WaveCustomization.fromSettings(Json settings) =>
      const WaveCustomization().merge(settings);
  WaveCustomization merge(Json settings) => WaveCustomization(
    language:
        [
          'auto',
          'en',
          'ru',
          'kk',
          'uk',
          'de',
          'es',
        ].contains(settings['language'])
        ? settings['language'] as String
        : language,
    theme: ['light', 'dark', 'amoled', 'system'].contains(settings['theme'])
        ? settings['theme'] as String
        : theme,
    appearance: appearance.merge(object(settings['appearance'])),
    reducedMotion: settings['reducedMotion'] is bool
        ? settings['reducedMotion'] as bool
        : reducedMotion,
    equalizer: equalizer.merge(object(settings['equalizer'])),
    playbackRate:
        settings['playbackRate'] is num &&
            (settings['playbackRate'] as num).isFinite
        ? (settings['playbackRate'] as num).toDouble().clamp(.5, 2)
        : playbackRate,
  );
  Json toSettings() => {
    'language': language,
    'theme': theme,
    'appearance': appearance.toJson(),
    'reducedMotion': reducedMotion,
    'equalizer': equalizer.toJson(),
    'playbackRate': playbackRate,
  };
  Json resetPalette(String mode) => {
    'appearance': {
      mode:
          (mode == 'amoled'
                  ? WavePalette.amoled
                  : mode == 'dark'
                  ? WavePalette.dark
                  : WavePalette.light)
              .toJson(),
      'radius': 24,
      'speed': 1,
      'compact': false,
      'blur': true,
      'waveStyle': 'silk',
      'cover3d': true,
      'coverKind': 'vinyl',
    },
    'reducedMotion': false,
  };
}
