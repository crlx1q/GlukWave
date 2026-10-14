import 'api.dart';

bool unavailableAudio(Object error) =>
    error is WaveException &&
    const {
      'AUDIO_UNAVAILABLE',
      'DIRECT_AUDIO_UNAVAILABLE',
      'AUDIO_MATCH_REJECTED',
    }.contains(error.code);
