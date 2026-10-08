import 'dart:math' as math;
import 'models.dart';

const equalizerFrequencies = <double>[
  31,
  62,
  125,
  250,
  500,
  1000,
  2000,
  4000,
  8000,
  16000,
];

/// Shared preference curve, independent of the number of hardware bands.
class WaveEqualizer {
  final bool enabled;
  final double preamp;
  final List<double> bands;
  const WaveEqualizer({
    this.enabled = false,
    this.preamp = 0,
    this.bands = const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  });
  WaveEqualizer merge(Json patch) {
    final incoming = patch['bands'];
    return WaveEqualizer(
      enabled: patch['enabled'] is bool ? patch['enabled'] as bool : enabled,
      preamp: finiteGain(patch['preamp'], preamp),
      bands: incoming is List && incoming.length == 10
          ? List<double>.unmodifiable(
              List.generate(
                10,
                (index) => finiteGain(incoming[index], bands[index]),
              ),
            )
          : bands,
    );
  }

  Json toJson() => {'enabled': enabled, 'preamp': preamp, 'bands': bands};
  double gainAt(double frequency) {
    if (!frequency.isFinite || frequency <= equalizerFrequencies.first) {
      return bands.first;
    }
    if (frequency >= equalizerFrequencies.last) return bands.last;
    for (var i = 1; i < equalizerFrequencies.length; i++) {
      if (frequency <= equalizerFrequencies[i]) {
        final t =
            math.log(frequency / equalizerFrequencies[i - 1]) /
            math.log(equalizerFrequencies[i] / equalizerFrequencies[i - 1]);
        return bands[i - 1] + (bands[i] - bands[i - 1]) * t;
      }
    }
    return 0;
  }
}

double finiteGain(dynamic input, [double fallback = 0]) =>
    input is num && input.isFinite ? input.toDouble().clamp(-12, 12) : fallback;

const equalizerPresets = <String, WaveEqualizer>{
  'flat': WaveEqualizer(enabled: true),
  'warm': WaveEqualizer(
    enabled: true,
    preamp: -3,
    bands: [3, 3, 2, 1, 0, 0, -1, -1, -2, -2],
  ),
  'vocal': WaveEqualizer(
    enabled: true,
    preamp: -3,
    bands: [-3, -2, -1, 0, 2, 3, 3, 2, 0, -1],
  ),
  'bass': WaveEqualizer(
    enabled: true,
    preamp: -5,
    bands: [5, 4, 3, 1, 0, 0, 0, 0, -1, -1],
  ),
  'bright': WaveEqualizer(
    enabled: true,
    preamp: -3,
    bands: [-2, -1, 0, 0, 0, 1, 2, 3, 3, 2],
  ),
};
