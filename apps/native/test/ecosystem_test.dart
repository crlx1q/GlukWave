import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/controller.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'connect_provider_test.dart' show ConnectAudio, connectedTrack;
import 'app_layout_test.dart' show LayoutApi;

class EcosystemApi extends LayoutApi {
  final requests = <Json>[];
  Completer<Json>? sessionsPending, commandPending;
  bool sessionsMissing = false, revokeFails = false;
  Json connection = {}, roomFixture = {};
  List<Json> sessionFixtures = [], integrationFixtures = [];
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    requests.add({'path': path, 'method': method, 'data': data});
    if (path == '/api/connect') return {'connect': connection};
    if (path == '/api/devices/command') return commandPending?.future ?? {};
    if (path == '/api/integrations') {
      return {'connections': integrationFixtures};
    }
    if (path == '/api/integrations/spotify/connect') {
      return {
        'url': 'https://accounts.spotify.com/authorize?state=isolated-test',
      };
    }
    if (path == '/api/rooms/room-test') return {'room': roomFixture};
    if (path.startsWith('/api/account/sessions')) {
      if (sessionsMissing) {
        throw const WaveException('Not found', 'not_found', 404);
      }
      if (method == 'DELETE') {
        if (revokeFails) throw const WaveException('offline', 'network');
        if (path == '/api/account/sessions') {
          sessionFixtures.removeWhere((s) => s['current'] != true);
        } else {
          sessionFixtures.removeWhere((s) => path.endsWith('/${s['id']}'));
        }
      }
      return sessionsPending?.future ??
          {'sessions': sessionFixtures, 'currentSessionId': 'current'};
    }
    return {};
  }
}

class EcosystemController extends WaveController {
  final events = <Json>[];
  final opened = <String>[];
  EcosystemController(super.api, super.cache, super.audio);
  @override
  Future<void> openUrl(String value) async {
    opened.add(value);
  }

  @override
  Future<Json> emitAck(String event, Json data) async {
    events.add({'event': event, ...data});
    if (event == 'room:join') {
      final source = api as EcosystemApi;
      return {'room': source.roomFixture, 'connect': source.connection};
    }
    return {'ok': true};
  }
}

class ProtocolAudio extends ConnectAudio {
  Completer<void>? pendingLoad;
  bool failLoad = false;
  bool ready = false, simulatedPlaying = false;
  ProtocolAudio(super.api, super.cache);
  @override
  bool get sourceReady => ready;
  @override
  bool get outputPlaying => simulatedPlaying;
  @override
  Future<void> localCommand(String command, [Json data = const {}]) async {
    await super.localCommand(command, data);
    if (command == 'pause') {
      cancelPendingLoad();
      simulatedPlaying = false;
    }
  }

