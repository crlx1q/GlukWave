import 'dart:math' as math;
import '../core/parity.dart';

abstract interface class WindowsDspOutput {
  String? get sourceUri;
  Future<void> applyEqualizer(bool enabled, double preamp, List<double> bands);
  Future<void> release();
}

/// This boundary is also used by the real mpv player, so tests can prove the
/// exact native property write and error propagation without opening hardware.
Future<void> writeWindowsEqualizer(
  Future<void> Function(String, String) setProperty,
  bool enabled,
  double preamp,
  List<double> bands, {
  double volume = 1,
}) async {
  final base = volume.isFinite ? volume.clamp(0, 1).toDouble() : 0.0;
  try {
    await setProperty('af', windowsEqualizerFilter(enabled, preamp, bands));
    await setProperty('volume-max', '400');
    await setProperty(
      'volume',
      (base * 100 * windowsEqualizerGain(enabled, preamp)).toStringAsFixed(4),
    );
  } catch (_) {
    // A rejected effect must leave music at the user's normal volume.
    try {
      await setProperty('af', '');
    } catch (_) {}
    try {
      await setProperty('volume', (base * 100).toStringAsFixed(4));
    } catch (_) {}
    rethrow;
  }
}

double windowsEqualizerGain(bool enabled, double preamp) =>
    enabled && preamp.isFinite
    ? math.pow(10, preamp.clamp(-12, 12) / 20).toDouble()
    : 1.0;
