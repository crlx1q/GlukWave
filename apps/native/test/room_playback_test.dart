import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/controller.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_layout_test.dart' show LayoutApi;

class RoomController extends WaveController {
  final commands = <Json>[];
  RoomController(super.api, super.cache, super.audio);
  @override
  Future<Json> emitAck(String event, Json data) async {
    commands.add({'event': event, ...data});
    return event == 'room:join' ? {'room': room} : {'ok': true};
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
    'Actual room completion sends validated repeat and current track/revision identity',
    () async {
      SharedPreferences.setMockInitialValues({});
      final api = LayoutApi(), cache = MusicCache(api);
      final audio = WaveAudioHandler(api, cache);
      // Use the real handler; the controller owns room policy and emits the
      // actual callback payload. No audio source or network fixture is needed.
      final c = RoomController(api, cache, audio);
      c.preferences = await SharedPreferences.getInstance();
      final track = WaveTrack({
        'id': 'finite-track',
        'duration': 60,
        'playback': {'kind': 'audio'},
      });
      c.user = WaveUser({'id': 'owner', 'username': 'listener'});
      c.audio.current = track;
      await c.enterRoom({
        'id': 'room',
        'ownerId': 'owner',
        'members': [],
        'state': {
          'trackId': track.id,
          'position': 0,
          'playing': false,
          'revision': 9,
        },
      });
      c.commands.clear();
      expect(
        await c.audio.onEnded!(track, AudioServiceRepeatMode.none),
        isTrue,
      );
      expect(c.commands.single, {
        'event': 'room:command',
        'roomId': 'room',
        'command': 'ended',
        'trackId': track.id,
        'expectedRevision': 9,
        'repeat': 'off',
      });
      c.commands.clear();
      c.room!['ownerId'] = 'other-owner';
      c.room!['members'] = [
        {'userId': 'owner', 'canControl': false},
      ];
      expect(await c.audio.onEnded!(track, AudioServiceRepeatMode.all), isTrue);
      expect(
        c.commands,
        isEmpty,
        reason: 'A listener waits for authoritative room playback.',
      );
      c.dispose();
      await c.audio.release();
      c.api.dio.close(force: true);
    },
  );
}
