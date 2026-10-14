import 'dart:io';
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
  Future<bool> update(bool enabled, {bool explicit = false}) async {
    if (!supported) return enabled;
    return await channel.invokeMethod<bool>('update', {
          'enabled': enabled,
          'explicit': explicit,
        }) ??
        false;
  }
}
