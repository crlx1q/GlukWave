import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/core/library_mutations.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/ui/playlist_manager.dart';
import 'package:glukwave/ui/widgets.dart';
import 'package:glukwave/l10n/wave_localizations.dart';
import 'app_layout_test.dart' as layout;
import 'audio_design_test.dart' as audio;
import 'helpers/fonts.dart';
import 'helpers/artwork_fixture.dart';

Json initial() => {
  'tracks': [
    {
      'id': 'sc:track/1',
      'title': 'Там, где тихо',
      'artist': 'Wave',
      'artwork': 'https://qa.invalid/coast.jpg',
      'duration': 180,
      'source': 'local',
    },
  ],
  'likedIds': <String>[],
  'playlists': [
    {
      'id': 'p/one',
      'name': 'Тихий вечер',
      'description': 'Свои моменты',
      'public': false,
      'trackIds': <String>[],
    },
  ],
  'history': [],
};

class PendingApi extends WaveApi {
  final calls = <Json>[];
  final writes = <Completer<Json>>[];
  Completer<Json>? reading;
  PendingApi() : super('http://127.0.0.1:4000') {
    token = 'owner-token';
  }
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    calls.add({'path': path, 'method': method, 'data': data});
    if (path == '/api/library') return reading?.future ?? initial();
    if (method != 'GET') {
      final pending = Completer<Json>();
      writes.add(pending);
      return pending.future;
    }
    if (path == '/api/auth/me') {
      return {
        'user': {'id': 'owner', 'plan': 'beta'},
      };
    }
    return {};
  }
}

class TempCache extends MusicCache {
  final Directory root;
  TempCache(super.api, this.root, {bool persist = true})
    : super(
        supportDirectory: () async {
          if (!persist) {
            throw const FileSystemException(
              'Isolated UI fixture has no disk writer',
            );
          }
          return root;
        },
      );
}

