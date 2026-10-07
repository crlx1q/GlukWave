import 'dart:math' as math;
import 'models.dart';

/// Constants and equations shared with apps/web/src/wave-math.ts.
const bloomTurn = .32,
    bloomRest = .78,
    bloomSwell = 1.1,
    bloomCap = .55,
    bloomReach = .32,
    bloomPhase = .8,
    bloomCell = 6.0;
double clamp01(double value) => value.isFinite ? value.clamp(0, 1) : 0;
double smoothstep(double a, double b, double value) {
  final t = clamp01((value - a) / (b - a));
  return t * t * (3 - 2 * t);
}

double bloomField(double u, double v, double phase, double energy) {
  final e = clamp01(energy), envelope = math.sin(math.pi * u);
  final centre =
      .52 +
      math.sin(u * 7.54 + phase * .65) * .145 +
      math.sin(u * 13.19 - phase * .38) * .065;
  final width = (.042 + .012 * math.sin(u * 9.42 + phase * .23)) * (1 + e * .3);
  double band(double offset, double scale) =>
      math.exp(-math.pow((v - centre - offset) / (width * scale), 2) * .65);
  return clamp01(
    (.82 * band(0, 1) +
            .27 * band(.11 * math.sin(u * 5.2 - phase * .24) + .075, .68) +
            .2 * band(-.1, .6)) *
        (.35 + .65 * envelope) *
        (1 + e * .25),
  );
}

({double level, double radius, double presence}) bloomDot(
  double u,
  double v,
  double phase,
  double energy,
  double pointerX,
  double pointerY,
  double pointerActive,
  double aspect,
) {
  final level = bloomField(u, v, phase, energy),
      dx = (u - pointerX) * aspect / bloomReach,
      dy = (v - pointerY) / bloomReach;
  final influence = clamp01(pointerActive) * math.exp(-dx * dx - dy * dy);
  return (
    level: level,
    radius: math.min(
      bloomCap,
      math.sqrt(math.pow(level, .9) / math.pi) * (1 + bloomSwell * influence),
    ),
    presence:
        smoothstep(.03, .16, level) * bloomRest * (1 - influence) + influence,
  );
}

class AudioEnvelope {
  final bool available;
  final double duration;
  final List<double> samples;
  final String? source;
  const AudioEnvelope({
    this.available = false,
    this.duration = 0,
    this.samples = const [],
    this.source,
  });
  factory AudioEnvelope.fromJson(Json data) {
    final duration = number(data['duration']);
    final raw = data['samples'];
    final valid =
        data['available'] == true &&
        duration.isFinite &&
        duration > 0 &&
        raw is List &&
        raw.isNotEmpty &&
        raw.length <= 4096 &&
        raw.every((s) => s is num && s.isFinite && s >= 0 && s <= 1);
    return valid
        ? AudioEnvelope(
            available: true,
            duration: duration,
            samples: List<double>.unmodifiable(
              raw.map((s) => (s as num).toDouble()),
            ),
            source: data['source'] as String?,
          )
        : const AudioEnvelope();
  }
  Json toJson() => {
    'available': available,
    'duration': duration,
    'samples': samples,
    'source': source,
  };
  double at(double position, bool playing) {
    if (!playing || !available || duration <= 0 || samples.isEmpty) return 0;
    final index = clamp01(position / duration) * (samples.length - 1),
        low = index.floor(),
        high = math.min(samples.length - 1, low + 1),
        part = index - low;
    return clamp01(samples[low] * (1 - part) + samples[high] * part);
  }
}

double easeEnergy(double current, double target, double seconds) =>
    current +
    (target - current) *
        (1 -
            math.exp(-math.min(.07, seconds) / (target > current ? .08 : .24)));
