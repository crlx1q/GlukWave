import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/controller.dart';
import 'package:glukwave/core/discord.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';

Json discordFixture({String status = 'active', bool eligible = true}) => {
  'eligible': eligible,
  'configured': true,
  'connected': true,
  'needsReconnect': false,
  'enabled': true,
  'allowJoin': true,
  'status': status,
  'identity': {
    'id': 'qa-discord',
    'username': 'quiet_listener',
    'displayName': 'Quiet listener',
    'avatarUrl': '',
  },
  'device': {'name': 'GlukWave · Windows', 'kind': 'windows'},
  'activity': {
    'trackId': 'qa-track',
    'title': 'A quiet place',
    'artist': 'QA catalogue artist',
    'album': 'Quiet hours',
    'cover': '',
    'position': 25,
    'duration': 178,
    'playing': true,
    'trackUrl': 'https://wave.gluk.tech/app/?track=qa-track',
    'joinUrl': 'https://wave.gluk.tech/app/?listen=qa-host',
  },
};

class DiscordApi extends WaveApi {
  final requests = <({String path, String method, Json data})>[];
  Json state = discordFixture();
  Completer<Json>? pending;
  bool fail = false;
  DiscordApi() : super('http://127.0.0.1:4000');
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    requests.add((path: path, method: method, data: object(data)));
    if (path == '/api/discord') {
      if (fail) {
        throw const WaveException(
          'Private provider failure and token: secret',
          'DISCORD_FAILURE',
          503,
        );
      }
      if (method == 'PATCH') state = {...state, ...object(data)};
      return pending?.future ?? state;
    }
    if (path == '/api/integrations/discord/connect') {
      return {'url': 'https://discord.com/oauth2/authorize?state=qa'};
    }
    if (path == '/api/integrations') {
      return {
        'connections': [
          {'provider': 'discord', 'connected': true},
        ],
      };
    }
    if (path == '/api/connect') return {'connect': {}};
    if (path == '/api/account/sessions') return {'sessions': []};
    return {};
  }
}

class DiscordController extends WaveController {
  final opened = <String>[];
  DiscordController(super.api, super.cache, super.audio);
  @override
  Future<void> openUrl(String value) async {
    opened.add(value);
  }
}

Future<DiscordController> discordController() async {
  SharedPreferences.setMockInitialValues({});
  final api = DiscordApi(), cache = MusicCache(api);
  final c = DiscordController(api, cache, WaveAudioHandler(api, cache));
  c.preferences = await SharedPreferences.getInstance();
  c.api.token = 'isolated-qa-token';
  c.user = WaveUser({'id': 'qa-user', 'username': 'qa', 'plan': 'beta'});
  c.online = true;
  c.loading = false;
  return c;
}

