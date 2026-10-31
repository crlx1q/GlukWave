import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

/// One physical toggle gesture resolves locally; explicit play/pause calls are
/// deliberately not counted because they are idempotent transport commands.
class MediaButtonGesture {
  final Future<void> Function(int count) dispatch;
  final Duration quiet;
  Timer? timer;
  int count = 0;
  Object? scope;
  MediaButtonGesture(
    this.dispatch, {
    this.quiet = const Duration(milliseconds: 350),
  });
  void press(Object nextScope) {
    if (scope != nextScope) {
      cancel();
      scope = nextScope;
    }
    count = (count + 1).clamp(1, 3);
    timer?.cancel();
    timer = Timer(quiet, () {
      final value = count;
      count = 0;
      timer = null;
      unawaited(dispatch(value));
    });
  }

  void cancel() {
    timer?.cancel();
    timer = null;
    count = 0;
  }

  void dispose() => cancel();
}

class WindowsMediaButton {
  static const channel = MethodChannel('tech.gluk.glukwave/media_button');
  final MediaButtonGesture gesture;
  bool enabled = false, available = false, _disposed = false;
  Object? scope;
  WindowsMediaButton(Future<void> Function(int count) dispatch)
    : gesture = MediaButtonGesture(dispatch) {
    if (Platform.isWindows) {
      channel.setMethodCallHandler((call) async {
        if (call.method == 'press' && enabled && !_disposed) {
          gesture.press(scope ?? '');
        }
      });
    }
  }
  Future<void> update(bool value, Object nextScope) async {
    if (_disposed || !Platform.isWindows) return;
    if (scope != nextScope) {
      gesture.cancel();
      scope = nextScope;
    }
    if (enabled == value) return;
    enabled = value;
    if (!value) gesture.cancel();
    try {
      available =
          await channel.invokeMethod<bool>('setEnabled', value) ?? false;
    } on MissingPluginException {
      available = false;
    } on PlatformException {
      available = false;
    }
  }

  void dispose() {
    _disposed = true;
    gesture.dispose();
    if (Platform.isWindows) {
      unawaited(
        channel
            .invokeMethod<bool>('setEnabled', false)
            .catchError((_) => false),
      );
      channel.setMethodCallHandler(null);
    }
  }
}
