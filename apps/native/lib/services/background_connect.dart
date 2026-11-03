import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';

/// Keeps the existing authenticated transport alive; never opens another
/// socket or stores account credentials in the Android service.
class BackgroundConnectBridge {
  final MethodChannel channel;
  final bool supported;
  BackgroundConnectBridge({MethodChannel? channel, bool? supported})
    : channel =
          channel ??
          const MethodChannel('tech.gluk.glukwave/connect_background'),
      supported = supported ?? Platform.isAndroid;
  Future<void> Function()? onIdleTaskClosed;
  bool? _playback;
  void listen() {
    if (!supported) return;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'taskClosed') await onIdleTaskClosed?.call();
    });
    unawaited(channel.invokeMethod<void>('listen').catchError((Object _) {}));
  }

  Future<void> playback(bool active) async {
    if (!supported || _playback == active) return;
    _playback = active;
    try {
      await channel.invokeMethod<void>('playback', {'active': active});
    } catch (_) {
      if (_playback == active) _playback = null;
      rethrow;
    }
  }

  void dispose() {
    onIdleTaskClosed = null;
    if (supported) channel.setMethodCallHandler(null);
  }

  Future<bool> update(bool enabled, {bool explicit = false}) async {
    if (!supported) return enabled;
    return await channel.invokeMethod<bool>('update', {
          'enabled': enabled,
          'explicit': explicit,
        }) ??
        false;
  }
}