  @override
  Future<void> playTrack(
    WaveTrack track, {
    List<WaveTrack>? list,
    double position = 0,
    bool playing = true,
  }) async {
    cancelPendingLoad();
    final revision = loadRevision;
    await super.playTrack(
      track,
      list: list,
      position: position,
      playing: playing,
    );
    if (pendingLoad != null) await pendingLoad!.future;
    if (failLoad) {
      throw const WaveException('source unavailable', 'playback_failed');
    }
    if (revision != loadRevision) return;
    ready = true;
    simulatedPlaying = playing;
    current = track;
    tracks = list ?? [track];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
  });
  Future<EcosystemController> setup() async {
    final api = EcosystemApi(), cache = MusicCache(api);
    final c = EcosystemController(api, cache, ProtocolAudio(api, cache));
    c.preferences = await SharedPreferences.getInstance();
    c.deviceId = 'native-install';
    c.api.token = 'test-token';
    c.user = WaveUser({'id': 'listener', 'username': 'test'});
    c.online = true;
    c.tracks = [connectedTrack];
    return c;
  }

  Future<void> close(EcosystemController c) async {
    c.dispose();
    await c.audio.release();
    c.api.dio.close(force: true);
  }

  Json room() => {
    'id': 'room-test',
    'name': 'Our evening',
    'ownerId': 'listener',
    'members': [],
    'state': {
      'trackId': connectedTrack.id,
      'queue': [connectedTrack.id],
      'playing': true,
      'position': 24,
      'revision': 8,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    },
  };
  Json connect(EcosystemController c, {bool own = false}) => {
    'independent': false,
    'activeDeviceId': own ? c.deviceId : 'browser-install',
    'activeSurfaceId': own ? c.surfaceId : 'browser-surface',
    'roomId': 'room-test',
    'room': {'id': 'room-test', 'name': 'Our evening'},
    'track': connectedTrack.json,
    'queueTracks': [connectedTrack.json],
    'state': {
      'trackId': connectedTrack.id,
      'playing': true,
      'queue': [connectedTrack.id],
      'position': 24,
      'revision': own ? 12 : 11,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    },
  };

  test(
    'Joining on a second client mirrors a room and remote volume targets the selected output',
    () async {
      final c = await setup(), api = c.api as EcosystemApi;
      api.roomFixture = room();
      api.connection = connect(c);
      await c.enterRoom(api.roomFixture);
      expect(c.room?['id'], 'room-test');
      expect(c.controllingRemote, isTrue);
      expect(c.outputHere, isFalse);
      expect(c.audio.remote, isTrue);
      expect(c.audio.viewCurrent?.id, connectedTrack.id);
      expect(c.audio.outputPlaying, isFalse);
      expect((c.audio as ConnectAudio).starts, isEmpty);
      await c.transport('volume', {'volume': .3});
      expect(object(api.requests.last['data']), {
        'deviceId': 'browser-install',
        'surfaceId': 'browser-surface',
        'command': 'volume',
        'volume': .3,
      });
      await c.transport('pause');
      expect(c.events.last['event'], 'room:command');
      expect(c.events.last['command'], 'pause');
      expect((c.audio as ConnectAudio).starts, isEmpty);
      await close(c);
    },
  );

  test(
    'Account room adoption before socket connection does not claim output or start duplicate sound',
    () async {
      final c = await setup(), api = c.api as EcosystemApi;
      api.roomFixture = room();
      await c.receiveAccountState(connect(c));
      expect(c.room?['id'], 'room-test');
      expect(
        c.events,
        isEmpty,
        reason: 'An automatic snapshot must not use a claiming room join.',
      );
      expect(c.audio.remote, isTrue);
      expect((c.audio as ConnectAudio).starts, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('room:${c.namespace}'), 'room-test');
      await c.clearRoomParticipation();
      expect(c.room, isNull);
      expect(c.audio.remote, isFalse);
      expect(prefs.getString('room:${c.namespace}'), isNull);
      await close(c);
    },
  );

  test(
    'Only the selected room output loads audio; a stale revision cannot reclaim it',
    () async {
      final c = await setup(), api = c.api as EcosystemApi;
      api.roomFixture = room();
      c.room = room();
      await c.receiveAccountState(connect(c));
      expect((c.audio as ConnectAudio).starts, isEmpty);
      await c.receiveAccountState(connect(c, own: true));
      expect(c.outputHere, isTrue);
      expect(c.audio.remote, isFalse);
      expect((c.audio as ConnectAudio).starts, isNotEmpty);
      final starts = (c.audio as ConnectAudio).starts.length;
      await c.receiveAccountState(connect(c));
      expect(c.outputHere, isTrue);
      expect((c.audio as ConnectAudio).starts.length, starts);
      await close(c);
    },
  );

  test(
    'Room listeners without control rights still adjust output volume but cannot change the room track',
    () async {
      final c = await setup(), api = c.api as EcosystemApi;
      c.room = room()..['ownerId'] = 'another-user';
      api.roomFixture = c.room!;
      await c.receiveAccountState(connect(c));
      await c.transport('volume', {'volume': .2});
      expect(object(api.requests.last['data'])['command'], 'volume');
      await expectLater(
        c.transport('track', {'trackId': connectedTrack.id}),
        throwsA(isA<WaveException>()),
      );
      expect(c.events, isEmpty);
      await close(c);
    },
  );

  test(
    'A room without an output owner stays a silent mirror and Listen here claims through a real room join',
    () async {
      final c = await setup(), api = c.api as EcosystemApi;
      api.roomFixture = room();
      c.room = room();
      await c.receiveAccountState({
        ...connect(c),
        'activeDeviceId': null,
        'activeSurfaceId': null,
      });
      expect(c.outputHere, isFalse);
      expect(c.audio.remote, isTrue);
      expect(c.audio.outputPlaying, isFalse);
      expect((c.audio as ConnectAudio).starts, isEmpty);
      api.connection = {
        ...connect(c, own: true),
        'state': {...object(connect(c, own: true)['state']), 'revision': 20},
      };
      await c.listenHere();
      expect(c.events.single, {'event': 'room:join', 'roomId': 'room-test'});
      expect(c.outputHere, isTrue);
      expect((c.audio as ConnectAudio).starts, isNotEmpty);
      await close(c);
    },
  );

  test(
    'Session actions use real server results; failures do not remove rows and other-session logout preserves current',
    () async {
      final c = await setup(), api = c.api as EcosystemApi;
      api.sessionFixtures = [
        {'id': 'current', 'current': true},
        {'id': 'other', 'current': false},
      ];
      await c.refreshSessions();
      expect(c.currentSessionId, 'current');
      expect(c.sessions.length, 2);
      api.revokeFails = true;
      await expectLater(
        c.revokeSession('other'),
        throwsA(isA<WaveException>()),
      );
      expect(c.sessions.length, 2);
      expect(c.pendingSessionActions, isEmpty);
      api.revokeFails = false;
      await c.revokeSession(null);
      expect(c.sessions.single['id'], 'current');
      expect(c.api.token, 'test-token');
      expect(
        api.requests.any(
          (r) =>
              r['path'] == '/api/account/sessions' && r['method'] == 'DELETE',
        ),
        isTrue,
      );
      await close(c);
    },
  );

  test(
    'Late session responses cannot cross an account boundary; legacy missing routes are honest unavailable',
    () async {
      final c = await setup(), api = c.api as EcosystemApi;
      api.sessionsPending = Completer<Json>();
      final pending = c.refreshSessions();
      api.token = 'different-session';
      api.sessionsPending!.complete({
        'sessions': [
          {'id': 'old-private-session'},
        ],
      });
      await pending;
      expect(c.sessions, isEmpty);
      api.sessionsPending = null;
      api.sessionsMissing = true;
      await c.refreshSessions();
      expect(c.sessionsSupported, isFalse);
      expect(c.sessions, isEmpty);
      expect(c.sessionsLoading, isFalse);
      await close(c);
    },
  );

  test(
    'Duplicate transfer taps serialize until the real response and refreshed ownership arrive',
    () async {
      final c = await setup(), api = c.api as EcosystemApi;
      api.commandPending = Completer<Json>();
      final pending = c.transfer(
        'target-device',
        targetSurfaceId: 'target-surface',
      );
      expect(c.pendingDeviceActions, contains('transfer:target-device'));
      await c.transfer('target-device', targetSurfaceId: 'target-surface');
      expect(
        api.requests.where((r) => r['path'] == '/api/devices/command').length,
        1,
      );
      api.connection = {
        'activeDeviceId': 'target-device',
        'activeSurfaceId': 'target-surface',
        'state': {'revision': 20},
      };
      api.commandPending!.complete({'ok': true});
      await pending;
      expect(c.pendingDeviceActions, isEmpty);
      expect(c.activeDeviceId, 'target-device');
      await close(c);
    },
  );

  test(
    'A room transfer command adopts participation then awaits ready playback without sending room-wide commands',
    () async {
      final c = await setup(), api = c.api as EcosystemApi;
      final output = c.audio as ProtocolAudio;
      api.roomFixture = room();
      await c.receiveAccountState(connect(c));
      output.pendingLoad = Completer<void>();
      var finished = false;
      final command = c
          .receiveDeviceCommand({
            'command': 'track',
            'localOnly': true,
            'outputActive': true,
            'roomId': 'room-test',
            'trackId': connectedTrack.id,
            'queue': [connectedTrack.id],
            'position': 24,
            'playing': true,
          })
          .then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(
        finished,
        isFalse,
        reason: 'The receiver must not ACK a source before it is ready.',
      );
      expect(c.room?['id'], 'room-test');
      output.pendingLoad!.complete();
      await command;
      expect(output.current?.id, connectedTrack.id);
      expect(
        c.events,
        isEmpty,
        reason: 'Local output transfer cannot change the room master timeline.',
      );
      expect(
        c.outputHere,
        isTrue,
        reason:
            'Provisional output lasts until the committed account snapshot.',
      );
      await c.receiveAccountState(connect(c, own: true));
      expect(c.activeDeviceId, c.deviceId);
      await c.receiveDeviceCommand({
        'command': 'pause',
        'localOnly': true,
        'outputActive': false,
        'roomId': 'room-test',
      });
      expect(output.local.last, 'pause');
      expect(c.events, isEmpty);
      await close(c);
    },
  );

  test(
    'Failed room-source readiness does not retain provisional ownership',
    () async {
      final c = await setup(), api = c.api as EcosystemApi;
      api.roomFixture = room();
      await c.receiveAccountState(connect(c));
      (c.audio as ProtocolAudio).failLoad = true;
      await expectLater(
        c.receiveDeviceCommand({
          'command': 'track',
          'localOnly': true,
          'outputActive': true,
          'roomId': 'room-test',
          'trackId': connectedTrack.id,
          'queue': [connectedTrack.id],
        }),
        throwsA(isA<WaveException>()),
      );
      expect(c.outputHere, isFalse);
      expect(c.activeDeviceId, 'browser-install');
      expect(c.audio.outputPlaying, isFalse);
      await close(c);
    },
  );

  test(
    'A transfer rollback pause cancels a delayed source instead of allowing late autoplay or an obsolete ACK',
    () async {
      final c = await setup(), api = c.api as EcosystemApi;
      final output = c.audio as ProtocolAudio;
      api.roomFixture = room();
      await c.receiveAccountState(connect(c));
      output.pendingLoad = Completer<void>();
      final pending = c.receiveDeviceCommand({
        'command': 'track',
        'localOnly': true,
        'outputActive': true,
        'roomId': 'room-test',
        'trackId': connectedTrack.id,
        'queue': [connectedTrack.id],
        'playing': true,
      });
      final failed = expectLater(pending, throwsA(isA<WaveException>()));
      await Future<void>.delayed(Duration.zero);
      await c.receiveDeviceCommand({
        'command': 'pause',
        'localOnly': true,
        'outputActive': false,
        'roomId': 'room-test',
      });
      output.pendingLoad!.complete();
      await failed;
      expect(output.outputPlaying, isFalse);
      expect(c.outputHere, isFalse);
      expect(c.activeDeviceId, 'browser-install');
      await close(c);
    },
  );

  test(
    'Native requests explicitly distinguish the app from a browser without carrying callback keys',
    () async {
      final api = EcosystemApi();
      api.clientKind = 'windows';
      api.deviceName = 'GlukWave · Windows';
      expect(api.headers['X-GlukWave-Client'], 'native');
      expect(api.headers['X-GlukWave-Kind'], 'windows');
      expect(api.headers['X-GlukWave-Device-Name'], 'GlukWave · Windows');
      expect(api.headers.keys.any((key) => key.contains('API_KEY')), isFalse);
      api.dio.close(force: true);
    },
  );

  test(
    'Returning from OAuth refreshes actual connections instead of assuming the browser completed sign-in',
    () async {
      final c = await setup(), api = c.api as EcosystemApi;
      await c.connectProvider('spotify');
      expect(
        c.opened.single,
        startsWith('https://accounts.spotify.com/authorize'),
      );
      api.integrationFixtures = [
        {'provider': 'spotify', 'connected': false},
      ];
      final prompt = c.notice;
      await c.applicationResumed();
      expect(c.integrations.single['connected'], isFalse);
      expect(c.notice, prompt);
      api.integrationFixtures = [
        {'provider': 'spotify', 'connected': true},
      ];
      await c.applicationResumed();
      expect(c.integrations.single['connected'], isTrue);
      expect(c.notice, isNot(prompt));
      await close(c);
    },
  );
}