Future<layout.LayoutController> controller({bool persist = true}) async {
  SharedPreferences.setMockInitialValues({});
  final api = PendingApi(),
      cache = TempCache(
        api,
        await Directory.systemTemp.createTemp('wave-playlist-'),
        persist: persist,
      ),
      out = audio.UiAudio(api, cache),
      c = layout.LayoutController(api, cache, out);
  c.preferences = await SharedPreferences.getInstance();
  await c.restoreCustomizationScope();
  await c.customize({'language': 'ru', 'reducedMotion': true});
  c.user = WaveUser({'id': 'owner', 'plan': 'beta'});
  c.online = true;
  c.loading = false;
  c.tracks = objects(initial()['tracks']).map(WaveTrack.new).toList();
  c.playlists = objects(initial()['playlists']);
  return c;
}

Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 20));
Future<void> dispose(layout.LayoutController c) async {
  c.user = null;
  c.dispose();
  await c.audio.release();
  c.api.dio.close(force: true);
  await tick();
  final root = (c.cache as TempCache).root;
  for (var retry = 0; retry < 10; retry++) {
    try {
      await root.delete(recursive: true);
      break;
    } on FileSystemException {
      if (retry == 9) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

Widget shell(
  layout.LayoutController c,
  Widget child, {
  String mode = 'dark',
  double scale = 1.25,
}) => RepaintBoundary(
  key: const Key('capture'),
  child: MaterialApp(
    theme: buildWaveTheme(
      c.customization.merge({'theme': mode}),
      mode == 'light' ? Brightness.light : Brightness.dark,
      coverAccent: const Color(0xffad795d),
    ),
    locale: const Locale('ru'),
    supportedLocales: WaveStrings.supportedLocales,
    localizationsDelegates: WaveStrings.delegates,
    builder: (context, page) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
      child: page!,
    ),
    home: Scaffold(body: child),
  ),
);

Finder action(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    )
    .last;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
    await loadAppFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test(
    'Journal preserves canonical other-device membership and cover against stale snapshot',
    () {
      final j = LibraryMutations(initial()),
          began = j.revision,
          e = j.begin('playlist:p/one', 'membership', 'p/one', {
            'trackId': 'sc:track/1',
            'present': true,
          });
      j.base['playlists'].add({
        'id': 'other-list',
        'name': 'Keep order',
        'trackIds': [],
      });
      j.acknowledge(
        e,
        playlist: {
          ...objects(initial()['playlists']).first,
          'trackIds': ['other-device', 'sc:track/1'],
          'artwork': 'cover.jpg',
        },
      );
      expect(objects(j.base['playlists']).map((p) => p['id']), [
        'p/one',
        'other-list',
      ]);
      j.acceptSnapshot(initial(), began);
      expect(objects(j.visible['playlists']).first['trackIds'], [
        'other-device',
        'sc:track/1',
      ]);
      expect(objects(j.visible['playlists']).first['artwork'], 'cover.jpg');
      final read = j.revision;
      j.acceptPlaylist({
        ...objects(j.visible['playlists']).first,
        'artwork': 'new.jpg',
      });
      j.acceptSnapshot(initial(), read);
      expect(objects(j.visible['playlists']).first['artwork'], 'new.jpg');
    },
  );
  test(
    'Cover acknowledgement preserves newer edits and cannot resurrect a deleted playlist',
    () {
      final j = LibraryMutations(initial()),
          edit = j.begin('playlist:p/one', 'update', 'p/one', {
            'name': 'New name',
          });
      j.acknowledge(
        edit,
        playlist: {
          'id': 'p/one',
          'name': 'New name',
          'trackIds': ['new-track'],
        },
      );
      j.acceptPlaylist({
        'id': 'p/one',
        'name': 'Old name',
        'trackIds': [],
        'artwork': 'cover.jpg',
      });
      expect(objects(j.base['playlists']).first['name'], 'New name');
      expect(objects(j.base['playlists']).first['trackIds'], ['new-track']);
      final remove = j.begin('playlist:p/one', 'delete', 'p/one', {});
      j.acknowledge(remove);
      j.acceptPlaylist({
        'id': 'p/one',
        'name': 'Old name',
        'trackIds': [],
        'artwork': 'late.jpg',
      });
      expect(objects(j.base['playlists']), isEmpty);
    },
  );
  test(
    'Journal failed edit retains later intent and pending refresh overlay; cache is confirmed',
    () {
      final j = LibraryMutations(initial()),
          first = j.begin('like:a', 'like', 'a', {'liked': true}),
          last = j.begin('like:a', 'like', 'a', {'liked': false});
      j.reject(first);
      j.acceptSnapshot(initial(), j.revision);
      expect(j.visible['likedIds'], isEmpty);
      expect(j.saving, ['like:a']);
      j.acknowledge(last);
      expect(j.base['likedIds'], isEmpty);
      final create = j.begin('create:pending:x', 'create', 'pending:x', {
        'playlist': {'id': 'pending:x', 'name': 'Draft', 'trackIds': []},
      });
      expect(objects(j.visible['playlists']).length, 2);
      expect(objects(j.base['playlists']).length, 1);
      j.reject(create);
    },
  );
  test(
    'Controller likes notify immediately, serialize final intent and rollback only failed request',
    () async {
      final c = await controller(),
          api = c.api as PendingApi,
          t = c.tracks.first;
      var notifications = 0;
      c.addListener(() => notifications++);
      final first = c.like(t);
      final handled = expectLater(first, throwsStateError);
      expect(c.likedIds, [t.id]);
      expect(notifications, greaterThan(0));
      final second = c.like(t);
      expect(c.likedIds, isEmpty);
      await tick();
      expect(api.writes.length, 1);
      api.writes.first.completeError(StateError('isolated outage'));
      await handled;
      await tick();
      expect(api.writes.length, 2);
      expect(api.calls.map((r) => object(r['data'])['liked']), [true, false]);
      api.writes.last.complete({});
      await second;
      expect(c.likedIds, isEmpty);
      expect(c.librarySaving, isEmpty);
      expect(api.calls.every((r) => r['method'] == 'PUT'), true);
      await dispose(c);
    },
  );
  test(
    'Controller independent entity writes do not queue a like behind a slow playlist',
    () async {
      final c = await controller(), api = c.api as PendingApi;
      final playlist = c.updatePlaylist('p/one', {'name': 'Slow playlist'}),
          like = c.like(c.tracks.first);
      await tick();
      expect(api.writes.length, 2);
      api.writes[1].complete({});
      await like;
      expect(c.librarySaving, ['playlist:p/one']);
      api.writes[0].complete({
        'playlist': {...c.playlists.first, 'name': 'Slow playlist'},
      });
      await playlist;
      await dispose(c);
    },
  );
  test(
    'Controller membership uses atomic encoded PUT, retains pending during refresh and persists confirmed only',
    () async {
      final c = await controller(),
          api = c.api as PendingApi,
          t = c.tracks.first;
      final write = c.setPlaylistTrack('p/one', t, true);
      expect(c.playlistsForTrack(t.id).length, 1);
      await tick();
      expect(
        api.calls.first['path'],
        '/api/playlists/p%2Fone/tracks/sc%3Atrack%2F1',
      );
      await c.refreshLibrary();
      expect(c.playlistsForTrack(t.id).length, 1);
      await tick();
      final cache = (c.cache as TempCache),
          files = cache.root.listSync().whereType<File>().where(
            (f) => f.path.endsWith('.json'),
          );
      expect(files, isNotEmpty);
      final disk = object(jsonDecode(files.first.readAsStringSync()));
      expect(objects(disk['playlists']).first['trackIds'], isEmpty);
      api.writes.first.complete({
        'playlist': {
          ...c.playlists.first,
          'trackIds': ['other-device', t.id],
        },
      });
      await write;
      await tick();
      expect(c.playlists.first['trackIds'], ['other-device', t.id]);
      expect(
        api.calls.where((r) => r['method'] == 'GET').map((r) => r['path']),
        ['/api/library'],
      );
      await dispose(c);
    },
  );
  test(
    'Controller create draft settles once; rejected create rolls back and stale account reply is ignored',
    () async {
      final c = await controller(), api = c.api as PendingApi;
      final create = c.createPlaylist('On my way');
      final failed = expectLater(create, throwsStateError);
      expect(c.playlists.last['id'], startsWith('pending:'));
      await tick();
      api.writes.first.completeError(StateError('isolated outage'));
      await failed;
      expect(c.playlists.length, 1);
      final retry = c.createPlaylist('On my way');
      expect(c.playlists.length, 2);
      await tick();
      api.writes.last.complete({
        'playlist': {'id': 'saved', 'name': 'On my way', 'trackIds': []},
      });
      await retry;
      expect(c.playlists.last['id'], 'saved');
      final delayed = c.updatePlaylist('saved', {'name': 'Old account'});
      final scoped = expectLater(delayed, throwsStateError);
      await tick();
      api.token = 'next-token';
      c.user = WaveUser({'id': 'next-owner', 'plan': 'beta'});
      c.playlists = [];
      api.writes.last.complete({
        'playlist': {'id': 'saved', 'name': 'Old account', 'trackIds': []},
      });
      await scoped;
      expect(c.playlists, isEmpty);
      expect(c.librarySaving, isEmpty);
      await dispose(c);
    },
  );
  test(
    'Create from a non-library search track seeds playable metadata before and after acknowledgement',
    () async {
      final c = await controller(),
          api = c.api as PendingApi,
          track = WaveTrack({
            'id': 'soundcloud:search',
            'title': 'Search result',
            'artist': 'New artist',
            'artwork': 'https://qa.invalid/coast.jpg',
            'source': 'soundcloud',
            'sourceUrl': 'https://soundcloud.com/fixture/result',
            'duration': 214,
          });
      expect(c.track(track.id), isNull);
      final create = c.createPlaylist(
        'From search',
        ids: [track.id],
        knownTracks: [track],
      );
      expect(c.track(track.id)?.playable, true);
      await tick();
      expect(object(api.calls.first['data']).containsKey('knownTracks'), false);
      api.writes.first.complete({
        'playlist': {
          'id': 'from-search',
          'name': 'From search',
          'trackIds': [track.id],
        },
      });
      await create;
      expect(c.track(track.id)?.sourceUrl, track.sourceUrl);
      expect(c.track(track.id)?.playable, true);
      expect(api.calls.length, 1);
      await dispose(c);
    },
  );
  test(
    'Controller ignores GET begun before canonical membership ack in both refresh paths',
    () async {
      for (final full in [false, true]) {
        final c = await controller(), api = c.api as PendingApi;
        api.reading = Completer<Json>();
        final reading = full ? c.refresh() : c.refreshLibrary();
        await tick();
        final write = c.setPlaylistTrack('p/one', c.tracks.first, true);
        await tick();
        api.writes.first.complete({
          'playlist': {
            ...c.playlists.first,
            'trackIds': ['other-device', c.tracks.first.id],
          },
        });
        await write;
        api.reading!.complete(initial());
        await reading;
        expect(c.playlists.first['trackIds'], [
          'other-device',
          c.tracks.first.id,
        ]);
        await dispose(c);
      }
    },
  );
  for (final width in [320.0, 375.0, 1280.0]) {
    testWidgets(
      'Playlist picker, optimistic draft and failure keep inputs and fit $width',
      (tester) async {
        final c = (await tester.runAsync(() => controller(persist: false)))!,
            api = c.api as PendingApi;
        await tester.runAsync(installArtworkFixture);
        await layout.viewport(tester, Size(width, 850));
        await tester.pumpWidget(
          shell(
            c,
            PlaylistMembershipDialog(controller: c, track: c.tracks.first),
            mode: width == 375 ? 'light' : 'dark',
            scale: 1.25,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.byKey(const ValueKey('playlist-membership-p/one')),
        );
        await tester.pump();
        expect(c.playlistsForTrack(c.tracks.first.id).length, 1);
        await tester.runAsync(tick);
        api.writes.first.complete({'playlist': c.playlists.first});
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('playlist-new-name')),
          'После дождя',
        );
        await tester.pump();
        await tester.ensureVisible(action('Новый плейлист'));
        await tester.tap(action('Новый плейлист'));
        await tester.pump();
        expect(find.text('Сохраняем…'), findsWidgets);
        expect(c.playlists.last['id'], startsWith('pending:'));
        await tester.runAsync(tick);
        expect(api.writes.length, 2);
        api.writes.last.completeError(
          const WaveException('Не удалось сохранить. Попробуй ещё раз.'),
        );
        await tester.pumpAndSettle();
        expect(find.text('После дождя'), findsOneWidget);
        expect(find.text('Повторить'), findsOneWidget);
        expect(c.playlists.length, 1);
        expect(tester.takeException(), isNull);
        await layout.screenshot(tester, 'playlist22-picker-${width.toInt()}');
        await tester.pumpWidget(const SizedBox());
        clearArtworkFixture();
        await tester.runAsync(() => dispose(c));
        await tester.binding.setSurfaceSize(null);
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      },
    );
  }
  testWidgets(
    'Playlist editor keeps delete confirmation mounted through optimistic rollback',
    (tester) async {
      final c = (await tester.runAsync(() => controller(persist: false)))!,
          api = c.api as PendingApi;
      await layout.viewport(tester, const Size(375, 850));
      await tester.pumpWidget(
        shell(
          c,
          PlaylistEditDialog(controller: c, playlist: c.playlists.first),
          mode: 'light',
          scale: 1.25,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(action('Удалить плейлист'));
      await tester.tap(action('Удалить плейлист'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(action('Удалить плейлист'));
      await tester.tap(action('Удалить плейлист'));
      await tester.pump();
      expect(c.playlists, isEmpty);
      expect(
        find.textContaining('Аудиофайлы не будут удалены'),
        findsOneWidget,
      );
      await tester.runAsync(tick);
      api.writes.first.completeError(
        const WaveException('Не удалось удалить. Попробуй ещё раз.'),
      );
      await tester.pumpAndSettle();
      expect(c.playlists.length, 1);
      expect(find.text('Повторить'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await layout.screenshot(tester, 'playlist22-delete-rollback');
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => dispose(c));
      await tester.binding.setSurfaceSize(null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
