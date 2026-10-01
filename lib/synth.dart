import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

class SynthController {
  final ValueNotifier<double> wave = ValueNotifier<double>(0.0);

  Timer? _timer;
  double _phase = 0;
  bool _lofi = false;

  bool get isRunning => _timer != null;

  void start() {
    _timer ??= Timer.periodic(const Duration(milliseconds: 60), (_) {
      _phase += _lofi ? 0.18 : 0.32;
      final value = sin(_phase) * (_lofi ? 0.55 : 0.9);
      wave.value = value;
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    wave.value = 0;
  }

  void setLofi(bool enabled) {
    _lofi = enabled;
  }

  void dispose() {
    stop();
    wave.dispose();
  }
}
