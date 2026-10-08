import 'package:shared_preferences/shared_preferences.dart';

class DeviceVolumeStore {
  static const key = 'deviceVolume';
  final SharedPreferences preferences;
  Future<void> _writes = Future.value();
  DeviceVolumeStore(this.preferences);
  double get value {
    final saved = preferences.get(key);
    return saved is num && saved.isFinite ? saved.toDouble().clamp(0, 1) : .8;
  }

  Future<void> save(double value) {
    if (!value.isFinite) return Future.value();
    final bounded = value.clamp(0, 1).toDouble();
    // Slider and remote commands may overlap. Preserve their submission order.
    _writes = _writes.catchError((Object _) {}).then((_) async {
      await preferences.setDouble(key, bounded);
    });
    return _writes;
  }
}
