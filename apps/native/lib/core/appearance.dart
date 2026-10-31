import '../l10n/wave_localizations.dart';
import 'models.dart';
import 'equalizer.dart';

bool requiresAdvancedAppearance(Json changes) {
  if (changes.containsKey('fontFamily')) return true;
  final appearance = object(changes['appearance']);
  for (final entry in appearance.entries) {
    if (![
      'light',
      'dark',
      'amoled',
      'coverAccent',
      'miniBackground',
    ].contains(entry.key)) {
      return true;
    }
    if (object(entry.value).keys.any((key) => key != 'accent')) return true;
  }
  return false;
}

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
  for (final key in [
    'theme',
    'reducedMotion',
    'language',
    'playbackRate',
    'fontFamily',
    'fontScale',
    'powerSaving',
    'savedThemes',
  ]) {
    if (changes.containsKey(key)) result[key] = settings[key];
  }
  if (changes['wallpaper'] is Map) {
    final changed = object(changes['wallpaper']);
    result['wallpaper'] = {
      for (final key in ['url', 'dim', 'blur'])
        if (changed.containsKey(key)) key: object(settings['wallpaper'])[key],
    };
  }
  if (changes['seasonalEffects'] is Map) {
    final changed = object(changes['seasonalEffects']);
    result['seasonalEffects'] = {
      for (final key in ['enabled', 'mode', 'intensity'])
        if (changed.containsKey(key))
          key: object(settings['seasonalEffects'])[key],
    };
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
        'coverAccent',
        'coverKind',
        'miniBackground',
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
  final bool compact, blur, cover3d, coverAccent;
  final String waveStyle, coverKind, miniBackground;
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
    this.coverAccent = true,
    this.coverKind = 'vinyl',
    this.miniBackground = 'cover',
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
    'coverAccent': coverAccent,
    'coverKind': coverKind,
    'miniBackground': miniBackground,
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
    coverAccent: values['coverAccent'] is bool
        ? values['coverAccent'] as bool
        : coverAccent,
    cover3d: values['cover3d'] is bool ? values['cover3d'] as bool : cover3d,
    miniBackground:
        ['cover', 'pixels', 'plain'].contains(values['miniBackground'])
        ? values['miniBackground'] as String
        : miniBackground,
    coverKind: ['vinyl', 'cd'].contains(values['coverKind'])
        ? values['coverKind'] as String
        : coverKind,
  );
}

class WaveSeasonalEffects {
  final bool enabled;
  final String mode, intensity;
  const WaveSeasonalEffects({
    this.enabled = false,
    this.mode = 'auto',
    this.intensity = 'subtle',
  });
  WaveSeasonalEffects merge(Json value) => WaveSeasonalEffects(
    enabled: value['enabled'] is bool ? value['enabled'] as bool : enabled,
    mode: ['auto', 'snow', 'rain', 'leaves', 'sun'].contains(value['mode'])
        ? value['mode'] as String
        : mode,
    intensity: ['subtle', 'normal'].contains(value['intensity'])
        ? value['intensity'] as String
        : intensity,
  );
  Json toJson() => {'enabled': enabled, 'mode': mode, 'intensity': intensity};
  String resolve([DateTime? date]) {
    if (mode != 'auto') return mode;
    final month = (date ?? DateTime.now()).month;
    return month == 12 || month <= 2
        ? 'snow'
        : month <= 5
        ? 'rain'
        : month <= 8
        ? 'sun'
        : 'leaves';
  }
}

