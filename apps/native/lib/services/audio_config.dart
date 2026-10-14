import 'package:audio_service/audio_service.dart';

/// Connect has its own foreground service while paused. The media service
/// returns to lower priority so these flags also satisfy audio_service's
/// constructor invariant in debug builds.
AudioServiceConfig waveAudioServiceConfig(String channelName) =>
    AudioServiceConfig(
      androidNotificationChannelId: 'tech.gluk.glukwave.audio',
      androidNotificationChannelName: channelName,
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'drawable/ic_notification',
    );
