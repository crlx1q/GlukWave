import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/controller.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/services/metadata_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

Json track(String id) => {
  'id': id,
  'title': id,
  'artist': 'Search fixture',
  'source': 'local',
  'duration': 240,
};

class SearchApi extends WaveApi {
  final requests =
      <({String path, String method, Json? query, dynamic data})>[];
  Future<Json> Function(String path, Json? query)? respond;
  SearchApi() : super('http://127.0.0.1:4012');
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    requests.add((path: path, method: method, query: query, data: data));
    return respond?.call(path, query) ?? Future.value({'tracks': []});
  }
}

Future<WaveController> fixture(SearchApi api) async {
  SharedPreferences.setMockInitialValues({});
  final cache = MusicCache(api);
  final c = WaveController(api, cache, WaveAudioHandler(api, cache));
  c.preferences = await SharedPreferences.getInstance();
  c.loading = false;
  return c;
}

Future<void> release(WaveController c) async {
  c.dispose();
  await c.audio.release();
  c.api.dio.close(force: true);
}

Future<void> until(WaveController c, bool Function() predicate) {
  if (predicate()) return Future.value();
  final done = Completer<void>();
  void changed() {
    if (!predicate()) return;
    c.removeListener(changed);
    done.complete();
  }

  c.addListener(changed);
  return done.future.timeout(
    const Duration(seconds: 5),
    onTimeout: () {
      c.removeListener(changed);
      throw TimeoutException(
        'Search did not reach its expected terminal state',
      );
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
  });

  test(
    'Pasted link is a result, never an implicit like or library refresh',
    () async {
      final api = SearchApi()
        ..respond = (path, _) async => {'track': track('resolved')};
      final c = await fixture(api);
      try {
        c.likedIds = ['already-liked'];
        await c.search(' https://soundcloud.com/example/song ');
        expect(c.results.single.id, 'resolved');
        expect(c.likedIds, ['already-liked']);
        expect(api.requests, hasLength(1));
        expect(api.requests.single.path, '/api/tracks/resolve');
        expect(api.requests.single.method, 'POST');
        expect(api.requests.single.data, {
          'url': 'https://soundcloud.com/example/song',
        });
        expect(c.searchLoading, false);
        expect(c.searchError, isNull);
      } finally {
        await release(c);
      }
    },
  );

  test(
    'Fast results retain provider errors until the deferred completion arrives',
    () async {
      final full = Completer<Json>();
      final api = SearchApi()
        ..respond = (_, query) async => query?['fast'] == '1'
            ? {
                'tracks': [track('fast')],
                'pendingProviders': ['youtube'],
                'errors': [
                  {'provider': 'spotify', 'message': 'Unavailable'},
                ],
              }
            : full.future;
      final c = await fixture(api);
      try {
        await c.search('quiet');
        expect(c.results.single.id, 'fast');
        expect(c.searchLoading, false);
        expect(c.searchPendingProviders, ['youtube']);
        expect(c.searchProviderErrors.single['provider'], 'spotify');
        expect(c.notice, isNull);
        final terminal = until(
          c,
          () => c.results.singleOrNull?.id == 'complete',
        );
        full.complete({
          'tracks': [track('complete')],
          'artists': [
            {'id': 'artist'},
          ],
        });
        await terminal;
        expect(c.searchPendingProviders, isEmpty);
        expect(c.searchProviderErrors, isEmpty);
        expect(c.artistResults.single['id'], 'artist');
      } finally {
        await release(c);
      }
    },
  );

  test(
    'Deferred outage preserves useful tracks and exposes an inline error',
    () async {
      final full = Completer<Json>();
      final api = SearchApi()
        ..respond = (_, query) async => query?['fast'] == '1'
            ? {
                'tracks': [track('usable')],
                'pendingProviders': ['youtube'],
              }
            : full.future;
      final c = await fixture(api);
      try {
        await c.search('partial');
        final terminal = until(c, () => c.searchError != null);
        full.completeError(
          const WaveException('Provider unavailable', 'OFFLINE', 503),
        );
        await terminal;
        expect(c.results.single.id, 'usable');
        expect(c.searchPendingProviders, isEmpty);
        expect(c.searchError, 'Provider unavailable');
      } finally {
        await release(c);
      }
    },
  );

  test(
    'A late query cannot replace results or errors of the newer query',
    () async {
      final old = Completer<Json>();
      final api = SearchApi()
        ..respond = (_, query) async => query?['q'] == 'old'
            ? old.future
            : {
                'tracks': [track('new')],
              };
      final c = await fixture(api);
      try {
        final first = c.search('old');
        await c.search('new');
        old.complete({
          'tracks': [track('old')],
          'errors': [
            {'message': 'Old error'},
          ],
        });
        await first;
        expect(c.results.single.id, 'new');
        expect(c.searchProviderErrors, isEmpty);
        expect(c.searchError, isNull);
      } finally {
        await release(c);
      }
    },
  );

  test(
    'Account change discards an earlier result even when it completes later',
    () async {
      final old = Completer<Json>();
      final api = SearchApi()..token = 'first';
      api.respond = (_, query) async => query?['q'] == 'old'
          ? old.future
          : {
              'tracks': [track('own-new-account')],
            };
      final c = await fixture(api);
      try {
        final first = c.search('old');
        api.token = 'second';
        await c.search('new');
        old.complete({
          'tracks': [track('private-old-account')],
        });
        await first;
        expect(c.results.single.id, 'own-new-account');
        expect(c.searchError, isNull);
      } finally {
        await release(c);
      }
    },
  );

  test(
    'Search failure reaches a visible terminal state instead of staying busy',
    () async {
      final api = SearchApi()
        ..respond = (_, _) async =>
            throw const WaveException('Offline', 'OFFLINE', 503);
      final c = await fixture(api);
      try {
        await c.search('unavailable');
        expect(c.searchLoading, false);
        expect(c.searchError, 'Offline');
        expect(c.results, isEmpty);
      } finally {
        await release(c);
      }
    },
  );

  test(
    'Fresh metadata cache presents immediately and keeps provider keys separate',
    () async {
      final api = SearchApi()
        ..respond = (_, _) async => {
          'tracks': [track('other-provider')],
        };
      api.peekMetadata(
        '/api/search',
      ); // Establish this account's metadata scope.
      api.metadata.put(
        MetadataCache.key('/api/search', {
          'q': 'cached',
          'source': 'all',
          'fast': '1',
        }),
        {
          'tracks': [track('cached')],
        },
      );
      final c = await fixture(api);
      try {
        await c.search('cached');
        expect(c.results.single.id, 'cached');
        expect(api.requests, isEmpty);
        await c.search('cached', source: 'youtube');
        expect(c.results.single.id, 'other-provider');
        expect(api.requests.single.query?['source'], 'youtube');
      } finally {
        await release(c);
      }
    },
  );

  test(
    'Clearing a query invalidates late work and clears all search-only state',
    () async {
      final old = Completer<Json>();
      final api = SearchApi()..respond = (_, _) => old.future;
      final c = await fixture(api);
      try {
        final first = c.search('old');
        await c.search('   ');
        old.complete({
          'tracks': [track('must-not-return')],
          'pendingProviders': ['youtube'],
        });
        await first;
        expect(c.results, isEmpty);
        expect(c.artistResults, isEmpty);
        expect(c.playlistResults, isEmpty);
        expect(c.searchPendingProviders, isEmpty);
        expect(c.searchProviderErrors, isEmpty);
        expect(c.searchLoading, false);
        expect(c.searchError, isNull);
      } finally {
        await release(c);
      }
    },
  );

  test(
    'Position-only playback packets do not rebuild the controller UI',
    () async {
      final api = SearchApi(), c = await fixture(api);
      try {
        await c.audio.playbackState.first;
        var notifications = 0;
        void changed() => notifications++;
        c.addListener(changed);
        Future<void> emit(PlaybackState state) async {
          final observed = c.audio.playbackState.firstWhere(
            (value) => identical(value, state),
          );
          c.audio.playbackState.add(state);
          await observed;
        }

        await emit(
          PlaybackState(
            processingState: AudioProcessingState.ready,
            playing: true,
          ),
        );
        final playingNotifications = notifications;
        expect(playingNotifications, greaterThan(0));
        final lastPacket = PlaybackState(
          processingState: AudioProcessingState.ready,
          playing: true,
          updatePosition: const Duration(milliseconds: 120 * 16),
          bufferedPosition: const Duration(milliseconds: 120 * 16 + 1000),
        );
        final packetsDelivered = c.audio.playbackState.firstWhere(
          (value) => identical(value, lastPacket),
        );
        for (var frame = 1; frame <= 120; frame++) {
          c.audio.playbackState.add(
            frame == 120
                ? lastPacket
                : PlaybackState(
                    processingState: AudioProcessingState.ready,
                    playing: true,
                    updatePosition: Duration(milliseconds: frame * 16),
                    bufferedPosition: Duration(milliseconds: frame * 16 + 1000),
                  ),
          );
        }
        await packetsDelivered;
        expect(
          notifications,
          playingNotifications,
          reason:
              'Time and buffering packets must stay outside the app rebuild path',
        );
        await emit(
          PlaybackState(
            processingState: AudioProcessingState.ready,
            playing: false,
          ),
        );
        expect(
          notifications,
          playingNotifications + 1,
          reason: 'Pause is a real visible state change',
        );
        await emit(
          PlaybackState(
            processingState: AudioProcessingState.loading,
            playing: false,
          ),
        );
        expect(
          notifications,
          playingNotifications + 2,
          reason: 'Loading controls and status must still update',
        );
        await emit(
          PlaybackState(
            processingState: AudioProcessingState.ready,
            playing: false,
            repeatMode: AudioServiceRepeatMode.one,
            shuffleMode: AudioServiceShuffleMode.all,
          ),
        );
        expect(
          notifications,
          playingNotifications + 3,
          reason:
              'Repeat and shuffle must not disappear with progress isolation',
        );
        c.removeListener(changed);
      } finally {
        await release(c);
      }
    },
  );
}