class WaveCustomization {
  final String theme;
  final String language;
  final WaveAppearance appearance;
  final WaveSeasonalEffects seasonalEffects;
  final bool reducedMotion, powerSaving;
  final Json wallpaper;
  final List<Json> savedThemes;
  final WaveEqualizer equalizer;
  final double playbackRate;
  final String fontFamily;
  final double fontScale;
  const WaveCustomization({
    this.theme = 'light',
    this.language = 'auto',
    this.appearance = const WaveAppearance(),
    this.seasonalEffects = const WaveSeasonalEffects(),
    this.reducedMotion = false,
    this.powerSaving = false,
    this.wallpaper = const {'url': '', 'dim': .35, 'blur': 8},
    this.savedThemes = const [],
    this.equalizer = const WaveEqualizer(),
    this.playbackRate = 1,
    this.fontFamily = 'manrope',
    this.fontScale = 1,
  });
  factory WaveCustomization.fromSettings(Json settings) =>
      const WaveCustomization().merge(settings);
  WaveCustomization merge(Json settings) => WaveCustomization(
    powerSaving: settings['powerSaving'] is bool
        ? settings['powerSaving'] as bool
        : powerSaving,
    wallpaper: settings.containsKey('wallpaper')
        ? normalizeWallpaper({...wallpaper, ...object(settings['wallpaper'])})
        : wallpaper,
    savedThemes: settings.containsKey('savedThemes')
        ? normalizeSavedThemes(settings['savedThemes'])
        : savedThemes,
    seasonalEffects: seasonalEffects.merge(object(settings['seasonalEffects'])),
    fontFamily: ['manrope', 'nunito', 'system'].contains(settings['fontFamily'])
        ? settings['fontFamily'] as String
        : fontFamily,
    fontScale:
        settings['fontScale'] is num && (settings['fontScale'] as num).isFinite
        ? number(settings['fontScale'], fontScale).clamp(.85, 1.25)
        : fontScale,
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
    'seasonalEffects': seasonalEffects.toJson(),
    'reducedMotion': reducedMotion,
    'powerSaving': powerSaving,
    'wallpaper': wallpaper,
    'savedThemes': savedThemes,
    'equalizer': equalizer.toJson(),
    'playbackRate': playbackRate,
    'fontFamily': fontFamily,
    'fontScale': fontScale,
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

Json normalizeWallpaper(Json value) {
  final url = value['url']?.toString() ?? '';
  return {
    'url': RegExp(r'^/api/profile-assets/[A-Za-z0-9_-]+$').hasMatch(url)
        ? url
        : '',
    'dim': number(value['dim'], .35).clamp(0, .9),
    'blur': number(value['blur'], 8).clamp(0, 24),
  };
}

List<Json> normalizeSavedThemes(dynamic input) {
  if (input is! List) return [];
  final ids = <String>{}, result = <Json>[];
  for (final raw in input.take(12)) {
    final value = object(raw),
        id = value['id']?.toString() ?? '',
        name = value['name']?.toString().trim() ?? '',
        mode = value['mode'];
    if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(id) ||
        name.isEmpty ||
        name.length > 40 ||
        !['light', 'dark'].contains(mode) ||
        !ids.add(id)) {
      continue;
    }
    final colors = object(value['colors']);
    if (!['bg', 'surface', 'ink', 'accent'].every(
      (key) =>
          RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(colors[key]?.toString() ?? ''),
    )) {
      continue;
    }
    result.add({
      'id': id,
      'name': name,
      'mode': mode,
      'colors': {
        for (final key in ['bg', 'surface', 'ink', 'accent'])
          key: colors[key].toString().toLowerCase(),
      },
    });
  }
  return result;
}

const studioPalettes =
    <({String id, String name, String mode, WavePalette colors})>[
      (id: 'paper', name: 'Paper', mode: 'light', colors: WavePalette.light),
      (
        id: 'midnight',
        name: 'Midnight',
        mode: 'dark',
        colors: WavePalette('#202423', '#2c312f', '#edece2', '#a4b59c'),
      ),
      (
        id: 'sage',
        name: 'Sage',
        mode: 'light',
        colors: WavePalette('#e5e9dd', '#f2f4eb', '#323f35', '#7d9574'),
      ),
      (
        id: 'lilac',
        name: 'Lilac',
        mode: 'light',
        colors: WavePalette('#eae5ed', '#f6f1f8', '#44394b', '#aa89b7'),
      ),
      (
        id: 'sand',
        name: 'Sand',
        mode: 'light',
        colors: WavePalette('#eee4d7', '#faf3e9', '#46392f', '#bd845d'),
      ),
      (
        id: 'ocean',
        name: 'Ocean',
        mode: 'dark',
        colors: WavePalette('#101e29', '#1b2d3a', '#e2edf3', '#7eb4ca'),
      ),
      (
        id: 'rose',
        name: 'Rose',
        mode: 'light',
        colors: WavePalette('#eee1e3', '#fbf1f2', '#4c333b', '#b97c90'),
      ),
      (
        id: 'forest',
        name: 'Forest',
        mode: 'dark',
        colors: WavePalette('#121f1a', '#20322a', '#e3ede5', '#8cbaa0'),
      ),
    ];
