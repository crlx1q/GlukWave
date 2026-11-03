import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/controller.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/background_connect.dart';
import 'package:glukwave/services/cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_lifecycle_test.dart' as native;

class PendingPlaybackApi extends native.PlaybackApi {
  final requested = Completer<void>();
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) {
    if (!requested.isCompleted) requested.complete();
    return super.call(path, method: method, data: data, query: query);
  }
}

class IdleApi extends WaveApi {
  int calls = 0;
  Completer<Json>? probeResult;
  IdleApi() : super('http://127.0.0.1:4012');
  @override
  Future<Json> probe() async => probeResult?.future ?? {};
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    calls++;
    return {};
  }
}

class IdleAudio extends WaveAudioHandler {
  bool audible = false, failStop = false;
  int stops = 0;
  IdleAudio(super.api, super.cache);
  @override
  bool get outputPlaying => audible;
  @override
  Future<void> localCommand(String command, [Json data = const {}]) async {
    if (command == 'stop') {
      stops++;
      if (failStop) throw StateError('Controlled decoder cleanup failure');
    }
  }
}

Future<(WaveController, IdleAudio, IdleApi)> fixture() async {
  SharedPreferences.setMockInitialValues({'backgroundConnect': true});
  final api = IdleApi(), cache = MusicCache(api), audio = IdleAudio(api, cache);
  final c = WaveController(api, cache, audio);
  c.preferences = await SharedPreferences.getInstance();
  c.loading = false;
  return (c, audio, api);
}

Future<void> clean((WaveController, IdleAudio, IdleApi) data) async {
  data.$1.dispose();
  await data.$2.release();
  data.$3.dio.close(force: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        ),
  );

  for (final pauseDuringLoad in [false, true]) {
    test(
      pauseDuringLoad
          ? 'Explicit pause during a source lookup releases an idle task and rejects late audio'
          : 'Closing a task during the next track lookup preserves local listening',
      () async {
        final api = PendingPlaybackApi()..pending = Completer<Json>();
        final output = native.NativeOutput()..active = true;
        final audio = WaveAudioHandler(
          api,
          native.PlaybackCache(api),
          output: output,
        )..autoCache = false;
        audio.prepareNext = false;
        var closes = 0;
        audio.onIdleTaskRemoved = () async => closes++;
        final selected = native.external('next-background-track');
        final loading = audio.playTrack(selected, list: [selected]);
        try {
          await api.requested.future;
          expect(audio.outputPlaying, false);
          expect(audio.trackLoading, true);
          expect(audio.backgroundPlaybackActive, true);
          if (pauseDuringLoad) {
            await audio.localCommand('pause');
            expect(audio.backgroundPlaybackActive, false);
          }
          await audio.finishIdleTask();
          expect(closes, pauseDuringLoad ? 1 : 0);
          api.pending!.complete({'playback': api.descriptor});
          await loading;
          if (pauseDuringLoad) {
            expect(output.loaded, isEmpty);
            expect(audio.outputPlaying, false);
          } else {
            expect(audio.current?.id, selected.id);
            expect(audio.outputPlaying, true);
            await audio.localCommand('pause');
            expect(audio.backgroundPlaybackActive, false);
            await audio.finishIdleTask();
            expect(closes, 1);
          }
        } finally {
          if (!api.pending!.isCompleted) {
            api.pending!.complete({'playback': api.descriptor});
          }
          await loading;
          await audio.release();
          api.dio.close(force: true);
        }
      },
    );
  }

  test(
    'Removing an idle task stops media and cannot reconnect afterward',
    () async {
      final f = await fixture(), c = f.$1, audio = f.$2;
      try {
        c.transportPending = true;
        audio.playbackState.add(
          PlaybackState(processingState: AudioProcessingState.ready),
        );
        await audio.onTaskRemoved();
        expect(audio.stops, 1);
        expect(
          audio.playbackState.value.processingState,
          AudioProcessingState.idle,
        );
        expect(c.transportPending, false);
        expect(c.socket, isNull);
        expect(c.connected, false);
        expect(
          c.preferences.getBool('backgroundConnect'),
          true,
          reason: 'Closing one task must not disable the explicit preference',
        );
        await c.revalidateConnection();
        expect(f.$3.calls, 0);
      } finally {
        await clean(f);
      }
    },
  );

  test(
    'A pre-close probe completing late cannot restart a closed idle task',
    () async {
      final f = await fixture(), c = f.$1;
      try {
        f.$3.probeResult = Completer<Json>();
        final oldProbe = c.revalidateConnection();
        await f.$2.onTaskRemoved();
        f.$3.probeResult!.complete({'auth': {}});
        await oldProbe;
        expect(c.socket, isNull);
        expect(f.$3.calls, 0);
      } finally {
        await clean(f);
      }
    },
  );

  test('Task removal keeps audible local music intact', () async {
    final f = await fixture();
    try {
      f.$2.audible = true;
      var closed = false;
      f.$2.onIdleTaskRemoved = () async => closed = true;
      await f.$2.onTaskRemoved();
      expect(f.$2.stops, 0);
      expect(closed, false);
    } finally {
      await clean(f);
    }
  });

  test(
    'A failed decoder stop still removes the idle media notification state',
    () async {
      final f = await fixture();
      try {
        f.$2.failStop = true;
        await f.$2.onTaskRemoved();
        expect(f.$2.stops, 1);
        expect(
          f.$2.playbackState.value.processingState,
          AudioProcessingState.idle,
        );
        expect(f.$2.playbackState.value.playing, false);
      } finally {
        await clean(f);
      }
    },
  );

  test(
    'Android bridge retries a failed playback delivery and handles idle close',
    () async {
      const channel = MethodChannel('clients32/background-lifecycle');
      final calls = <String>[];
      var failures = 1, closes = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'playback' && failures-- > 0) {
          throw PlatformException(code: 'TEMPORARY');
        }
        return null;
      });
      final bridge = BackgroundConnectBridge(channel: channel, supported: true)
        ..onIdleTaskClosed = () async => closes++;
      try {
        bridge.listen();
        await expectLater(
          bridge.playback(true),
          throwsA(isA<PlatformException>()),
        );
        await bridge.playback(true);
        await bridge.playback(true);
        expect(calls.where((value) => value == 'playback'), hasLength(2));
        final done = Completer<void>();
        messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('taskClosed'),
          ),
          (_) => done.complete(),
        );
        await done.future;
        expect(closes, 1);
      } finally {
        bridge.dispose();
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
  );
}
