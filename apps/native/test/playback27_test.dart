import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:glukwave/services/windows_mpv_player.dart';
import 'parity23_windows_test.dart' as fixture;

class DelayedOpen extends fixture.FakeMpv {
  final entered = Completer<void>(), finish = Completer<void>();
  int plays = 0, pauses = 0;
  @override
  Future<void> open(dynamic media, {bool play = true}) async {
    await super.open(media, play: play);
    entered.complete();
    await finish.future;
  }

  @override
  Future<void> play() async {
    plays++;
    await super.play();
  }

  @override
  Future<void> pause() async {
    pauses++;
    await super.pause();
  }
}

LoadRequest source() => LoadRequest(
  audioSourceMessage: ProgressiveAudioSourceMessage(
    id: 'handoff',
    uri: 'https://example.test/own.mp3',
  ),
  initialPosition: const Duration(seconds: 42),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'play during delayed native open is applied after actual open and initial seek',
    () async {
      final backend = DelayedOpen(),
          player = WaveMpvPlayer('handoff-play', output: backend);
      var completed = false;
      final load = player.load(source()).then((value) {
        completed = true;
        return value;
      });
      await backend.entered.future;
      await player.play(PlayRequest());
      await Future<void>.delayed(Duration.zero);
      expect(
        completed,
        isFalse,
        reason: 'duration event alone cannot finish an open still in flight',
      );
      expect(backend.state.playing, isFalse);
      backend.finish.complete();
      await load;
      expect(backend.state.playing, isTrue);
      expect(backend.seeks, [const Duration(seconds: 42)]);
      await player.release();
    },
  );
  test(
    'pause during delayed native open wins over the captured playing state',
    () async {
      final backend = DelayedOpen(),
          player = WaveMpvPlayer('handoff-pause', output: backend);
      await player.play(PlayRequest());
      final load = player.load(source());
      await backend.entered.future;
      expect(backend.state.playing, isTrue);
      await player.pause(PauseRequest());
      backend.finish.complete();
      await load;
      expect(backend.state.playing, isFalse);
      expect(backend.plays, 0);
      await player.release();
    },
  );
  test('released pending open cannot apply a late play intent', () async {
    final backend = DelayedOpen(),
        player = WaveMpvPlayer('handoff-release', output: backend);
    final load = player.load(source());
    final rejected = expectLater(load, throwsA(isA<StateError>()));
    await backend.entered.future;
    await player.play(PlayRequest());
    await player.release();
    backend.finish.complete();
    await rejected;
    expect(backend.plays, 0);
  });
}
