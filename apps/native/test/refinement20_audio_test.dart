import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/core/playback_recovery.dart';
import 'package:glukwave/services/audio.dart';
import 'audio_lifecycle_test.dart' as fixture;

class TransientOutput extends fixture.NativeOutput {
  int failures = 1;
  bool hangs = false;
  @override
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    if (hangs) return Completer<Duration?>().future;
    if (failures-- > 0) throw PlayerException(0, 'Expired capability', null);
    return super.setUrl(
      url,
      headers: headers,
      initialPosition: initialPosition,
      preload: preload,
      tag: tag,
    );
  }
}

class UnavailableApi extends fixture.PlaybackApi {
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    if (path.contains('/bad/')) {
      throw const WaveException('Unavailable', 'AUDIO_UNAVAILABLE');
    }
    return super.call(path, method: method, data: data, query: query);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        ),
  );
  test(
    'native source renews its descriptor once and preserves the requested position',
    () async {
      final api = fixture.PlaybackApi()..token = 'same-device-session',
          output = TransientOutput();
      final audio = WaveAudioHandler(
        api,
        fixture.PlaybackCache(api),
        output: output,
      );
      try {
        await audio.playTrack(
          fixture.external('original'),
          position: 17,
          playing: false,
        );
        expect(api.requests.length, 2);
        expect(output.loadedPosition, const Duration(seconds: 17));
        expect(
          output.sentHeaders?['Authorization'],
          'Bearer same-device-session',
        );
        expect(audio.trackLoading, false);
      } finally {
        await audio.release();
      }
    },
  );
  test(
    'a hanging native decoder has a finite deadline and only one source renewal',
    () async {
      final api = fixture.PlaybackApi(),
          output = TransientOutput()..hangs = true;
      final audio = WaveAudioHandler(
        api,
        fixture.PlaybackCache(api),
        output: output,
        sourceLoadTimeout: const Duration(milliseconds: 10),
      );
      try {
        await expectLater(
          audio.playTrack(fixture.external('bad'), playing: false),
          throwsA(
            isA<WaveException>().having(
              (error) => error.code,
              'code',
              'AUDIO_STREAM_TIMEOUT',
            ),
          ),
        );
        expect(api.requests.length, 2);
        expect(audio.trackLoading, false);
      } finally {
        await audio.release();
      }
    },
  );
  test(
    'source failure recovery preserves user auth/network/autoplay decisions',
    () {
      expect(
        unavailableAudio(
          const WaveException('unavailable', 'AUDIO_UNAVAILABLE'),
        ),
        true,
      );
      for (final code in [
        'AUTH_REQUIRED',
        'AUDIO_EXPIRED',
        'AUTOPLAY_BLOCKED',
        'network',
        'DEVICE_TIMEOUT',
      ]) {
        expect(
          unavailableAudio(WaveException('requires attention', code)),
          false,
        );
      }
    },
  );
  test(
    'a failed descriptor identifies the pending queue item before the decoder loads',
    () async {
      final api = UnavailableApi(), output = TransientOutput()..failures = 0;
      final audio = WaveAudioHandler(
        api,
        fixture.PlaybackCache(api),
        output: output,
      );
      var failures = 0;
      final bad = fixture.external('bad'), good = fixture.external('good');
      audio.onSourceFailure = (track, error) async {
        failures++;
        expect(track.id, 'bad');
        expect(audio.viewCurrent?.id, 'bad');
        expect(audio.tracks.map((track) => track.id), ['bad', 'good']);
        await audio.playTrack(good, list: [good], playing: false);
        return true;
      };
      try {
        await audio.playTrack(bad, list: [bad, good], playing: false);
        expect(audio.current?.id, 'good');
        expect(failures, 1);
      } finally {
        await audio.release();
      }
    },
  );
}
