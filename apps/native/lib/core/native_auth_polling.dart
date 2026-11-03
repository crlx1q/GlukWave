import 'dart:async';
import 'package:dio/dio.dart';
import 'api.dart';
import 'models.dart';
import '../l10n/wave_localizations.dart';

typedef NativeAuthRead =
    Future<Json> Function(CancelToken cancellation, Duration timeout);

/// A browser approval is one flow, even across temporary mobile-network errors.
/// Only safe status reads repeat; credentials and approval POSTs never repeat.
class NativeAuthPolling {
  final DateTime Function() now;
  final Future<void> Function(Duration) delay;
  CancelToken? _request;
  bool _cancelled = false;
  NativeAuthPolling({
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  }) : now = now ?? DateTime.now,
       delay = delay ?? Future<void>.delayed;

  void cancel() {
    _cancelled = true;
    _request?.cancel('Native login cancelled');
  }

  bool _temporary(Object error) =>
      error is WaveException &&
      ((error.status == null &&
              ['network', 'AUTH_POLL_TIMEOUT'].contains(error.code)) ||
          [408, 500, 502, 503, 504].contains(error.status));

  Future<Json> wait({
    required DateTime expires,
    required bool Function() current,
    required NativeAuthRead read,
  }) async {
    var failures = 0;
    bool active() => !_cancelled && current();
    while (active() && now().isBefore(expires)) {
      final remaining = expires.difference(now());
      final timeout = remaining < const Duration(seconds: 10)
          ? remaining
          : const Duration(seconds: 10);
      final cancellation = CancelToken();
      _request = cancellation;
      try {
        final data = await read(cancellation, timeout);
        if (!active()) break;
        failures = 0;
        if (data['status'] == 'approved') return data;
        if (data['status'] == 'expired') break;
      } catch (error) {
        if (!active()) break;
        if (!_temporary(error)) rethrow;
        failures++;
      } finally {
        if (identical(_request, cancellation)) _request = null;
      }
      if (!active() || !now().isBefore(expires)) break;
      const steps = [2, 3, 5];
      final pause = Duration(seconds: steps[failures.clamp(0, 2)]);
      final budget = expires.difference(now());
      await delay(pause < budget ? pause : budget);
    }
    throw WaveException(
      wt('native.b85fd36bb6'),
      active() ? 'CHALLENGE_EXPIRED' : 'AUTH_CANCELLED',
    );
  }
}
