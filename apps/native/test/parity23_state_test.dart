import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/controller.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/background_connect.dart';
import 'audio_lifecycle_test.dart' as f;

class DirectoryApi extends f.PlaybackApi {
  final directory = <Completer<Json>>[];
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) {
    if (path != '/api/devices') {
      return super.call(path, method: method, data: data, query: query);
    }
    final pending = Completer<Json>();
    directory.add(pending);
    return pending.future;
  }
}

class VolumeOutput extends f.NativeOutput {
  final volumes = <double>[];
  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);
}

class CloudApi extends f.PlaybackApi {
  final commands = <Json>[];
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    if (path == '/api/devices/command') commands.add(object(data));
    return {
      'connect': {'activeDeviceId': 'cloud-pc', 'state': {}},
    };
  }
}

class LanExitController extends WaveController {
  bool localNetwork = true;
  int exits = 0;
  final closed = Completer<void>();
  LanExitController(super.api, super.cache, super.audio);
  @override
  bool get lanEnabled => localNetwork;
  @override
  Future<void> setLanEnabled(bool value) async {
    exits++;
    await closed.future;
    localNetwork = value;
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
    'background Connect bridge sends no credentials and respects a system notification stop',
    () async {
      const channel = MethodChannel('test.connect.background');
      final calls = <Map<dynamic, dynamic>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.arguments as Map);
            return call.arguments['explicit'] == true;
          });
      final bridge = BackgroundConnectBridge(channel: channel, supported: true);
      expect(await bridge.update(true), false);
      expect(await bridge.update(true, explicit: true), true);
      expect(calls, [
        {'enabled': true, 'explicit': false},
        {'enabled': true, 'explicit': true},
      ]);
    },
  );

  test(
    'payload-free invalidations retain names and share a refresh with one trailing update',
    () async {
      final api = DirectoryApi(), cache = f.PlaybackCache(api);
      final audio = WaveAudioHandler(api, cache, output: f.NativeOutput());
      final c = WaveController(api, cache, audio)
        ..devices = [
          {'id': 'pc', 'name': 'Chrome · Windows'},
        ];
      try {
        final pending = c.receiveDeviceChange({});
        final burst = List.generate(12, (_) => c.receiveDeviceChange({}));
        expect(c.devices.single['name'], 'Chrome · Windows');
        expect(api.directory.length, 1);
        api.directory[0].complete({
          'devices': [
            {
              'id': 'pc',
              'name': 'Chrome · Windows',
              'track': {'id': 'first'},
            },
          ],
        });
        await Future<void>.delayed(Duration.zero);
        expect(api.directory.length, 2);
        api.directory[1].complete({
          'devices': [
            {
              'id': 'pc',
              'name': 'Chrome · Windows',
              'track': {'id': 'second'},
            },
          ],
        });
        await Future.wait([pending, ...burst]);
        expect(object(c.devices.single['track'])['id'], 'second');
        expect(api.directory.length, 2);
        final stale = c.refreshDevices();
        await c.receiveDeviceChange({
          'devices': [
            {'id': 'phone', 'name': 'GlukWave · Android'},
          ],
        });
        api.directory[2].complete({'devices': []});
        await stale;
        expect(c.devices.single['name'], 'GlukWave · Android');
      } finally {
        c.dispose();
        await audio.release();
      }
    },
  );

  test(
    'an old account response cannot replace a new account directory',
    () async {
      final api = DirectoryApi(), cache = f.PlaybackCache(api);
      final audio = WaveAudioHandler(api, cache, output: f.NativeOutput());
      final c = WaveController(api, cache, audio);
      try {
        api.token = 'old';
        final old = c.refreshDevices();
        api.token = 'new';
        final next = c.refreshDevices();
        api.directory[1].complete({
          'devices': [
            {'id': 'new', 'name': 'New phone'},
          ],
        });
        await next;
        api.directory[0].complete({
          'devices': [
            {'id': 'old'},
          ],
        });
        await old;
        expect(c.devices.single['id'], 'new');
      } finally {
        c.dispose();
        await audio.release();
      }
    },
  );

  test(
    'independent snapshots preserve local media, repeat, shuffle and wave preferences',
    () async {
      final api = DirectoryApi(), cache = f.PlaybackCache(api);
      final audio = WaveAudioHandler(api, cache, output: f.NativeOutput())
        ..current = f.external('local')
        ..repeat = AudioServiceRepeatMode.one
        ..shuffle = true;
      final c = WaveController(api, cache, audio)
        ..deviceId = 'local'
        ..waveMode = 'favorites'
        ..waveMood = 'calm'
        ..waveActive = true;
      try {
        await c.receiveAccountState({
          'independent': true,
          'activeDeviceId': 'remote',
          'activeDeviceName': 'Chrome · Windows',
          'state': {
            'trackId': 'remote-song',
            'playing': true,
            'repeat': 'off',
            'shuffle': false,
            'waveMode': 'popular',
            'waveMood': 'energy',
            'waveActive': false,
            'revision': 5,
          },
        });
        expect(audio.viewCurrent?.id, 'local');
        expect(audio.remote, false);
        expect(audio.repeat, AudioServiceRepeatMode.one);
        expect(audio.shuffle, true);
        expect(
          [c.waveMode, c.waveMood, c.waveActive],
          ['favorites', 'calm', true],
        );
        expect(c.activeDeviceName, 'Chrome · Windows');
      } finally {
        c.dispose();
        await audio.release();
      }
    },
  );

  test(
    'cloud transfer exits LAN before issuing one scoped account command',
    () async {
      final api = CloudApi(), cache = f.PlaybackCache(api);
      final audio = WaveAudioHandler(api, cache, output: f.NativeOutput());
      final c = LanExitController(api, cache, audio);
      try {
        final first = c.transferCloud('cloud-pc');
        final second = c.transferCloud('cloud-pc');
        expect(c.exits, 1);
        expect(api.commands, isEmpty);
        c.closed.complete();
        await Future.wait([first, second]);
        expect(c.lanEnabled, false);
        expect(api.commands.length, 1);
        expect(api.commands.single['deviceId'], 'cloud-pc');
        expect(api.commands.single['command'], 'transfer');
      } finally {
        c.dispose();
        await audio.release();
      }
    },
  );

  test(
    'phone local output stays full volume, remote volume remains independent and notification likes are scoped to their track',
    () async {
      final api = f.PlaybackApi(),
          cache = f.PlaybackCache(api),
          output = VolumeOutput();
      final audio =
          WaveAudioHandler(api, cache, output: output, hardwareVolume: true)
            ..autoCache = false
            ..prepareNext = false;
      var liked = 0;
      audio.onNotificationLike = () async {
        liked++;
      };
      try {
        await audio.localCommand('volume', {'volume': .12});
        await audio.previewControl('volume', .3, localVolume: true);
        expect(audio.volume, 1);
        expect(output.volumes, everyElement(1));
        await audio.clearControlPreview('volume');
        await audio.playTrack(f.external('first'));
        final controls = audio.playbackState.value.controls;
        expect(
          controls.map((c) => c.action),
          isNot(contains(MediaAction.stop)),
        );
        expect(controls.last.customAction?.name, 'glukwave.like');
        await audio.customAction('glukwave.like', {'trackId': 'first'});
        expect(liked, 1);
        await audio.playTrack(f.external('second'));
        await audio.customAction('glukwave.like', {'trackId': 'first'});
        expect(liked, 1);
        audio.showRemote(
          const PlaybackSnapshot(volume: .24),
          f.external('remote'),
          [],
        );
        expect(audio.volume, .24);
        expect(audio.outputVolume, 1);
      } finally {
        await audio.release();
      }
    },
  );
}
