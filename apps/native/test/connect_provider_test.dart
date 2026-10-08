import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/controller.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/services/provider_player.dart';
import 'app_layout_test.dart' show LayoutApi;

final connectedTrack = WaveTrack({
  'id': 'connected-track',
  'title': 'Connected song',
  'artist': 'Test artist',
  'duration': 180,
  'source': 'local',
  'playback': {'kind': 'audio'},
});

class ConnectApi extends LayoutApi {
  final requests = <Json>[];
  Completer<Json>? connectPending;
  bool missingConnect = false;
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    requests.add({'path': path, 'method': method, 'data': data});
    if (path == '/api/connect') {
      if (missingConnect) throw const WaveException('Missing', 'network', 404);
      if (connectPending != null) return connectPending!.future;
    }
    return {};
  }
}

class ConnectAudio extends WaveAudioHandler {
  final local = <String>[];
  final starts = <WaveTrack>[];
  ConnectAudio(super.api, super.cache);
  @override
  Future<void> localCommand(String command, [Json data = const {}]) async {
    local.add(command);
  }

  @override
  Future<void> playTrack(
    WaveTrack track, {
    List<WaveTrack>? list,
    double position = 0,
    bool playing = true,
  }) async {
    starts.add(track);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
  });
  test(
    'Account Connect mirrors remote playback and routes controls without local playback',
    () async {
      final api = ConnectApi(), cache = MusicCache(api);
      final output = ConnectAudio(api, cache),
          c = WaveController(api, cache, output);
      c.deviceId = 'phone-install';
      c.devices = [
        {'deviceId': 'pc-install', 'name': 'Living room PC'},
      ];
      c.tracks = [connectedTrack];
      await c.receiveAccountState({
        'independent': false,
        'activeDeviceId': 'pc-install',
        'activeSurfaceId': 'pc-runtime',
        'track': connectedTrack.json,
        'queueTracks': [connectedTrack.json],
        'serverTime': 20000,
        'state': {
          'trackId': connectedTrack.id,
          'playing': true,
          'position': 10,
          'volume': .4,
          'updatedAt': 18000,
          'queue': [connectedTrack.id],
        },
      });
      expect(c.controllingRemote, isTrue);
      expect(output.viewCurrent?.id, connectedTrack.id);
      expect(output.current, isNull);
      expect(output.playing, isTrue);
      expect(output.outputPlaying, isFalse);
      expect(output.position.inMilliseconds, closeTo(12000, 300));
      expect(output.viewTracks.single.id, connectedTrack.id);
      await c.transport('pause');
      await c.transport('volume', {'volume': .2});
      await c.play(connectedTrack, list: [connectedTrack]);
      expect(output.local, isEmpty);
      expect(output.starts, isEmpty);
      expect(api.requests.map((v) => object(v['data'])['command']), [
        'pause',
        'volume',
        'track',
      ]);
      for (final request in api.requests) {
        expect(object(request['data'])['deviceId'], 'pc-install');
        expect(object(request['data'])['surfaceId'], 'pc-runtime');
      }
      expect(object(api.requests.last['data']).keys.toSet(), {
        'deviceId',
        'command',
        'surfaceId',
        'trackId',
        'queue',
      });
      await c.transfer(c.deviceId, targetSurfaceId: c.surfaceId);
      expect(object(api.requests.last['data']), {
        'deviceId': c.deviceId,
        'command': 'transfer',
        'fromDeviceId': 'pc-install',
        'surfaceId': c.surfaceId,
      });
      await c.receiveAccountState({'independent': true});
      expect(output.remote, isFalse);
      expect(output.playing, isFalse);
      expect(output.outputPlaying, isFalse);
      expect(c.controllingRemote, isFalse);
      c.dispose();
      await output.release();
      api.dio.close(force: true);
    },
  );
  test(
    'Same installation and another runtime remains a remote output',
    () async {
      final api = ConnectApi(),
          cache = MusicCache(api),
          audio = ConnectAudio(api, cache);
      final c = WaveController(api, cache, audio)..deviceId = 'pc-install';
      await c.receiveAccountState({
        'independent': false,
        'activeDeviceId': c.deviceId,
        'activeSurfaceId': 'other-runtime',
        'track': connectedTrack.json,
        'state': {'trackId': connectedTrack.id},
        'queueTracks': [connectedTrack.json],
      });
      expect(c.controllingRemote, isTrue);
      await c.receiveAccountState({
        'independent': false,
        'activeDeviceId': c.deviceId,
        'activeSurfaceId': c.surfaceId,
        'state': {},
      });
      expect(c.controllingRemote, isFalse);
      expect(audio.remote, isFalse);
      c.dispose();
      await audio.release();
      api.dio.close(force: true);
    },
  );
  test(
    'Late Connect responses cannot replace new revisions and legacy 404 is immediate',
    () async {
      final api = ConnectApi(), cache = MusicCache(api);
      final audio = ConnectAudio(api, cache);
      final c = WaveController(api, cache, audio)..deviceId = 'my-install';
      api.token = 'fixture-token';
      api.connectPending = Completer<Json>();
      final pending = c.refreshConnect();
      await c.receiveAccountState({
        'activeDeviceId': 'new-device',
        'activeSurfaceId': 'new-runtime',
        'track': connectedTrack.json,
        'state': {'trackId': connectedTrack.id, 'revision': 12, 'position': 12},
      });
      api.connectPending!.complete({
        'connect': {
          'activeDeviceId': 'old-device',
          'state': {'revision': 11},
        },
      });
      await pending;
      expect(c.activeDeviceId, 'new-device');
      await c.receiveAccountState({
        'activeDeviceId': 'old-device',
        'state': {'revision': 11},
      });
      expect(c.activeDeviceId, 'new-device');
      await c.receiveAccountState({
        'independent': true,
        'state': {'revision': 12},
      });
      expect(audio.outputPlaying, isFalse);
      expect(audio.playing, isFalse);
      api.connectPending = null;
      api.missingConnect = true;
      await c.refreshConnect();
      c.dispose();
      await audio.release();
      api.dio.close(force: true);
    },
  );
  test(
    'Own-output Connect keeps saved volume while remote volume is only mirrored',
    () async {
      final api = ConnectApi(), cache = MusicCache(api);
      final audio = WaveAudioHandler(api, cache);
      final c = WaveController(api, cache, audio)..deviceId = 'my-install';
      await audio.localCommand('volume', {'volume': .23});
      await c.receiveAccountState({
        'independent': false,
        'activeDeviceId': c.deviceId,
        'activeSurfaceId': c.surfaceId,
        'state': {'volume': .9},
      });
      expect(audio.volume, .23);
      await c.receiveAccountState({
        'independent': false,
        'activeDeviceId': 'remote-install',
        'activeSurfaceId': 'remote-surface',
        'track': connectedTrack.json,
        'queueTracks': [connectedTrack.json],
        'state': {'trackId': connectedTrack.id, 'volume': .7},
      });
      expect(audio.volume, .7);
      expect(audio.outputVolume, .23);
      await c.receiveAccountState({
        'independent': false,
        'activeDeviceId': c.deviceId,
        'activeSurfaceId': c.surfaceId,
        'state': {'volume': .9},
      });
      expect(audio.volume, .23);
      c.dispose();
      await audio.release();
      api.dio.close(force: true);
    },
  );
  test(
    'Official provider document validates identities and carries no account token',
    () {
      final sc = WaveTrack({
        'id': 'sc',
        'source': 'soundcloud',
        'sourceUrl': 'https://soundcloud.com/odesza/say-my-name-feat-zyra',
        'playback': {'kind': 'soundcloud'},
      });
      final html = providerDocument(sc, 5, 'https://wave.gluk.tech');
      expect(html, contains('SC.Widget.Events.FINISH'));
      expect(html, contains('PLAY_PROGRESS'));
      expect(html, contains("callHandler('waveProvider',5"));
      expect(html, isNot(contains('Authorization')));
      expect(sc.offline, isFalse);
      expect(sc.playable, isTrue);
      expect(
        () => providerDocument(
          WaveTrack({
            'id': 'x',
            'source': 'soundcloud',
            'sourceUrl': 'https://evil.example',
            'playback': {'kind': 'soundcloud'},
          }),
          1,
          'https://wave.gluk.tech',
        ),
        throwsException,
      );
      final youtube = WaveTrack({
        'id': 'youtube-M7lc1UVf-VE',
        'source': 'youtube',
        'sourceId': 'M7lc1UVf-VE',
        'playback': {'kind': 'youtube'},
      });
      expect(
        providerDocument(youtube, 2, 'https://wave.gluk.tech'),
        contains('onStateChange'),
      );
    },
  );
  test(
    'Provider transport derives playing/time/ended from official callbacks, rejecting old generations',
    () async {
      final bridge = ProviderPlayer();
      final track = WaveTrack({
        'id': 'soundcloud-1',
        'duration': 30,
        'source': 'soundcloud',
        'sourceUrl': 'https://soundcloud.com/odesza/say-my-name-feat-zyra',
        'playback': {'kind': 'soundcloud'},
      });
      final commands = <String>[];
      bridge.evaluate = (script) async {
        commands.add(script);
        if (script.contains('"play"')) {
          bridge.receive(bridge.generation, {
            'event': 'state',
            'playing': true,
          });
        }
      };
      bridge.addListener(() {
        if (bridge.loading && !bridge.ready) {
          scheduleMicrotask(
            () => bridge.receive(bridge.generation, {'event': 'ready'}),
          );
        }
      });
      await bridge.load(track, position: 3, volume: .4);
      expect(bridge.playing, isTrue);
      expect(
        commands
            .map(
              (s) =>
                  s.contains('"volume"') ||
                  s.contains('"seek"') ||
                  s.contains('"play"'),
            )
            .every((v) => v),
        isTrue,
      );
      bridge.receive(bridge.generation - 1, {
        'event': 'position',
        'position': 99,
      });
      expect(bridge.position, 3);
      bridge.receive(bridge.generation, {
        'event': 'position',
        'position': 7,
        'duration': 30,
      });
      expect(bridge.position, 7);
      await bridge.command('pause');
      expect(
        bridge.playing,
        isTrue,
        reason: 'A request alone cannot pretend playback changed.',
      );
      bridge.receive(bridge.generation, {'event': 'state', 'playing': false});
      expect(bridge.playing, isFalse);
      var ended = 0;
      bridge.onEnded = () => ended++;
      bridge.receive(bridge.generation, {'event': 'ended'});
      expect(ended, 1);
      await bridge.clear();
      bridge.dispose();
    },
  );
}
