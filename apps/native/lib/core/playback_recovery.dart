import 'api.dart';
import 'package:just_audio/just_audio.dart';

bool unavailableAudio(Object error) =>
    error is PlayerException ||
    error is WaveException &&
        const {
          'AUDIO_UNAVAILABLE',
          'AUDIO_FORMAT_UNAVAILABLE',
          'DIRECT_AUDIO_UNAVAILABLE',
          'EXTRACTOR_UPSTREAM',
          'EXTRACTOR_URL',
          'AUDIO_MATCH_REJECTED',
        }.contains(error.code);
