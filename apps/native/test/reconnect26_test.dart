import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/controller.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'audio_lifecycle_test.dart' show NativeOutput;
import 'native19_core_test.dart' show SavedApi, savedTrack;

class ReconnectApi extends SavedApi {
  Completer<Json>? auth;
  int probes = 0, authCalls = 0;
  @override
  Future<Json> probe() async {
    probes++;
    if (!available) throw const WaveException('offline', 'NETWORK');
    return {};
  }

  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    if (path == '/api/auth/me') {
      authCalls++;
      if (auth != null) return auth!.future;
      if (!available) throw const WaveException('offline', 'NETWORK');
      return {
        'user': {'id': 'boot', 'plan': 'free'},
      };
    }
    if (path == '/api/library' && available) {
      return {
        'tracks': [savedTrack('fresh').json],
        'likedIds': ['fresh'],
        'playlists': [],
        'history': [],
      };
    }
    return super.call(path, method: method, data: data, query: query);
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
  test(
    'cold saved session is coherent before a stalled network; reconnect retains active decoder and queue',
    () async {
      final root = await Directory.systemTemp.createTemp('reconnect26-'),
          api = ReconnectApi()..auth = Completer<Json>();
      final cache = MusicCache(api, supportDirectory: () async => root),
          output = NativeOutput();
      final audio = WaveAudioHandler(api, cache, output: output)
        ..autoCache = false
        ..prepareNext = false;
      final c = WaveController(api, cache, audio),
          owner = WaveUser({'id': 'boot', 'plan': 'free'});
      c.user = owner;
      final scope = c.namespace;
      c.user = null;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => call.method == 'read'
            ? jsonEncode({'token': 'saved-token', 'user': owner.json})
            : null,
      );
      await File('${root.path}/state-$scope.json').writeAsString(
        jsonEncode({
          'tracks': [savedTrack('saved').json],
          'likedIds': ['saved'],
          'playlists': [],
          'history': [],
          'settings': {},
          'config': {},
        }),
      );
      try {
        var coherent = 0;
        c.addListener(() {
          if (!c.restoringLocal && c.user != null && c.tracks.isNotEmpty) {
            coherent++;
          }
        });
        await c.initialize();
        expect(c.restoringLocal, false);
        expect(c.loading, false);
        expect(c.user?.id, 'boot');
        expect(c.likedIds, ['saved']);
        expect(c.tracks.single.id, 'saved');
        expect(coherent, greaterThan(0));
        expect(api.authCalls, 1);
        final joined = c.refresh();
        await Future<void>.delayed(Duration.zero);
        expect(api.authCalls, 1);
        api.auth!.completeError(const WaveException('offline', 'NETWORK'));
        await joined;
        expect(c.online, false);
        expect(c.tracks.single.id, 'saved');
        // A local saved file stays active while the connection is revalidated.
        final local = savedTrack('saved');
        await cache.save(local, manual: true);
        await audio.playTrack(local, list: [local]);
        expect(output.active, true);
        final loads = output.loaded.length;
        await c.revalidateConnection();
        expect(c.online, false);
        expect(output.loaded.length, loads);
        expect(audio.current?.id, 'saved');
        api.available = true;
        api.auth = null;
        await c.revalidateConnection();
        expect(c.online, true);
        expect(
          c.tracks.map((track) => track.id),
          containsAll(['fresh', 'saved']),
        );
        expect(c.likedIds, ['fresh']);
        expect(output.active, true);
        expect(output.loaded.length, loads);
        expect(audio.current?.id, 'saved');
        expect(audio.tracks.single.id, 'saved');
        expect(api.probes, 2);
      } finally {
        c.dispose();
        await audio.release();
        cache.activeId = null;
        await cache.clear(includingDownloads: true);
        cache.dispose();
        api.diagnostics.dispose();
        api.dio.close(force: true);
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'a guest configuration outage is recorded as offline and can recover',
    () async {
      final root = await Directory.systemTemp.createTemp('reconnect26-guest-'),
          api = ReconnectApi();
      final cache = MusicCache(api, supportDirectory: () async => root),
          audio = WaveAudioHandler(api, cache, output: NativeOutput());
      final c = WaveController(api, cache, audio);
      c.preferences = await SharedPreferences.getInstance();
      try {
        await c.refresh();
        expect(c.online, false);
        api.available = true;
        await c.revalidateConnection();
        expect(c.online, true);
        expect(c.user, isNull);
      } finally {
        c.dispose();
        await audio.release();
        cache.dispose();
        api.diagnostics.dispose();
        api.dio.close(force: true);
        await root.delete(recursive: true);
      }
    },
  );
}
