import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/controller.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'connect_provider_test.dart' show ConnectApi;

final localTrack = WaveTrack({
  'id': 'offline-test',
  'title': 'Original cached music',
  'duration': 90,
  'source': 'local',
  'playback': {'kind': 'audio', 'offline': true},
});

class LanCache extends MusicCache {
  LanCache(super.api);
  @override
  Future<File?> fileFor(String id) async =>
      entries.containsKey(id) ? File('isolated-cache') : null;
}

class LanAudio extends WaveAudioHandler {
  bool sounds = false, ready = true;
  double seconds = 0, level = .8;
  final commands = <String>[];
  LanAudio(super.api, super.cache);
  @override
  bool get sourceReady => ready;
  @override
  bool get outputPlaying => sounds;
  @override
  Duration get outputPosition =>
      Duration(milliseconds: (seconds * 1000).round());
  @override
  double get outputVolume => level;
  @override
  Future<void> suspendLocalOutput() async {
    sounds = false;
  }

  @override
  Future<void> playTrack(
    WaveTrack track, {
    List<WaveTrack>? list,
    double position = 0,
    bool playing = true,
  }) async {
    clearRemote();
    current = track;
    tracks = list ?? [track];
    seconds = position;
    sounds = playing;
  }

  @override
  Future<void> localCommand(String command, [Json data = const {}]) async {
    commands.add(command);
    if (command == 'play') sounds = true;
    if (command == 'pause' || command == 'stop') sounds = false;
    if (command == 'seek') seconds = number(data['position']);
    if (command == 'volume') level = number(data['volume']);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final storage = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args = object(call.arguments), key = args['key'] as String;
            if (call.method == 'read') return storage[key];
            if (call.method == 'write') storage[key] = args['value'] as String;
            return null;
          },
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
  });
  test(
    'LAN controllers mirror, control and transfer one output without cloud requests; missing cache retains sender',
    () async {
      WaveController make(String id) {
        final api = ConnectApi(),
            cache = LanCache(api),
            audio = LanAudio(api, cache);
        return WaveController(api, cache, audio)
          ..deviceId = id
          ..user = WaveUser({'id': 'same-owner', 'plan': 'free'});
      }

      final host = make('host-device'), phone = make('phone-device');
      final hostAudio = host.audio as LanAudio,
          phoneAudio = phone.audio as LanAudio;
      host.cache.entries[localTrack.id] = {'track': localTrack.json};
      try {
        await host.createLanInvite();
        final uri = Uri.parse(host.lanInvite!),
            data = object(
              jsonDecode(
                utf8.decode(base64Url.decode(uri.queryParameters['data']!)),
              ),
            );
        data['endpoint'] = Uri.parse(
          data['endpoint'] as String,
        ).replace(host: '127.0.0.1').toString();
        await phone.connectLan(
          uri
              .replace(
                queryParameters: {
                  'data': base64Url.encode(utf8.encode(jsonEncode(data))),
                },
              )
              .toString(),
        );
        await host.play(localTrack, list: [localTrack]);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(hostAudio.sounds, true);
        expect(phone.controllingRemote, true);
        expect(phone.audio.viewCurrent?.id, localTrack.id);
        await phone.transport('seek', {'position': 12});
        expect(hostAudio.seconds, 12);
        await phone.transport('volume', {'volume': .3});
        expect(hostAudio.level, .3);
        await expectLater(host.transfer(phone.deviceId), throwsA(anything));
        expect(hostAudio.sounds, true);
        expect(host.activeDeviceId, host.deviceId);
        phone.cache.entries[localTrack.id] = {'track': localTrack.json};
        await host.transfer(phone.deviceId);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(hostAudio.sounds, false);
        expect(phoneAudio.sounds, true);
        expect(host.activeDeviceId, phone.deviceId);
        expect(phone.outputHere, true);
        await host.transport('pause');
        expect(phoneAudio.sounds, false);
        await phone.transport('play');
        expect(phoneAudio.sounds, true);
        await phone.receiveAccountState({
          'activeDeviceId': 'cloud-other',
          'state': {'playing': true},
        });
        expect(phone.activeDeviceId, phone.deviceId);
        expect(
          await phone.audio.onEnded!(localTrack, AudioServiceRepeatMode.one),
          true,
        );
        expect(phoneAudio.seconds, 0);
        expect(phoneAudio.sounds, true);
        await phone.listenHere();
        await host.listenHere();
        expect(hostAudio.sounds, true);
        expect(phoneAudio.sounds, false);
        expect((host.api as ConnectApi).requests, isEmpty);
        expect((phone.api as ConnectApi).requests, isEmpty);
        await host.removeLanPeer(phone.deviceId);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(phone.lanActive, false);
      } finally {
        await phone.setLanEnabled(false);
        await host.setLanEnabled(false);
        phone.dispose();
        host.dispose();
        await phoneAudio.release();
        await hostAudio.release();
        phone.api.dio.close(force: true);
        host.api.dio.close(force: true);
      }
    },
  );
}
