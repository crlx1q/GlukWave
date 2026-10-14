import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/services/audio_config.dart';

void main() {
  test(
    'production media service configuration constructs with assertions on',
    () {
      // The failed +23 combination is rejected before the audio handler starts.
      expect(
        () => AudioServiceConfig(
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: false,
        ),
        throwsAssertionError,
      );
      final config = waveAudioServiceConfig('Музыка');
      expect(config.androidNotificationChannelName, 'Музыка');
      expect(config.androidNotificationIcon, 'drawable/ic_notification');
      expect(config.androidNotificationOngoing, isTrue);
      expect(config.androidStopForegroundOnPause, isTrue);
    },
  );
}
