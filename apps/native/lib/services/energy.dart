import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A device preference, independent of account subscription and server settings.
/// Only visual work is reduced. Audio and platform media controls keep running.
class EnergyPolicy extends ChangeNotifier {
  static const channel = MethodChannel('tech.gluk.glukwave/energy');
  final Future<Map<String, dynamic>?> Function() readSystem;
  final bool mobile;
  SharedPreferences? _preferences;
  Timer? _timer;
  bool _disposed = false, _foreground = true, _reading = false;
  String mode = 'auto';
  bool systemSaving = false, charging = false;
  int? battery;
  EnergyPolicy({
    Future<Map<String, dynamic>?> Function()? readSystem,
    bool? mobile,
  }) : readSystem =
           readSystem ??
           (() => channel.invokeMapMethod<String, dynamic>('snapshot')),
       mobile = mobile ?? (Platform.isAndroid || Platform.isIOS);
  bool get saving =>
      mode == 'on' ||
      mode == 'auto' &&
          mobile &&
          (systemSaving || battery != null && battery! <= 20 && !charging);
  Future<void> initialize(SharedPreferences preferences) async {
    _preferences = preferences;
    final saved = preferences.getString('glukwave-energy');
    mode = ['auto', 'on', 'off'].contains(saved) ? saved! : 'auto';
    await refresh();
    _schedule();
  }

  Future<void> setMode(String value) async {
    if (!['auto', 'on', 'off'].contains(value)) {
      throw ArgumentError.value(value, 'mode');
    }
    if (_disposed || mode == value) return;
    mode = value;
    notifyListeners();
    await _preferences?.setString('glukwave-energy', value);
    if (value == 'auto') await refresh();
  }

  void foreground(bool value) {
    if (_disposed || _foreground == value) return;
    _foreground = value;
    _schedule();
    if (value) unawaited(refresh());
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_disposed && mobile && _foreground) {
      _timer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => unawaited(refresh()),
      );
    }
  }

  Future<void> refresh() async {
    if (_disposed || !mobile || !_foreground || _reading) return;
    _reading = true;
    try {
      final data = await readSystem();
      if (_disposed || data == null) return;
      final previous = (saving, systemSaving, charging, battery);
      systemSaving = data['saving'] == true;
      charging = data['charging'] == true;
      final level = data['battery'];
      battery = level is num && level >= 0 && level <= 100
          ? level.round()
          : null;
      if (previous != (saving, systemSaving, charging, battery)) {
        notifyListeners();
      }
    } on MissingPluginException {
      /* Desktop and unsupported OS remain manual. */
    } on PlatformException {
      /* Keep last known policy; never interrupt audio. */
    } finally {
      _reading = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
