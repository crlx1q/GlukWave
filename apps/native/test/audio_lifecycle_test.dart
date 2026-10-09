import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/services/provider_player.dart';

class PlaybackApi extends WaveApi {
  final requests = <String>[];
  Json descriptor = {
    'kind': 'audio',
    'url': '/api/external-audio/source',
    'offline': true,
    'downloadUrl': '/api/external-audio/source/download',
  };
  Completer<Json>? pending;
  PlaybackApi() : super('http://127.0.0.1:4000');
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    requests.add(path);
    return pending?.future ?? {'playback': descriptor};
  }
}

class PlaybackCache extends MusicCache {
  File? cached;
  PlaybackCache(super.api);
  @override
  Future<File?> fileFor(String id) async => cached;
}

// Exercise the real WaveAudioHandler through the native player boundary.
// No network audio, owner account, provider iframe or physical sound is used.
class NativeOutput extends AudioPlayer {
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final processing = StreamController<ProcessingState>.broadcast(sync: true);
  final loaded = <String>[];
  Map<String, String>? sentHeaders;
  bool active = false, ready = false, disposed = false;
  NativeOutput()
    : super(handleInterruptions: false, handleAudioSessionActivation: false);
  @override
  bool get playing => active;
  @override
  ProcessingState get processingState =>
      ready ? ProcessingState.ready : ProcessingState.idle;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<ProcessingState> get processingStateStream => processing.stream;
  @override
  Stream<PlaybackEvent> get playbackEventStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    loaded.add(url);
    sentHeaders = headers;
    ready = true;
    return const Duration(minutes: 3);
  }

  @override
  Future<Duration?> setFilePath(
    String path, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    loaded.add(path);
    ready = true;
    return const Duration(minutes: 3);
  }

  @override
  Future<void> play() async {
    active = true;
    states.add(PlayerState(true, processingState));
  }

  @override
  Future<void> pause() async {
    active = false;
    states.add(PlayerState(false, processingState));
  }

  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> dispose() async {
    disposed = true;
    await states.close();
    await processing.close();
    await super.dispose();
  }
}

