import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Musical status is a physical 1.2s loop. Appearance timeDilation changes
/// navigation, but must not speed up this clock. Ticker schedules repaints;
/// Stopwatch supplies elapsed real time independently of scaled frame stamps.
class PhysicalWaveClock extends Animation<double> with ChangeNotifier {
  static const cycle = Duration(milliseconds: 1200);
  final Duration period;
  final Stopwatch watch = Stopwatch();
  late final Ticker ticker;
  @override
  double get value =>
      (watch.elapsedMicroseconds % period.inMicroseconds) /
      period.inMicroseconds;
  PhysicalWaveClock(TickerProvider vsync, {this.period = cycle}) {
    ticker = vsync.createTicker((_) {
      notifyListeners();
    });
  }
  Duration get duration => period;
  @override
  bool get isAnimating => ticker.isActive;
  void repeat() {
    if (ticker.isActive) return;
    watch.start();
    ticker.start();
  }

  void stop() {
    watch.stop();
    ticker.stop();
  }

  @override
  AnimationStatus get status =>
      isAnimating ? AnimationStatus.forward : AnimationStatus.dismissed;
  @override
  bool get isCompleted => false;
  @override
  bool get isDismissed => !isAnimating;
  @override
  void addStatusListener(AnimationStatusListener listener) {}
  @override
  void removeStatusListener(AnimationStatusListener listener) {}
  @override
  void dispose() {
    watch.stop();
    ticker.dispose();
    super.dispose();
  }
}
