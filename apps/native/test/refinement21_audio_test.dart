import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/playback_recovery.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/diagnostics.dart';
import 'audio_lifecycle_test.dart' as f;

class InterruptedOutput extends f.NativeOutput {
  @override
  Duration get position => const Duration(seconds: 27);
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
    'a mid-song stream error reloads once at its position and never skips the queue',
    () async {
      final api = f.PlaybackApi(),
          output = InterruptedOutput(),
          audio = WaveAudioHandler(api, f.PlaybackCache(api), output: output)
            ..autoCache = false
            ..prepareNext = false;
      var skipped = 0;
      audio.onSourceFailure = (track, error) async {
        skipped++;
        return false;
      };
      try {
        await audio.playTrack(
          f.external('original'),
          list: [f.external('original'), f.external('next')],
        );
        await audio.recoverSourceFailure(
          PlayerException(0, 'HTTP 401 stale stream', null),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(api.requests.length, 2);
        expect(output.loadedPosition, const Duration(seconds: 27));
        expect(audio.current?.id, 'original');
        expect(audio.outputPlaying, true);
        expect(skipped, 0);
        await audio.recoverSourceFailure(
          PlayerException(0, 'HTTP connection failed', null),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(api.requests.length, 2);
        expect(audio.tracks.map((t) => t.id), ['original', 'next']);
        expect(skipped, 0);
      } finally {
        await audio.release();
      }
    },
  );
  test(
    'Play retries a failed source without changing the selected track or queue',
    () async {
      final api = f.PlaybackApi(),
          output = f.NativeOutput()
            ..urlError = PlayerException(0, 'HTTP connection failed', null),
          audio = WaveAudioHandler(api, f.PlaybackCache(api), output: output)
            ..autoCache = false
            ..prepareNext = false;
      try {
        await expectLater(
          audio.playTrack(
            f.external('original'),
            list: [f.external('original'), f.external('next')],
          ),
          throwsA(
            isA<WaveException>().having(
              (error) => error.code,
              'code',
              'AUDIO_STREAM_UNAVAILABLE',
            ),
          ),
        );
        expect(output.loaded.length, 2);
        expect(audio.current?.id, 'original');
        output.urlError = null;
        await audio.localCommand('play');
        expect(output.loaded.length, 3);
        expect(audio.sourceReady, true);
        expect(audio.outputPlaying, true);
        expect(audio.tracks.map((track) => track.id), ['original', 'next']);
      } finally {
        await audio.release();
      }
    },
  );
  test(
    'network, decoder and expiring capabilities are not permanent song failures',
    () {
      expect(
        unavailableAudio(PlayerException(4, 'Decoder unavailable', null)),
        false,
      );
      for (final code in [
        'AUDIO_EXPIRED',
        'AUDIO_STREAM_TIMEOUT',
        'AUDIO_STREAM_UNAVAILABLE',
        'EXTRACTOR_UPSTREAM',
        'EXTRACTOR_URL',
        'AUDIO_FORMAT_UNAVAILABLE',
      ]) {
        expect(
          unavailableAudio(WaveException('Retry this stream', code)),
          false,
        );
      }
      expect(
        unavailableAudio(
          const WaveException('Song unavailable', 'AUDIO_UNAVAILABLE'),
        ),
        true,
      );
    },
  );
  test(
    'local diagnostic journal survives reporter restart and excludes credentials',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'glukwave-diagnostics-',
      );
      final first = WaveDiagnostics(() => 'https://fixture.test', () => {}),
          second = WaveDiagnostics(() => 'https://fixture.test', () => {});
      try {
        first.version = 'fixture21';
        await first.enableLocalLog(directory);
        first.record(
          'HTTP401 https://fixture.test/api/stream?grant=private-grant Bearer private-token signature=private-signature',
          code: 'MPV_SOURCE',
        );
        await first.flushLocal();
        first.dispose();
        await second.enableLocalLog(directory);
        second.record('Recovered at27 seconds', code: 'SOURCE_RENEW');
        await second.flushLocal();
        final content = await File(
          '${directory.path}/logs/glukwave.jsonl',
        ).readAsString();
        expect(content, contains('MPV_SOURCE'));
        expect(content, contains('SOURCE_RENEW'));
        for (final secret in [
          'private-grant',
          'private-token',
          'private-signature',
        ]) {
          expect(content, isNot(contains(secret)));
        }
      } finally {
        first.dispose();
        second.dispose();
        await first.flushLocal();
        await second.flushLocal();
        await directory.delete(recursive: true);
      }
    },
  );
}
