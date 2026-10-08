import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/appearance.dart';
import 'package:glukwave/core/equalizer.dart';

void main() {
  test(
    'Hardware center frequencies interpolate the shared curve in logarithmic space',
    () {
      const curve = WaveEqualizer(bands: [-12, -6, 0, 6, 12, 6, 0, -6, -12, 0]);
      expect(curve.gainAt(31), -12);
      expect(curve.gainAt(125), 0);
      expect(curve.gainAt(math.sqrt(125 * 250)), closeTo(3, 1e-10));
      expect(curve.gainAt(math.sqrt(8000 * 16000)), closeTo(-6, 1e-10));
      expect(curve.gainAt(20), -12);
      expect(curve.gainAt(20000), 0);
    },
  );

  test(
    'Sparse processing changes preserve synced bands and reject invalid values',
    () {
      final original = const WaveCustomization().merge({
        'equalizer': equalizerPresets['warm']!.toJson(),
        'playbackRate': 1.25,
      });
      final changed = original.merge({
        'equalizer': {'preamp': -40},
        'playbackRate': double.nan,
      });
      expect(changed.equalizer.enabled, isTrue);
      expect(changed.equalizer.bands, original.equalizer.bands);
      expect(changed.equalizer.preamp, -12);
      expect(changed.playbackRate, 1.25);
      expect(
        presentationPatch({
          'equalizer': {'preamp': -40},
        }, changed),
        {
          'equalizer': {'preamp': -12.0},
        },
      );
      final invalid = changed.merge({
        'equalizer': {
          'bands': [1, 2],
          'preamp': double.infinity,
        },
      });
      expect(invalid.equalizer.bands, changed.equalizer.bands);
      expect(invalid.equalizer.preamp, -12);
      expect(changed.merge({'playbackRate': 100}).playbackRate, 2);
    },
  );

  test(
    'Older two-theme settings migrate without losing palettes or resetting processing',
    () {
      final old = WaveCustomization.fromSettings({
        'theme': 'dark',
        'appearance': {
          'light': {'accent': '#abcdef'},
          'dark': {'bg': '#123456'},
        },
      });
      expect(old.appearance.amoled.toJson(), WavePalette.amoled.toJson());
      final edit = old.merge({
        'theme': 'amoled',
        'appearance': {
          'amoled': {'accent': '#fedcba'},
        },
        'equalizer': equalizerPresets['bass']!.toJson(),
      });
      expect(edit.appearance.amoled.bg, '#000000');
      expect(edit.appearance.light.accent, '#abcdef');
      expect(edit.appearance.dark.bg, '#123456');
      expect(
        presentationPatch({
          'appearance': {
            'amoled': {'accent': '#fedcba'},
          },
        }, edit),
        {
          'appearance': {
            'amoled': {'accent': '#fedcba'},
          },
        },
      );
      final reset = edit.merge(edit.resetPalette('amoled'));
      expect(reset.theme, 'amoled');
      expect(reset.appearance.amoled.toJson(), WavePalette.amoled.toJson());
      expect(reset.appearance.light.accent, '#abcdef');
      expect(reset.appearance.dark.bg, '#123456');
      expect(reset.equalizer.toJson(), edit.equalizer.toJson());
    },
  );
}
