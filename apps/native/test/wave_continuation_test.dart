import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/controller.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/audio.dart';
import 'audio_lifecycle_test.dart' as f;

WaveTrack own(String id) => WaveTrack({
  'id': id,
  'title': 'Own $id',
  'artist': 'Original tester',
  'duration': 180,
  'source': 'local',
  'playback': {'kind': 'audio', 'url': '/own.wav'},
});

class WaveApiFixture extends WaveApi {
  WaveApiFixture() : super('http://127.0.0.1:4000');
  final queries = <Json>[], resolutions = <String>[];
  List<WaveTrack> ranked = [];
  Completer<Json>? pending;
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    if (path == '/api/recommendations') {
      queries.add({...?query});
      return pending?.future ?? {'tracks': ranked.map((t) => t.json).toList()};
    }
    if (path.endsWith('/playback')) {
      resolutions.add(path);
      return {
        'playback': {'kind': 'audio', 'url': '/own.wav'},
      };
    }
    return {};
  }
}

class Output extends f.NativeOutput {
  Duration cursor = Duration.zero;
  @override
  Duration get position => cursor;
  @override
  Future<void> seek(Duration? position, {int? index}) async {
    cursor = position ?? Duration.zero;
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
  Future<(WaveController, WaveApiFixture, Output)> setup() async {
    SharedPreferences.setMockInitialValues({});
    final api = WaveApiFixture()..token = 'isolated',
        cache = f.PlaybackCache(api),
        output = Output();
    final audio = WaveAudioHandler(api, cache, output: output)
      ..autoCache = false;
    final controller = WaveController(api, cache, audio)
      ..user = WaveUser({'id': 'listener'})
      ..online = true
      ..loading = false;
    controller.preferences = await SharedPreferences.getInstance();
    await controller.restoreCustomizationScope();
    return (controller, api, output);
  }

  Future<void> close(WaveController c) async {
    c.dispose();
    await c.audio.release();
    c.api.dio.close(force: true);
  }

  test(
    'native ranked wave starts first, prepares next once and extends natural end with mode/mood',
    () async {
      final (c, api, output) = await setup();
      try {
        api.ranked = [own('first'), own('second')];
        await c.startWave(mode: 'favorites', mood: 'calm');
        expect(c.audio.current?.id, 'first');
        expect(c.waveMode, 'favorites');
        expect(c.waveMood, 'calm');
        await Future<void>.delayed(Duration.zero);
        await c.transport('next');
        expect(c.audio.current?.id, 'second');
        expect(
          api.resolutions.where((p) => p.contains('/second/')).length,
          1,
          reason: 'Metadata prepared for next is reused by actual playback.',
        );
        api.ranked = [own('third')];
        expect(
          await c.audio.onEnded!(c.audio.current!, AudioServiceRepeatMode.none),
          true,
        );
        expect(c.audio.current?.id, 'third');
        expect(api.queries.last['seedTrackId'], 'second');
        expect(api.queries.last['mode'], 'favorites');
        expect(api.queries.last['mood'], 'calm');
        final loads = output.loaded.length;
        await c.audio.playTrack(c.audio.current!, list: c.audio.tracks);
        expect(
          output.loaded.length,
          loads,
          reason: 'Loaded repeat reuses native decoder.',
        );
      } finally {
        await close(c);
      }
    },
  );
  test(
    'late native wave result cannot pause or replace a newer selection',
    () async {
      final (c, api, output) = await setup();
      try {
        await c.play(own('old'), list: [own('old')]);
        api.pending = Completer<Json>();
        final next = c.transport('next');
        await Future<void>.delayed(Duration.zero);
        expect(api.queries.length, 1);
        await c.play(own('selected'), list: [own('selected')]);
        api.pending!.complete({
          'tracks': [own('stale').json],
        });
        await next;
        expect(c.audio.current?.id, 'selected');
        expect(output.active, true);
        expect(c.audio.tracks.map((t) => t.id), ['selected']);
      } finally {
        await close(c);
      }
    },
  );
  test(
    'empty unfamiliar tail stops honestly instead of recycling a known track',
    () async {
      final (c, api, output) = await setup();
      try {
        c.waveMode = 'discovery';
        await c.play(own('last'), list: [own('last')], preserveWave: true);
        await c.transport('next');
        expect(output.active, false);
        expect(c.audio.current?.id, 'last');
        expect(api.queries.length, 1);
      } finally {
        await close(c);
      }
    },
  );
}
