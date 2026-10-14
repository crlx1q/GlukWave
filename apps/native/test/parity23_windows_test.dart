import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as m;
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:glukwave/services/windows_mpv_player.dart';
import 'package:glukwave/services/windows_playback_state.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/core/wave_math.dart';
import 'audio_lifecycle_test.dart' as f;

class FakeMpv implements m.Player {
  final durations = StreamController<Duration>.broadcast(sync: true),
      positions = StreamController<Duration>.broadcast(sync: true);
  final completions = StreamController<bool>.broadcast(sync: true);
  final errors = StreamController<String>.broadcast(sync: true);
  final seeks = <Duration>[];
  @override
  m.PlayerState state = const m.PlayerState();
  @override
  late final stream = m.PlayerStream(
    const Stream.empty(),
    const Stream.empty(),
    completions.stream,
    positions.stream,
    durations.stream,
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    errors.stream,
  );
  @override
  Future<void> open(dynamic media, {bool play = true}) async {
    state = m.PlayerState(
      playlist: m.Playlist([media as m.Media]),
      duration: const Duration(minutes: 3),
      playing: play,
    );
    durations.add(state.duration);
    completions.add(false);
  }

  @override
  Future<void> seek(Duration value) async {
    seeks.add(value);
    state = state.copyWith(position: value);
    positions.add(value);
  }

  @override
  Future<void> play() async {
    state = state.copyWith(playing: true);
  }

  @override
  Future<void> pause() async {
    state = state.copyWith(playing: false);
  }

  @override
  Future<void> dispose() async {
    await durations.close();
    await positions.close();
    await completions.close();
    await errors.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class AdvancingOutput extends f.NativeOutput {
  final clock = StreamController<Duration>.broadcast(sync: true);
  Duration currentPosition = Duration.zero;
  @override
  Duration get position => currentPosition;
  @override
  Stream<Duration> get positionStream => clock.stream;
  void advance() {
    currentPosition = const Duration(milliseconds: 400);
    clock.add(currentPosition);
  }

  @override
  Future<void> dispose() async {
    await clock.close();
    await super.dispose();
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
    'mpv applies prepared initial position exactly once and ignores paused/reset completion',
    () async {
      final backend = FakeMpv(),
          player = WaveMpvPlayer('isolated23', output: backend);
      final events = <PlaybackEventMessage>[];
      final sub = player.playbackEventMessageStream.listen(events.add);
      try {
        await player.load(
          LoadRequest(
            audioSourceMessage: ProgressiveAudioSourceMessage(
              id: 'one',
              uri: 'https://example.test/own.mp3',
            ),
            initialPosition: const Duration(seconds: 42),
          ),
        );
        expect(backend.seeks, [const Duration(seconds: 42)]);
        backend.durations.add(const Duration(minutes: 3));
        expect(backend.seeks.length, 1);
        backend.completions.add(false);
        backend.completions.add(true);
        await Future<void>.delayed(Duration.zero);
        expect(events.last.updatePosition, const Duration(seconds: 42));
        expect(events.last.processingState, ProcessingStateMessage.ready);
        backend.errors.add('lavf: Failed to create file cache.');
        await Future<void>.delayed(Duration.zero);
        expect(events.last.errorCode, isNull);
        await player.play(PlayRequest());
        await player.seek(SeekRequest(position: const Duration(seconds: 55)));
        backend.completions.add(true);
        await Future<void>.delayed(Duration.zero);
        expect(events.last.processingState, ProcessingStateMessage.ready);
        backend.positions.add(const Duration(minutes: 3));
        backend.completions.add(true);
        await Future<void>.delayed(Duration.zero);
        expect(events.last.processingState, ProcessingStateMessage.completed);
        await player.seek(SeekRequest(position: const Duration(seconds: 12)));
        await Future<void>.delayed(Duration.zero);
        expect(events.last.processingState, ProcessingStateMessage.ready);
        backend.errors.add('Failed to open https://example.test/own.mp3.');
        await Future<void>.delayed(Duration.zero);
        expect(events.last.errorCode, isNotNull);
      } finally {
        await sub.cancel();
        await player.release();
      }
    },
  );
  test(
    'Windows start waits for decoded progress before confirming playback',
    () async {
      final api = f.PlaybackApi(), output = AdvancingOutput();
      final audio =
          WaveAudioHandler(
              api,
              f.PlaybackCache(api),
              output: output,
              verifyNativeProgress: true,
            )
            ..autoCache = false
            ..prepareNext = false;
      try {
        var confirmed = false;
        final start = audio.playTrack(f.external('handoff')).then((_) {
          confirmed = true;
        });
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(confirmed, false);
        output.advance();
        await start;
        expect(confirmed, true);
        expect(audio.current?.id, 'handoff');
      } finally {
        await audio.release();
      }
    },
  );
  test(
    'real silence remains still while ordinary measured music receives a stronger dynamic response',
    () {
      expect(waveResponse(0), 0);
      expect(waveResponse(1), 1);
      expect(waveResponse(.15), greaterThan(.3));
      expect(waveResponse(.5), greaterThan(waveResponse(.15)));
      expect(waveResponse(.7), lessThan(1));
      expect(nonFatalMpvMessage('Failed to open audio'), false);
    },
  );
}
