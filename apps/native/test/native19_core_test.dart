import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/controller.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/core/qr_login.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/services/energy.dart';
import 'audio_lifecycle_test.dart' show NativeOutput;

class SavedApi extends WaveApi {
  final calls = <String>[];
  bool available = false;
  bool permitted = true;
  int downloadCount = 0;
  SavedApi() : super('https://wave.test');
  @override
  Future<Json> localeMetadata(String browserLanguage) async =>
      throw const WaveException('Offline', 'network');
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    calls.add(path);
    if (!available) throw const WaveException('No connection', 'network');
    if (path.endsWith('/info')) {
      return {
        'status': 'pending',
        'deviceName': 'Living room Windows',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 2))
            .millisecondsSinceEpoch,
      };
    }
    if (path.endsWith('/playback')) {
      return {
        'playback': {
          'kind': 'audio',
          'url': '/api/audio/saved',
          'offline': permitted,
        },
      };
    }
    if (path.endsWith('/lyrics')) {
      return {
        'lines': [
          {'time': 0, 'text': 'Saved words'},
        ],
      };
    }
    return {};
  }

  @override
  Future<void> download(
    WaveTrack track,
    File target, {
    void Function(double)? progress,
    CancelToken? cancelToken,
  }) async {
    await target.writeAsBytes([73, 68, 51, ...List.filled(2048, 42)]);
    downloadCount++;
    progress?.call(1);
  }
}

class CoverAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final picture = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    return ResponseBody.fromBytes(
      picture,
      200,
      headers: {
        'content-type': ['image/png'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class PendingSavedApi extends SavedApi {
  final pending = Completer<Json>();
  final blocked = <String>[];
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    if (path.endsWith('/first/playback')) {
      blocked.add(path);
      return pending.future;
    }
    return super.call(path, method: method, data: data, query: query);
  }
}

WaveTrack savedTrack(String id, {String artwork = ''}) => WaveTrack({
  'id': id,
  'title': 'Saved $id',
  'artist': 'Wave artist',
  'duration': 180,
  'artwork': artwork,
  'source': 'local',
  'playback': {'kind': 'audio', 'offline': true},
});

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
  test('Guard accepts only own-server app challenges or a manual code', () {
    const id = '45d445e9-3a2e-43cb-9274-a6804cfd12c9',
        origin = 'https://wave.test';
    for (final value in [id, '$origin/app/?qr=$id', '$origin/app?qr=$id']) {
      expect(qrChallengeId(value, origin), id);
    }
    for (final value in [
      'https://evil.test/app?qr=$id',
      'https://wave.test.evil.test/app?qr=$id',
      'http://wave.test/app?qr=$id',
      'https://wave.test:8443/app?qr=$id',
      'https://attacker@wave.test/app?qr=$id',
      'https:missinghost',
      'glukwave://app?qr=$id',
      '$origin/other?qr=$id',
      '$origin/app?qr=$id&qr=$id',
      '$origin/app?qr=../bad',
      'tiny',
    ]) {
      expect(
        () => qrChallengeId(value, origin),
        throwsFormatException,
        reason: value,
      );
    }
  });
  test(
    'Energy follows OS and low battery, remembers override and stops background polling',
    () async {
      var reads = 0;
      Json state = {'saving': false, 'battery': 18, 'charging': false};
      final preferences = await SharedPreferences.getInstance();
      final policy = EnergyPolicy(
        mobile: true,
        readSystem: () async {
          reads++;
          return state;
        },
      );
      await policy.initialize(preferences);
      expect(policy.saving, true);
      state = {...state, 'charging': true};
      await policy.refresh();
      expect(policy.saving, false);
      state = {...state, 'saving': true};
      await policy.refresh();
      expect(policy.saving, true);
      await policy.setMode('off');
      expect(policy.saving, false);
      final restored = EnergyPolicy(
        mobile: true,
        readSystem: () async => state,
      );
      await restored.initialize(preferences);
      expect(restored.mode, 'off');
      expect(restored.saving, false);
      restored.dispose();
      await policy.setMode('on');
      expect(policy.saving, true);
      policy.foreground(false);
      final before = reads;
      await policy.refresh();
      expect(reads, before);
      policy.foreground(true);
      await Future<void>.delayed(Duration.zero);
      expect(reads, greaterThan(before));
      policy.dispose();
    },
  );
  test(
    'Offline manifest, pinned audio, artwork and lyrics survive a fresh cache instance',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'wave-native19-reopen-',
      );
      final api = SavedApi()..token = 'private-test-token';
      final covers = CoverAdapter();
      api.dio.httpClientAdapter = covers;
      final first = MusicCache(api, supportDirectory: () async => directory);
      final track = savedTrack(
        'first',
        artwork: 'https://images.test/cover.png',
      );
      try {
        await first.open('owner');
        await first.save(track, manual: true);
        await first.saveLyrics(track.id, {
          'lines': [
            {'time': 0, 'text': 'Offline words'},
          ],
        });
        expect(
          covers.requests.single.headers.containsKey('Authorization'),
          false,
        );
        final second = MusicCache(api, supportDirectory: () async => directory);
        await second.open('owner');
        expect(second.savedTracks.single.id, track.id);
        expect(object(second.entries[track.id])['manual'], true);
        expect(await second.fileFor(track.id), isNotNull);
        expect(
          await File(second.artworkForUrl(track.artwork)!).readAsBytes(),
          covers.picture,
        );
        expect(
          objects((await second.lyricsFor(track.id))!['lines']).single['text'],
          'Offline words',
        );
        final audioBytes = (object(second.entries[track.id])['bytes'] as num)
            .toInt();
        expect(second.bytes, greaterThan(audioBytes));
        await second.clear();
        expect(
          second.contains(track.id),
          true,
          reason: 'Temporary cleanup preserves pinned music.',
        );
        await second.clear(includingDownloads: true);
        expect(second.savedTracks, isEmpty);
        expect(
          second.directory.listSync().whereType<File>().where(
            (f) => !f.path.endsWith('manifest.json'),
          ),
          isEmpty,
        );
        second.dispose();
      } finally {
        first.dispose();
        api.dio.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'Pinning an older audio-only cache adds durable art without re-downloading audio',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'wave-native19-migrate-',
      );
      final api = SavedApi(), covers = CoverAdapter();
      api.dio.httpClientAdapter = covers;
      final cache = MusicCache(api, supportDirectory: () async => directory);
      try {
        await cache.open('owner');
        await cache.save(savedTrack('older'));
        final updated = savedTrack(
          'older',
          artwork: 'https://images.test/new.png',
        );
        await cache.save(updated, manual: true);
        expect(api.downloadCount, 1);
        expect(cache.artworkForUrl(updated.artwork), isNotNull);
        expect(cache.savedTracks.single.artwork, updated.artwork);
        expect(object(cache.entries['older'])['manual'], true);
      } finally {
        await cache.clear(includingDownloads: true);
        cache.dispose();
        api.dio.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'Forged manifest paths never read or delete files outside the cache',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'wave-native19-path-',
      );
      final api = SavedApi(),
          cache = MusicCache(
            SavedApi(),
            supportDirectory: () async => directory,
          );
      try {
        await cache.open('owner');
        final outside = File('${directory.path}/keep.audio');
        await outside.writeAsBytes([1, 2, 3]);
        cache.entries['forged'] = {
          'file': '../keep.audio',
          'bytes': 3,
          'cover': '../keep.audio',
          'track': savedTrack('forged').json,
        };
        expect(cache.artworkPath('forged'), null);
        expect(await cache.fileFor('forged'), null);
        expect(await outside.exists(), true);
      } finally {
        cache.api.dio.close(force: true);
        api.dio.close(force: true);
        cache.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'Saved playback, next and repeat stay local despite stale room and remote output',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'wave-native19-local-',
      );
      final api = SavedApi()..token = 'saved-session';
      final cache = MusicCache(api, supportDirectory: () async => directory),
          output = NativeOutput();
      final audio = WaveAudioHandler(api, cache, output: output)
        ..autoCache = false;
      final c = WaveController(api, cache, audio)
        ..deviceId = 'phone'
        ..user = WaveUser({'id': 'owner', 'plan': 'free'});
      final first = savedTrack('first'), second = savedTrack('second');
      try {
        await cache.open(c.namespace);
        c.waveforms.open(cache.directory);
        await cache.save(first, manual: true);
        await cache.save(second, manual: true);
        await cache.saveLyrics(first.id, {
          'lines': [
            {'time': 0, 'text': 'Saved first'},
          ],
        });
        c.tracks = [first, second, savedTrack('not-downloaded')];
        c.room = {'id': 'stale-jam', 'type': 'jam', 'ownerId': 'someone-else'};
        c.connect = {
          'activeDeviceId': 'old-pc',
          'activeSurfaceId': 'old-surface',
        };
        expect(c.canControl, false);
        await c.play(first, list: c.tracks);
        expect(c.localSavedPlayback, true);
        expect(c.room, null);
        expect(c.outputHere, true);
        expect(c.controllingRemote, false);
        expect(audio.offlineOnly, true);
        c.online =
            true; // Local saved session remains private even with internet.
        expect(audio.viewTracks.map((t) => t.id), ['first', 'second']);
        expect(output.loaded.single, endsWith('.audio'));
        expect(output.active, true);
        await c.transport('repeat', {'repeat': 'one'});
        await c.transport('next');
        expect(audio.current?.id, 'second');
        expect(output.loaded.length, 2);
        await c.receiveAccountState({
          'activeDeviceId': 'old-pc',
          'state': {
            'trackId': 'not-downloaded',
            'playing': true,
            'revision': 999,
          },
        });
        expect(audio.current?.id, 'second');
        expect(c.controllingRemote, false);
        expect(
          objects((await c.lyricsFor(first))['lines']).single['text'],
          'Saved first',
        );
        await c.setEnergyMode('on');
        expect(audio.prepareNext, false);
        expect(output.active, true);
        c.setVisualForeground(false);
        expect(output.active, true);
        expect(
          api.calls,
          isEmpty,
          reason:
              'No extractor, synchronization, recommendation or lyrics request is needed.',
        );
        await c.refresh();
        expect(c.online, false);
        expect(c.user?.id, 'owner');
        expect(cache.savedTracks.length, 2);
      } finally {
        c.dispose();
        await audio.release();
        cache.activeId = null;
        await cache.clear(includingDownloads: true);
        cache.dispose();
        api.dio.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'Guard confirmation cannot cross an account change and does not approve external QR',
    () async {
      final api = SavedApi()
        ..available = true
        ..token = 'account-one';
      final cache = MusicCache(api),
          audio = WaveAudioHandler(
            api,
            MusicCache(api),
            output: NativeOutput(),
          );
      final c = WaveController(api, cache, audio)
        ..user = WaveUser({'id': 'one'});
      const id = '45d445e9-3a2e-43cb-9274-a6804cfd12c9';
      try {
        await expectLater(
          c.qrInfo('https://evil.test/app?qr=$id'),
          throwsA(isA<WaveException>()),
        );
        expect(api.calls, isEmpty);
        await c.qrInfo(id);
        api.token = 'account-two';
        c.user = WaveUser({'id': 'two'});
        await expectLater(c.approveQr(id), throwsA(isA<WaveException>()));
        expect(api.calls.where((p) => p.endsWith('/approve')), isEmpty);
        await c.qrInfo(id);
        await c.approveQr(id);
        expect(api.calls.where((p) => p.endsWith('/approve')).length, 1);
        await expectLater(c.approveQr(id), throwsA(isA<WaveException>()));
      } finally {
        c.dispose();
        await audio.release();
        cache.dispose();
        api.dio.close(force: true);
      }
    },
  );
  test(
    'Queued resolver can be cancelled; duplicate saves share one request and permissions remain required',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'wave-native19-cancel-',
      );
      final api = PendingSavedApi()..available = true;
      final cache = MusicCache(api, supportDirectory: () async => directory);
      final audio = WaveAudioHandler(api, cache, output: NativeOutput());
      final c = WaveController(api, cache, audio)
        ..user = WaveUser({'id': 'owner'});
      try {
        await cache.open(c.namespace);
        final first = c.downloadTrack(savedTrack('first'));
        final duplicate = c.downloadTrack(savedTrack('first'));
        final second = c.downloadTrack(savedTrack('second'));
        expect(identical(first, duplicate), true);
        await Future<void>.delayed(Duration.zero);
        expect(api.blocked.length, 1);
        expect(api.calls, isEmpty);
        expect(cache.progress.keys.toSet(), {'first', 'second'});
        cache.cancel('first');
        api.pending.complete({
          'playback': {
            'kind': 'audio',
            'url': '/api/audio/first',
            'offline': true,
          },
        });
        await Future.wait([first, duplicate, second]);
        expect(cache.contains('first'), false);
        expect(cache.contains('second'), true);
        expect(cache.progress, isEmpty);
        api.permitted = false;
        await expectLater(
          c.downloadTrack(savedTrack('forbidden')),
          throwsA(isA<WaveException>()),
        );
        expect(cache.contains('forbidden'), false);
        expect(cache.failureFor('forbidden'), isNotNull);
      } finally {
        c.dispose();
        await audio.release();
        cache.activeId = null;
        await cache.clear(includingDownloads: true);
        cache.dispose();
        api.dio.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'Explicit uncached catalog play leaves local mode after an outage',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'wave-native19-online-',
      );
      final api = SavedApi();
      final cache = MusicCache(api, supportDirectory: () async => directory),
          output = NativeOutput();
      final audio = WaveAudioHandler(api, cache, output: output)
        ..autoCache = false;
      final c = WaveController(api, cache, audio)
        ..deviceId = 'phone'
        ..user = WaveUser({'id': 'owner'});
      try {
        await cache.open(c.namespace);
        final local = savedTrack('local'), remote = savedTrack('online');
        await cache.save(local, manual: true);
        await c.playSaved(local);
        expect(c.localSavedPlayback, true);
        api.available = true;
        await c.play(remote, list: [remote]);
        expect(c.localSavedPlayback, false);
        expect(c.online, true);
        expect(audio.offlineOnly, false);
        expect(output.loaded.last, startsWith('https://wave.test/api/audio/'));
        expect(api.calls, ['/api/tracks/online/playback']);
        expect(output.active, true);
      } finally {
        c.dispose();
        await audio.release();
        cache.activeId = null;
        await cache.clear(includingDownloads: true);
        cache.dispose();
        api.dio.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'Cold start restores scoped account library and saved music while server is unreachable',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'wave-native19-cold-',
      );
      final api = SavedApi();
      final cache = MusicCache(api, supportDirectory: () async => directory),
          output = NativeOutput();
      final audio = WaveAudioHandler(api, cache, output: output)
        ..autoCache = false;
      final c = WaveController(api, cache, audio);
      final owner = WaveUser({
        'id': 'cold-owner',
        'displayName': 'Offline listener',
        'plan': 'free',
      });
      final storage = <String, String>{
        'session:${api.server}': jsonEncode({
          'token': 'saved-session',
          'user': owner.json,
        }),
      };
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async {
          final args = object(call.arguments), key = args['key']?.toString();
          if (call.method == 'read') return storage[key];
          if (call.method == 'write' && key != null) {
            storage[key] = args['value'].toString();
          }
          if (call.method == 'delete') storage.remove(key);
          return null;
        },
      );
      try {
        c.user = owner;
        final scope = c.namespace;
        c.user = null;
        final initial = MusicCache(
          api,
          supportDirectory: () async => directory,
        );
        await initial.open(scope);
        final track = savedTrack('cold');
        await initial.save(track, manual: true);
        initial.dispose();
        await File('${directory.path}/state-$scope.json').writeAsString(
          jsonEncode({
            'tracks': [track.json],
            'likedIds': ['cold'],
            'playlists': [],
            'history': [],
            'settings': {},
            'config': {},
          }),
        );
        await c.initialize();
        expect(c.loggedIn, true);
        expect(c.user?.id, owner.id);
        expect(c.online, false);
        expect(c.loading, false);
        expect(c.likedIds, ['cold']);
        expect(c.savedTracks.single.id, 'cold');
        expect(c.tracks.single.id, 'cold');
        api.calls.clear();
        await c.playSaved(c.savedTracks.single);
        await Future<void>.delayed(Duration.zero);
        expect(output.active, true);
        expect(output.loaded.single, endsWith('.audio'));
        expect(api.calls, isEmpty);
      } finally {
        c.dispose();
        await audio.release();
        cache.activeId = null;
        if (cache.ready) await cache.clear(includingDownloads: true);
        cache.dispose();
        api.dio.close(force: true);
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
        await directory.delete(recursive: true);
      }
    },
  );
}
