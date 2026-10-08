import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/volume_store.dart';

void main() {
  test('Native and QR challenges accept the server epoch and legacy ISO', () {
    const epoch = 1791484000123;
    expect(challengeExpiry(epoch).millisecondsSinceEpoch, epoch);
    expect(challengeExpiry('$epoch').millisecondsSinceEpoch, epoch);
    expect(
      challengeExpiry(
        DateTime.fromMillisecondsSinceEpoch(
          epoch,
          isUtc: true,
        ).toIso8601String(),
      ).millisecondsSinceEpoch,
      epoch,
    );
    expect(() => challengeExpiry(null), throwsFormatException);
    expect(() => challengeExpiry(double.nan), throwsFormatException);
  });
  test(
    'Volume survives recreation, preserves mute and serializes changes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = DeviceVolumeStore(prefs);
      expect(store.value, .8);
      await Future.wait([store.save(.3), store.save(.6), store.save(0)]);
      expect(DeviceVolumeStore(prefs).value, 0);
      await store.save(7);
      expect(DeviceVolumeStore(prefs).value, 1);
      await store.save(double.nan);
      expect(DeviceVolumeStore(prefs).value, 1);
    },
  );
}