Future<void> closeDiscordController(DiscordController c) async {
  c.dispose();
  await c.audio.release();
  c.api.dio.close(force: true);
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
    'Public activity progresses locally without sending playback to Discord',
    () {
      final start = DateTime.utc(2026, 10, 9);
      final d = DiscordConnection(discordFixture(), receivedAt: start);
      expect(d.positionAt(start.add(const Duration(seconds: 10))), 35);
      expect(d.positionAt(start.subtract(const Duration(seconds: 10))), 25);
      expect(d.positionAt(start.add(const Duration(hours: 1))), 178);
      final paused = DiscordConnection({
        ...discordFixture(),
        'activity': {...d.activity, 'playing': false},
      }, receivedAt: start);
      expect(paused.positionAt(start.add(const Duration(seconds: 10))), 25);
      expect(
        DiscordConnection({
          ...discordFixture(),
          'status': 'internal_provider_code',
        }).status,
        'unavailable',
      );
      final unsafe = DiscordConnection({
        'activity': {
          'trackUrl': 'javascript:alert(1)',
          'joinUrl': 'https://token@evil.test',
          'duration': double.nan,
          'position': double.infinity,
        },
      });
      expect(unsafe.trackUrl, isNull);
      expect(unsafe.joinUrl, isNull);
      expect(unsafe.positionAt(start), 0);
    },
  );
  test(
    'Native presence loads server canonical output rather than local player',
    () async {
      final c = await discordController();
      await c.refreshDiscord();
      expect(c.discordConnection!.title, 'A quiet place');
      expect(c.audio.current, isNull);
      expect(c.discordConnection!.deviceName, 'GlukWave · Windows');
      expect(c.discordLoading, isFalse);
      await closeDiscordController(c);
    },
  );
  test(
    'Older pending request cannot replace a new authoritative socket snapshot',
    () async {
      final c = await discordController(), api = c.api as DiscordApi;
      api.pending = Completer<Json>();
      final old = c.refreshDiscord();
      c.receiveDiscordState({
        ...discordFixture(status: 'disabled'),
        'enabled': false,
      });
      api.pending!.complete(discordFixture());
      await old;
      expect(c.discordConnection!.status, 'disabled');
      expect(c.discordLoading, isFalse);
      await closeDiscordController(c);
    },
  );
  test(
    'Changing accounts during a request does not expose previous identity',
    () async {
      final c = await discordController(), api = c.api as DiscordApi;
      api.pending = Completer<Json>();
      final old = c.refreshDiscord();
      c.api.token = 'different-qa-account';
      api.pending!.complete(discordFixture());
      await old;
      expect(c.discordConnection, isNull);
      await closeDiscordController(c);
    },
  );
  test(
    'Errors stay scoped and omit provider secrets; save waits for server',
    () async {
      final c = await discordController(), api = c.api as DiscordApi;
      await c.refreshDiscord();
      api.fail = true;
      await c.refreshDiscord();
      expect(c.discordError, 'refresh_failed');
      expect(c.error, isNull);
      expect(c.online, isTrue);
      expect(c.discordConnection!.enabled, isTrue);
      await c.updateDiscord({'enabled': false});
      expect(c.discordError, 'save_failed');
      expect(
        c.discordConnection!.enabled,
        isTrue,
        reason: 'Failed saves cannot pretend activity was disabled.',
      );
      api.fail = false;
      await c.updateDiscord({'enabled': false, 'allowJoin': false});
      expect(c.discordError, isNull);
      expect(c.discordConnection!.enabled, isFalse);
      expect(api.requests.last.path, '/api/discord');
      expect(api.requests.last.method, 'PATCH');
      expect(api.requests.last.data, {'enabled': false, 'allowJoin': false});
      await closeDiscordController(c);
    },
  );
  test(
    'OAuth browser handoff refreshes actual server link when app resumes',
    () async {
      final c = await discordController(), api = c.api as DiscordApi;
      await c.connectProvider('discord');
      expect(
        c.opened.single,
        startsWith('https://discord.com/oauth2/authorize'),
      );
      expect(
        c.discordConnection,
        isNull,
        reason: 'Opening a browser is not authorization.',
      );
      await c.applicationResumed();
      expect(api.requests.any((r) => r.path == '/api/discord'), isTrue);
      expect(c.discordConnection!.connected, isTrue);
      await closeDiscordController(c);
    },
  );
  test(
    'Free server status is authoritative even with stale paid client profile',
    () async {
      final c = await discordController(), api = c.api as DiscordApi;
      api.state = discordFixture(status: 'locked', eligible: false);
      await c.refreshDiscord();
      expect(c.user!.plan, 'beta');
      expect(c.discordConnection!.eligible, isFalse);
      await closeDiscordController(c);
    },
  );
  test(
    'Disposed request completion does not notify or recreate status',
    () async {
      final c = await discordController(), api = c.api as DiscordApi;
      api.pending = Completer<Json>();
      final old = c.refreshDiscord();
      await closeDiscordController(c);
      api.pending!.complete(discordFixture());
      await old;
      expect(c.discordConnection, isNull);
    },
  );
}