WaveTrack external(String id, {String kind = 'soundcloud'}) => WaveTrack({
  'id': id,
  'title': 'Real source',
  'artist': 'Test artist',
  'source': 'soundcloud',
  'sourceUrl': 'https://soundcloud.com/test/real-source',
  'duration': 180,
  'playback': {'kind': kind},
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
  });
  Future<void> close(WaveAudioHandler audio) async {
    await audio.release();
    audio.api.dio.close(force: true);
  }

  test(
    'Permitted external source resolves before provider choice and retains its descriptor in current/queue',
    () async {
      final api = PlaybackApi()..token = 'isolated-token';
      final output = NativeOutput();
      final audio = WaveAudioHandler(api, PlaybackCache(api), output: output)
        ..autoCache = false;
      await audio.playTrack(
        external('source'),
        list: [external('source'), external('next')],
      );
      expect(api.requests, ['/api/tracks/source/playback']);
      expect(output.loaded, [
        'http://127.0.0.1:4000/api/external-audio/source',
      ]);
      expect(output.sentHeaders?['Authorization'], 'Bearer isolated-token');
      expect(audio.current?.embedded, isFalse);
      expect(audio.current?.offline, isTrue);
      expect(
        audio.tracks.first.playback['downloadUrl'],
        '/api/external-audio/source/download',
      );
      expect(audio.provider.track, isNull);
      expect(audio.outputPlaying, isTrue);
      expect(
        output.states.hasListener,
        isFalse,
        reason: 'Readiness subscription is released after ACK.',
      );
      await close(audio);
    },
  );

  test(
    'Metadata alone does not grant native playback or forward credentials to a CDN',
    () async {
      final api = PlaybackApi()..token = 'isolated-token';
      final output = NativeOutput();
      final audio = WaveAudioHandler(api, PlaybackCache(api), output: output)
        ..autoCache = false;
      api.descriptor = {'kind': 'unavailable'};
      await expectLater(
        audio.playTrack(external('metadata', kind: 'unavailable')),
        throwsA(isA<WaveException>()),
      );
      expect(output.loaded, isEmpty);
      api.descriptor = {
        'kind': 'audio',
        'url': 'https://media.example.test/approved.mp3',
        'offline': false,
      };
      await audio.playTrack(external('approved'));
      expect(output.sentHeaders, isNull);
      expect(audio.current?.offline, isFalse);
      await close(audio);
    },
  );

  test(
    'Cached permitted audio plays without resolving an online embedded descriptor',
    () async {
      final api = PlaybackApi();
      final cache = PlaybackCache(api)
        ..cached = File('isolated-cached-song.mp3');
      final output = NativeOutput();
      final audio = WaveAudioHandler(api, cache, output: output)
        ..autoCache = false;
      await audio.playTrack(external('cached'));
      expect(api.requests, isEmpty);
      expect(output.loaded, ['isolated-cached-song.mp3']);
      expect(audio.current?.embedded, isFalse);
      expect(audio.provider.track, isNull);
      await close(audio);
    },
  );

  test(
    'Pause cancels source resolution before late native loading or playback',
    () async {
      final api = PlaybackApi()..pending = Completer<Json>();
      final output = NativeOutput();
      final audio = WaveAudioHandler(api, PlaybackCache(api), output: output)
        ..autoCache = false;
      final loading = audio.playTrack(external('late'));
      await Future<void>.delayed(Duration.zero);
      await audio.localCommand('pause');
      api.pending!.complete({'playback': api.descriptor});
      await loading;
      expect(output.loaded, isEmpty);
      expect(audio.outputPlaying, isFalse);
      expect(audio.provider.track, isNull);
      await close(audio);
    },
  );

  test(
    'Background visual suspension preserves real native completion and starts the next direct source',
    () async {
      final api = PlaybackApi(), output = NativeOutput();
      final audio = WaveAudioHandler(api, PlaybackCache(api), output: output)
        ..autoCache = false;
      final first = external('first'), next = external('next');
      await audio.playTrack(first, list: [first, next]);
      final events = <Duration>[];
      final positions = audio.positionStream.listen(events.add);
      await Future<void>.delayed(const Duration(milliseconds: 280));
      expect(events, isNotEmpty);
      audio.setVisualUpdatesEnabled(false);
      final hiddenCount = events.length;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(events.length, hiddenCount);
      expect(audio.outputPlaying, isTrue);
      output.processing.add(ProcessingState.completed);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(audio.current?.id, 'next');
      expect(audio.outputPlaying, isTrue);
      expect(api.requests.last, '/api/tracks/next/playback');
      expect(events.length, hiddenCount);
      audio.setVisualUpdatesEnabled(true);
      await Future<void>.delayed(Duration.zero);
      expect(events.length, greaterThan(hiddenCount));
      await positions.cancel();
      final count = events.length;
      await Future<void>.delayed(const Duration(milliseconds: 280));
      expect(events.length, count);
      await close(audio);
      expect(output.disposed, isTrue);
    },
  );

  test('Download descriptor is restricted to the authenticated own origin', () {
    final api = PlaybackApi();
    WaveTrack downloadable(String url) => WaveTrack({
      ...external('source').json,
      'playback': {'kind': 'audio', 'downloadUrl': url},
    });
    expect(
      api.downloadUrl(downloadable('/api/external-audio/source/download')),
      'http://127.0.0.1:4000/api/external-audio/source/download',
    );
    for (final url in [
      'https://external.example/api/download',
      'file:///api/download',
      'http://name:secret@127.0.0.1:4000/api/download',
    ]) {
      expect(
        () => api.downloadUrl(downloadable(url)),
        throwsA(isA<WaveException>()),
      );
    }
    api.dio.close(force: true);
  });

  test(
    'Provider cancellation during an outgoing pause cannot install a late document',
    () async {
      final provider = ProviderPlayer();
      final pause = Completer<void>();
      provider.track = external('old');
      provider.ready = true;
      provider.evaluate = (_) => pause.future;
      final loading = provider.load(external('late'), playing: false);
      provider.cancelPendingLoad();
      pause.complete();
      await loading;
      expect(provider.track, isNull);
      expect(provider.loading, isFalse);
      expect(provider.ready, isFalse);
      provider.dispose();
    },
  );

  test(
    'Clearing an outgoing provider never clears a newer ready document',
    () async {
      final provider = ProviderPlayer();
      final pause = Completer<void>();
      provider.track = external('old');
      provider.ready = true;
      provider.evaluate = (_) => pause.future;
      final clearing = provider.clear();
      final loading = provider.load(external('next'), playing: false);
      await Future<void>.delayed(Duration.zero);
      pause.complete();
      await clearing;
      provider.receive(provider.generation, {'event': 'ready'});
      await loading;
      expect(provider.track?.id, 'next');
      expect(provider.ready, isTrue);
      expect(provider.loading, isFalse);
      await provider.clear();
      provider.dispose();
    },
  );
}
