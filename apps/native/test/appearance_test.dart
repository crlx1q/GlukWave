import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/appearance.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/appearance_store.dart';

class ControlledAppearanceApi extends WaveApi {
  final pendingResponse = Completer<Json>();
  final requested = Completer<void>();
  ControlledAppearanceApi() : super('http://127.0.0.1:4000');
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) {
    requested.complete();
    return pendingResponse.future;
  }
}

class SequencedAppearanceApi extends WaveApi {
  final payloads = <Json>[];
  final responses = <Completer<Json>>[];
  SequencedAppearanceApi() : super('http://127.0.0.1:4000');
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) {
    payloads.add(object(data));
    final response = Completer<Json>();
    responses.add(response);
    return response.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Hex accepts short input and invalid colors never replace a working palette',
    () {
      expect(normalizeHex(' AbC '), '#aabbcc');
      expect(normalizeHex('#B1A2DE'), '#b1a2de');
      expect(() => normalizeHex('javascript:red'), throwsFormatException);
      final result = const WaveCustomization().merge({
        'appearance': {
          'light': {'bg': 'invalid', 'accent': '#abc'},
        },
      });
      expect(result.appearance.light.bg, WavePalette.light.bg);
      expect(result.appearance.light.accent, '#aabbcc');
      expect(result.appearance.dark.toJson(), WavePalette.dark.toJson());
    },
  );

  test('Palette edits and reset preserve the opposite theme', () {
    final original = const WaveCustomization().merge({
      'theme': 'system',
      'reducedMotion': true,
      'appearance': {
        'dark': {'bg': '#111122', 'accent': '#445566'},
        'light': {'surface': '#f0faf0'},
        'radius': 38,
        'compact': true,
        'speed': 2,
        'waveStyle': 'particles',
        'coverKind': 'cd',
        'cover3d': false,
      },
    });
    final reset = original.merge(original.resetPalette('light'));
    expect(reset.theme, 'system');
    expect(reset.appearance.light.toJson(), WavePalette.light.toJson());
    expect(reset.appearance.dark.toJson(), original.appearance.dark.toJson());
    expect(reset.appearance.radius, 24);
    expect(reset.appearance.compact, isFalse);
    expect(reset.appearance.coverKind, 'vinyl');
    expect(reset.appearance.cover3d, isTrue);
    expect(reset.reducedMotion, isFalse);
    expect(
      const WaveAppearance().merge({'radius': -20, 'speed': 50}).radius,
      8,
    );
    expect(const WaveAppearance().merge({'speed': 50}).speed, 2);
  });

  test(
    'Guest changes survive restart and do not cross account scopes',
    () async {
      final prefs = await SharedPreferences.getInstance(),
          api = WaveApi('http://127.0.0.1:4000');
      final store = AppearanceStore(api, prefs);
      await store.selectScope(null);
      await store.change({
        'theme': 'dark',
        'appearance': {
          'dark': {'bg': '#121b25'},
          'compact': true,
        },
      });
      expect(store.pending, isFalse);
      store.dispose();
      final restored = AppearanceStore(api, prefs);
      await restored.selectScope(null);
      expect(restored.current.theme, 'dark');
      expect(restored.current.appearance.dark.bg, '#121b25');
      await restored.selectScope('account-b', fallback: {'theme': 'light'});
      expect(restored.current.theme, 'light');
      expect(restored.current.appearance.compact, isFalse);
      await restored.selectScope(null);
      expect(restored.current.appearance.dark.bg, '#121b25');
      restored.dispose();
      api.dio.close(force: true);
    },
  );

  test(
    'Offline PATCH retries from disk and preserves a remote edit of the other palette',
    () async {
      // This is a transport integration test, rather than a mocked HTTP widget.
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      bool available = false;
      Json serverSettings = const WaveCustomization().toSettings();
      final payloads = <Json>[];
      server.listen((request) async {
        final patch = object(
          jsonDecode(await utf8.decoder.bind(request).join()),
        );
        payloads.add(patch);
        expect(request.method, 'PATCH');
        expect(
          request.headers.value('authorization'),
          'Bearer real-test-session',
        );
        request.response.headers.contentType = ContentType.json;
        if (!available) {
          request.response.statusCode = 503;
          request.response.write(
            jsonEncode({
              'error': {'message': 'offline', 'code': 'network'},
            }),
          );
        } else {
          serverSettings = mergeAppearancePatch(serverSettings, patch);
          request.response.write(jsonEncode({'settings': serverSettings}));
        }
        await request.response.close();
      });
      final api = WaveApi('http://127.0.0.1:${server.port}')
        ..token = 'real-test-session';
      final prefs = await SharedPreferences.getInstance();
      final store = AppearanceStore(api, prefs);
      await store.selectScope('account-a');
      await store.change({
        'appearance': {
          'light': {'accent': '#7ca8bb'},
          'radius': 34,
        },
      });
      await store.flush();
      expect(store.pending, isTrue);
      expect(store.lastError, 'offline');
      store.dispose();
      final restored = AppearanceStore(api, prefs);
      await restored.selectScope('account-a');
      expect(restored.pending, isTrue);
      expect(restored.current.appearance.light.accent, '#7ca8bb');
      available = true;
      serverSettings = mergeAppearancePatch(serverSettings, {
        'appearance': {
          'dark': {'accent': '#334455'},
        },
      });
      await restored.receiveRemote(serverSettings);
      expect(restored.pending, isFalse);
      expect(restored.current.appearance.dark.accent, '#334455');
      expect(restored.current.appearance.light.accent, '#7ca8bb');
      expect(payloads.last, {
        'appearance': {
          'light': {'accent': '#7ca8bb'},
          'radius': 34,
        },
      });
      restored.dispose();
      api.dio.close(force: true);
      await server.close(force: true);
    },
  );

  test(
    'An old account response cannot change guest appearance after logout',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final api = ControlledAppearanceApi()..token = 'session';
      final store = AppearanceStore(api, prefs);
      await store.selectScope('account');
      await store.change({'theme': 'dark'});
      final operation = store.flush();
      await api.requested.future;
      api.token = null;
      await store.selectScope(null);
      await store.change({
        'appearance': {
          'light': {'accent': '#dbb976'},
        },
      });
      api.pendingResponse.complete({
        'settings': {
          'theme': 'dark',
          'appearance': {
            'light': {'accent': '#ff0000'},
          },
        },
      });
      await operation;
      expect(store.current.theme, 'light');
      expect(store.current.appearance.light.accent, '#dbb976');
      expect(store.pending, isFalse);
      store.dispose();
      api.dio.close(force: true);
    },
  );

  test(
    'Newer socket settings survive an older PATCH while sparse local edits stay visible',
    () async {
      final api = SequencedAppearanceApi()..token = 'account-a-session';
      final store = AppearanceStore(api, await SharedPreferences.getInstance());
      final baseline = {
        ...const WaveCustomization().toSettings(),
        'revision': 10,
      };
      await store.selectScope('account-a', fallback: baseline);
      await store.change({
        'appearance': {
          'light': {'accent': '#111111'},
        },
      });
      final first = store.flush();
      expect(api.responses.length, 1);
      await store.change({
        'appearance': {
          'light': {'accent': '#222222'},
          'radius': 30,
        },
      });
      final remote = mergeAppearancePatch(baseline, {
        'appearance': {
          'dark': {'accent': '#334455'},
          'light': {'accent': '#aabbcc'},
        },
        'revision': 12,
      });
      expect(
        await store.receiveRemote(
          remote,
          revision: 12,
          expectedToken: api.token,
          expectedOrigin: api.server,
        ),
        isTrue,
      );
      expect(store.current.appearance.light.accent, '#222222');
      expect(store.current.appearance.dark.accent, '#334455');
      api.responses.first.complete({
        'settings': mergeAppearancePatch(baseline, {
          'appearance': {
            'light': {'accent': '#111111'},
          },
          'revision': 11,
        }),
        'revision': 11,
      });
      await first;
      expect(store.remoteRevision, 12);
      expect(store.current.appearance.light.accent, '#222222');
      expect(store.current.appearance.dark.accent, '#334455');
      expect(store.pending, isTrue);
      final second = store.flush();
      expect(api.payloads.last, {
        'appearance': {
          'light': {'accent': '#222222'},
          'radius': 30.0,
        },
      });
      api.responses.last.complete({
        'settings': mergeAppearancePatch(remote, {
          'appearance': {
            'light': {'accent': '#222222'},
            'radius': 30,
          },
          'revision': 13,
        }),
        'revision': 13,
      });
      await second;
      expect(store.pending, isFalse);
      expect(await store.receiveRemote(remote, revision: 12), isFalse);
      expect(store.remoteRevision, 13);
      expect(store.current.appearance.radius, 30);
      store.dispose();
      api.dio.close(force: true);
    },
  );

  test(
    'In-flight sparse edits overlay remote events and survive a failed transport restart',
    () async {
      final api = SequencedAppearanceApi()..token = 'account-a-session';
      final prefs = await SharedPreferences.getInstance();
      final store = AppearanceStore(api, prefs);
      await store.selectScope('account-a');
      await store.change({
        'appearance': {
          'light': {'accent': '#111111'},
        },
      });
      final request = store.flush();
      await store.receiveRemote({
        'theme': 'dark',
        'appearance': {
          'light': {'accent': '#aaaaaa'},
          'dark': {'accent': '#334455'},
        },
        'revision': 4,
      }, revision: 4);
      expect(store.current.appearance.light.accent, '#111111');
      await store.change({
        'appearance': {
          'light': {'accent': '#222222'},
        },
      });
      api.responses.first.completeError(const WaveException('offline'));
      await request;
      store.dispose();
      final restored = AppearanceStore(api, prefs);
      await restored.selectScope('account-a');
      expect(restored.current.theme, 'dark');
      expect(restored.current.appearance.dark.accent, '#334455');
      expect(restored.current.appearance.light.accent, '#222222');
      final retry = restored.flush();
      expect(api.payloads.last, {
        'appearance': {
          'light': {'accent': '#222222'},
        },
      });
      api.responses.last.complete({
        'settings': {
          'theme': 'dark',
          'appearance': {
            'light': {'accent': '#222222'},
            'dark': {'accent': '#334455'},
          },
          'revision': 5,
        },
        'revision': 5,
      });
      await retry;
      expect(restored.pending, isFalse);
      restored.dispose();
      api.dio.close(force: true);
    },
  );

  test(
    'Old session and origin cannot reconcile or block a new account request',
    () async {
      final api = SequencedAppearanceApi()..token = 'account-a-session';
      final store = AppearanceStore(api, await SharedPreferences.getInstance());
      await store.selectScope('account-a');
      await store.change({'theme': 'dark'});
      final first = store.flush();
      api.server = 'http://127.0.0.1:5000';
      api.token = 'account-b-session';
      await store.selectScope('account-b');
      await store.change({
        'appearance': {
          'light': {'accent': '#dbb976'},
        },
      });
      final second = store.flush();
      expect(api.responses.length, 2);
      expect(
        await store.receiveRemote(
          {'theme': 'dark', 'revision': 99},
          revision: 99,
          expectedToken: 'account-a-session',
          expectedOrigin: 'http://127.0.0.1:4000',
        ),
        isFalse,
      );
      api.responses.first.complete({
        'settings': {'theme': 'dark', 'revision': 99},
      });
      await first;
      expect(store.remoteRevision, -1);
      expect(store.current.theme, 'light');
      api.responses.last.complete({
        'settings': {
          'appearance': {
            'light': {'accent': '#dbb976'},
          },
          'revision': 1,
        },
      });
      await second;
      expect(store.pending, isFalse);
      expect(store.current.appearance.light.accent, '#dbb976');
      store.dispose();
      api.dio.close(force: true);
    },
  );
}
