// Isolated content fixtures only. These are never imported by product routes.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/core/parity.dart';
import 'package:glukwave/l10n/wave_localizations.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/ui/client32_workspace.dart';
import 'package:glukwave/ui/auth_page.dart';
import 'package:glukwave/ui/connect_panel.dart';
import 'package:glukwave/ui/provider_import.dart';
import 'package:glukwave/ui/discovery.dart';
import 'package:glukwave/ui/parity_panels.dart';
import 'package:glukwave/ui/playlist_manager.dart';
import 'package:glukwave/ui/widgets.dart';
import 'app_layout_test.dart' as f;
import 'helpers/fonts.dart';
import 'helpers/artwork_fixture.dart';
import 'helpers/parity_fixture.dart';

class ContentApi extends ParityApi {
  bool empty = false;
  Completer<Json>? pendingProfile;
  final publicQueries = <String>[];
  final importedBodies = <Json>[];
  bool largeImport = false;
  final catalogue = List.generate(
    1000,
    (i) => <String, dynamic>{
      ...qaTrack,
      'id': 'content-$i',
      'title': 'Quiet session ${i + 1}',
      'album': 'Collected moments',
    },
  );
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    final route = Uri.parse(path).path;
    if (super.fail) {
      return super.call(path, method: method, data: data, query: query);
    }
    if (route == '/api/public-import/search') {
      publicQueries.add(object(data)['query'].toString());
      return {
        'playlists': [
          {
            'id': 'content-source',
            'name': 'After hours',
            'sourceUrl': 'https://open.spotify.com/playlist/content-source',
            'trackCount': largeImport ? 1000 : 6,
          },
        ],
      };
    }
    if (route == '/api/public-import/tracks') {
      final page = object(data)['cursor'] == null ? 0 : 1;
      final items = largeImport
          ? catalogue.skip(page * 500).take(500)
          : catalogue.take(6);
      return {
        'tracks': items.map((t) => {...t, 'source': 'spotify'}).toList(),
        'total': largeImport ? 1000 : 6,
        if (largeImport && page == 0) 'nextCursor': 'page2',
      };
    }
    if (method == 'POST' && route.endsWith('/import')) {
      importedBodies.add(object(data));
      return {
        'imported': (object(data)['trackIds'] as List? ?? const []).length,
      };
    }
    if (route.startsWith('/api/artists/')) {
      return {
        'artist': {
          ...qaArtist,
          'bio':
              'Independent catalogue metadata in an isolated visual fixture.',
        },
        'tracks': empty ? <Json>[] : catalogue,
        'albums': empty
            ? <Json>[]
            : [
                {
                  'id': 'moments',
                  'name': 'Collected moments',
                  'trackIds': catalogue.take(6).map((t) => t['id']).toList(),
                },
              ],
      };
    }
    if (route.startsWith('/api/profile/') && pendingProfile != null) {
      return pendingProfile!.future;
    }
    if (route == '/api/search') {
      return {
        'tracks': empty ? <Json>[] : catalogue.take(6).toList(),
        'artists': empty ? <Json>[] : [qaArtist],
      };
    }
    if (route.startsWith('/api/profile/')) {
      return {
        'user': {
          'id': 'content-listener',
          'displayName': 'Quiet listener',
          'username': 'quiet_listener',
          'bio': 'Music for unhurried evenings.',
          'plan': 'beta',
        },
        'stats': {'plays': 24, 'listeningSeconds': 3600, 'artistCount': 4},
        'playlists': [
          {
            'id': 'content-public',
            'name': 'After hours',
            'description': 'An isolated QA collection.',
            'trackIds': catalogue.take(6).map((t) => t['id']).toList(),
          },
        ],
      };
    }
    if (route == '/api/playlists/discover') {
      return {
        'playlists': [
          {
            'id': 'content-public',
            'name': 'After hours',
            'description': 'An isolated QA collection.',
          },
        ],
      };
    }
    if (route.startsWith('/api/playlists/')) {
      return {
        'playlist': {
          'id': 'content-public',
          'name': 'After hours',
          'description': 'An isolated QA collection.',
        },
        'tracks': empty ? <Json>[] : catalogue.take(6).toList(),
      };
    }
    return super.call(path, method: method, data: data, query: query);
  }
}

class ContentController extends ParityController {
  WaveTrack? played, liked;
  List<WaveTrack>? playedQueue;
  ContentController(super.api, super.cache, super.audio);
  @override
  Future<void> play(
    WaveTrack target, {
    List<WaveTrack>? list,
    bool preserveWave = false,
  }) async {
    played = target;
    playedQueue = list;
  }

  @override
  Future<void> like(WaveTrack track) async {
    liked = track;
  }
}

Future<ContentController> fixture() async {
  SharedPreferences.setMockInitialValues({});
  final api = ContentApi(), cache = MusicCache(api);
  final c = ContentController(api, cache, WaveAudioHandler(api, cache));
  c.preferences = await SharedPreferences.getInstance();
  await c.restoreCustomizationScope();
  await c.customize({'reducedMotion': true, 'language': 'en'});
  c.loading = false;
  c.online = true;
  c.user = WaveUser({
    'id': 'content-owner',
    'username': 'listener',
    'displayName': 'Listener',
    'plan': 'beta',
  });
  c.results = api.catalogue.map(WaveTrack.new).toList();
  c.tracks = c.results;
  return c;
}

Widget app(f.LayoutController c, Widget child, {double scale = 1}) =>
    RepaintBoundary(
      key: const Key('capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        supportedLocales: WaveStrings.supportedLocales,
        localizationsDelegates: WaveStrings.delegates,
        theme: buildWaveTheme(
          c.customization,
          c.customization.theme == 'light' ? Brightness.light : Brightness.dark,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: child),
      ),
    );

DiscoveryView results(
  ContentController c, {
  ValueChanged<String>? onType,
  ValueChanged<String>? onSource,
  ValueChanged<String>? onQuery,
  String query = 'Quiet',
  String type = 'tracks',
}) => DiscoveryView(
  controller: c,
  query: query,
  type: type,
  source: 'all',
  loading: false,
  scrollable: true,
  header: const Padding(
    padding: EdgeInsets.only(bottom: 24),
    child: PageHeading(
      'Find your next favourite',
      'Artists, collections and music for your mood.',
      eyebrow: 'SEARCH',
    ),
  ),
  onType: onType ?? (_) {},
  onSource: onSource ?? (_) {},
  onQuery: onQuery ?? (_) {},
  onPlaylist: (_) {},
  onMore: (_) {},
);

Future<void> mount(
  WidgetTester t,
  f.LayoutController c,
  Widget child,
  Size size, {
  double scale = 1,
}) async {
  await f.viewport(t, size);
  await t.pumpWidget(app(c, child, scale: scale));
  await t.pumpAndSettle();
}

Future<void> clean(WidgetTester t, f.LayoutController c) async {
  clearArtworkFixture();
  await f.clean(t, c);
}

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

  setUp(installArtworkFixture);
  tearDown(clearArtworkFixture);

  testWidgets(
    'Bounded search creates visible tracks lazily and plays with the complete result queue',
    (t) async {
      final c = (await t.runAsync(fixture))!;
      await mount(t, c, results(c), const Size(1280, 800));
      expect(find.byType(TrackRow).evaluate().length, lessThan(25));
      expect(find.text('Quiet session 1000'), findsNothing);
      await t.tap(find.text('Quiet session 1'));
      await t.pump();
      expect(c.played?.id, 'content-0');
      expect(c.playedQueue?.length, 1000);
      final scroll = find.byKey(const Key('discovery-scroll'));
      await t.drag(scroll, const Offset(0, -850));
      await t.pumpAndSettle();
      final state = t.state<ScrollableState>(
        find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
      );
      state.position.jumpTo(state.position.maxScrollExtent);
      await t.pumpAndSettle();
      expect(find.text('Quiet session 1000'), findsOneWidget);
      expect(find.byType(TrackRow).evaluate().length, lessThan(25));
      expect(t.takeException(), isNull);
      await clean(t, c);
    },
  );

  testWidgets(
    'Discovery genre, type and source controls dispatch their real callbacks',
    (t) async {
      final c = (await t.runAsync(fixture))!;
      String? type, source, genre;
      await mount(
        t,
        c,
        results(
          c,
          query: '',
          type: 'all',
          onType: (v) => type = v,
          onSource: (v) => source = v,
          onQuery: (v) => genre = v,
        ),
        const Size(390, 844),
      );
      await t.tap(find.byKey(const Key('search-type-artists')));
      expect(type, 'artists');
      await t.tap(find.byKey(const Key('browse-category-Ambient')));
      expect(genre, 'Ambient');
      await t.tap(find.byKey(const Key('search-source-menu')));
      await t.pumpAndSettle();
      await t.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is CheckedPopupMenuItem<String> &&
              widget.value == 'soundcloud',
        ),
      );
      await t.pumpAndSettle();
      expect(source, 'soundcloud');
      expect(t.takeException(), isNull);
      await clean(t, c);
    },
  );

  testWidgets(
    'Artist play and album context use complete real metadata queues',
    (t) async {
      final c = (await t.runAsync(fixture))!;
      await mount(
        t,
        c,
        ArtistDetail(controller: c, artist: qaArtist, embedded: true),
        const Size(1280, 900),
      );
      await t.tap(find.byKey(const Key('artist-play-all')));
      await t.pump();
      expect(c.playedQueue?.length, 1000);
      expect(find.byType(TrackRow).evaluate().length, lessThan(25));
      final tracks = (c.api as ContentApi).catalogue
          .take(6)
          .map(WaveTrack.new)
          .toList();
      await t.pumpWidget(
        app(
          c,
          AlbumDetailContent(
            controller: c,
            album: {'id': 'moments', 'name': 'Collected moments'},
            artist: qaArtist,
            tracks: tracks,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('album-play-all')));
      await t.pump();
      expect(c.playedQueue?.map((t) => t.id), tracks.map((t) => t.id));
      expect(t.takeException(), isNull);
      await clean(t, c);
    },
  );

  testWidgets(
    'Public profile playlists navigate inside the persistent desktop workspace',
    (t) async {
      final c = (await t.runAsync(fixture))!,
          workspace = ClientWorkspaceController();
      await mount(
        t,
        c,
        ClientWorkspaceScope(
          controller: workspace,
          child: Column(
            children: [
              Expanded(
                child: ClientWorkspace(
                  controller: workspace,
                  child: PublicProfileContent(
                    controller: c,
                    user: {'id': 'content-listener'},
                  ),
                ),
              ),
              const SizedBox(
                key: Key('retained-dock'),
                height: 104,
                child: Center(child: Text('Persistent playback fixture')),
              ),
            ],
          ),
        ),
        const Size(1280, 900),
      );
      await t.tap(find.byKey(const Key('profile-playlist-content-public')));
      await t.pumpAndSettle();
      expect(workspace.canGoBack, isTrue);
      expect(find.byKey(const Key('retained-dock')), findsOneWidget);
      await t.tap(find.byKey(const Key('public-playlist-play')));
      await t.pump();
      expect(c.playedQueue?.length, 6);
      workspace.back();
      await t.pumpAndSettle();
      expect(
        find.byKey(const Key('public-profile-content-listener')),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await clean(t, c);
      workspace.dispose();
    },
  );

  testWidgets(
    'Public discovery playlist rows use the workspace detail body and complete queue',
    (t) async {
      final c = (await t.runAsync(fixture))!,
          workspace = ClientWorkspaceController();
      await mount(
        t,
        c,
        ClientWorkspaceScope(
          controller: workspace,
          child: Column(
            children: [
              Expanded(
                child: ClientWorkspace(
                  controller: workspace,
                  child: SingleChildScrollView(
                    child: PublicPlaylists(controller: c),
                  ),
                ),
              ),
              const SizedBox(
                key: Key('retained-dock'),
                height: 104,
                child: Center(child: Text('Persistent playback fixture')),
              ),
            ],
          ),
        ),
        const Size(1280, 900),
      );
      await t.tap(
        find.byKey(const Key('discover-public-playlist-content-public')),
      );
      await t.pumpAndSettle();
      expect(workspace.canGoBack, isTrue);
      expect(find.byType(DiscoveryPlaylistContent), findsOneWidget);
      expect(find.byKey(const Key('retained-dock')), findsOneWidget);
      await t.tap(find.byKey(const Key('public-playlist-play')));
      await t.pump();
      expect(c.playedQueue?.length, 6);
      expect(t.takeException(), isNull);
      await clean(t, c);
      workspace.dispose();
    },
  );

  testWidgets(
    'Track actions keep like and playlist membership actionable on a 320 phone',
    (t) async {
      final c = (await t.runAsync(fixture))!;
      await mount(
        t,
        c,
        Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => parityTrackActions(context, c, c.results.first),
              child: const Text('Actions'),
            ),
          ),
        ),
        const Size(320, 740),
        scale: 1.25,
      );
      await t.tap(find.text('Actions'));
      await t.pumpAndSettle();
      await f.screenshot(t, 'clients32-content-actions-320-light');
      await t.tap(find.byKey(const Key('track-action-like')));
      await t.pumpAndSettle();
      expect(c.liked?.id, c.results.first.id);
      await t.tap(find.text('Actions'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('track-action-playlist')));
      await t.pumpAndSettle();
      expect(find.byType(PlaylistMembershipDialog), findsOneWidget);
      expect(t.takeException(), isNull);
      await clean(t, c);
    },
  );

  testWidgets(
    'Connect pairing and discovery dispatch real callbacks at desktop and thumb widths',
    (t) async {
      final c = (await t.runAsync(fixture))!;
      var qr = 0, scans = 0, discovers = 0;
      c.devices = [
        {
          'deviceId': 'qa-desktop',
          'name': 'Studio desktop',
          'kind': 'windows',
          'online': true,
        },
        {
          'deviceId': 'qa-phone',
          'name': 'Listening phone',
          'kind': 'android',
          'online': false,
        },
      ];
      for (final size in [
        const Size(1440, 900),
        const Size(390, 844),
        const Size(320, 640),
      ]) {
        await mount(
          t,
          c,
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConnectPanel(
              controller: c,
              showQr: () async {
                qr++;
              },
              scanQr: () async {
                scans++;
              },
              discover: () async {
                discovers++;
              },
            ),
          ),
          size,
          scale: size.width == 320 ? 1.25 : 1,
        );
        await f.screenshot(
          t,
          'clients32-content-connect-${size.width.toInt()}-light',
        );
        await t.ensureVisible(find.byKey(const Key('connect-pair-qr')));
        await t.tap(find.byKey(const Key('connect-pair-qr')));
        await t.pump();
        await t.ensureVisible(find.byKey(const Key('connect-discover')));
        await t.tap(find.byKey(const Key('connect-discover')));
        await t.pump();
        expect(t.takeException(), isNull);
      }
      expect(qr + scans, 3);
      expect(discovers, 3);
      await clean(t, c);
    },
  );

  testWidgets(
    'Public import preserves real source lookup and collection selection',
    (t) async {
      final c = (await t.runAsync(fixture))!;
      for (final size in [
        const Size(1440, 900),
        const Size(390, 844),
        const Size(320, 640),
      ]) {
        await mount(
          t,
          c,
          Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showProviderImport(context, c, 'spotify'),
                child: const Text('Import fixture'),
              ),
            ),
          ),
          size,
          scale: size.width == 320 ? 1.25 : 1,
        );
        await t.tap(find.text('Import fixture'));
        await t.pumpAndSettle();
        await f.screenshot(
          t,
          'clients32-content-import-${size.width.toInt()}-light',
        );
        await t.ensureVisible(find.byKey(const Key('public-import-query')));
        await t.enterText(
          find.byKey(const Key('public-import-query')),
          '@quiet',
        );
        await t.pump();
        await t.ensureVisible(find.byKey(const Key('public-import-find')));
        await t.tap(find.byKey(const Key('public-import-find')));
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.text('After hours'),
          180,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('provider-import-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await t.ensureVisible(find.text('After hours').last);
        await t.tap(find.text('After hours').last);
        await t.pumpAndSettle();
        expect(find.byKey(const Key('import-all')), findsOneWidget);
        await f.screenshot(
          t,
          'clients32-content-import-selection-${size.width.toInt()}-light',
        );
        await t.tap(find.byKey(const Key('import-close')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
      expect((c.api as ContentApi).publicQueries, [
        '@quiet',
        '@quiet',
        '@quiet',
      ]);
      await clean(t, c);
    },
  );

  testWidgets(
    'A paged thousand-track import builds lazily and retains manual selections across pages',
    (t) async {
      final c = (await t.runAsync(fixture))!, api = c.api as ContentApi;
      api.largeImport = true;
      await mount(
        t,
        c,
        Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showProviderImport(context, c, 'spotify'),
              child: const Text('Import fixture'),
            ),
          ),
        ),
        const Size(1280, 900),
      );
      await t.tap(find.text('Import fixture'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('public-import-query')), '@large');
      await t.pump();
      await t.tap(find.byKey(const Key('public-import-find')));
      await t.pumpAndSettle();
      final importScroll = find
          .descendant(
            of: find.byKey(const Key('provider-import-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await t.scrollUntilVisible(
        find.text('After hours'),
        200,
        scrollable: importScroll,
      );
      await t.tap(find.text('After hours'));
      await t.pumpAndSettle();
      expect(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is CheckboxListTile &&
                  widget.key.toString().contains('import-track-'),
            )
            .evaluate()
            .length,
        lessThan(30),
      );
      expect(find.byKey(const Key('import-track-content-499')), findsNothing);
      await t.tap(find.byKey(const Key('import-all')));
      await t.pumpAndSettle();
      final first = find.byKey(const Key('import-track-content-0'));
      expect(t.widget<CheckboxListTile>(first).value, isTrue);
      await t.tap(first);
      await t.pumpAndSettle();
      expect(t.widget<CheckboxListTile>(first).value, isFalse);
      final state = t.state<ScrollableState>(importScroll);
      state.position.jumpTo(state.position.maxScrollExtent);
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('import-load-more')));
      await t.tap(find.byKey(const Key('import-load-more')));
      await t.pumpAndSettle();
      state.position.jumpTo(0);
      await t.pumpAndSettle();
      expect(t.widget<CheckboxListTile>(first).value, isFalse);
      state.position.jumpTo(state.position.maxScrollExtent);
      await t.pumpAndSettle();
      final last = find.byKey(const Key('import-track-content-999'));
      await t.ensureVisible(last);
      expect(t.widget<CheckboxListTile>(last).value, isTrue);
      await t.tap(last);
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('import-confirm')));
      expect(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is CheckboxListTile &&
                  widget.key.toString().contains('import-track-'),
            )
            .evaluate()
            .length,
        lessThan(30),
      );
      await t.tap(find.byKey(const Key('import-confirm')));
      await t.pumpAndSettle();
      final imported = List<String>.from(api.importedBodies.single['trackIds']);
      expect(imported.length, 998);
      expect(imported, isNot(contains('content-0')));
      expect(imported, isNot(contains('content-999')));
      expect(imported, contains('content-500'));
      expect(t.takeException(), isNull);
      await clean(t, c);
    },
  );

  testWidgets(
    'Authentication and a large playlist picker compose without form or list overflow',
    (t) async {
      final c = (await t.runAsync(fixture))!;
      for (final size in [
        const Size(1440, 900),
        const Size(390, 844),
        const Size(320, 640),
      ]) {
        await mount(
          t,
          c,
          AuthPage(controller: c),
          size,
          scale: size.width == 320 ? 1.25 : 1,
        );
        expect(find.byKey(const Key('auth-email')), findsOneWidget);
        await f.screenshot(
          t,
          'clients32-content-auth-${size.width.toInt()}-light',
        );
        expect(t.takeException(), isNull);
      }
      c.playlists = List.generate(
        400,
        (i) => {
          'id': 'picker-$i',
          'name': 'Collection ${i + 1}',
          'trackIds': <String>[],
        },
      );
      await mount(
        t,
        c,
        Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () =>
                  showPlaylistMembership(context, c, c.results.first),
              child: const Text('Playlist fixture'),
            ),
          ),
        ),
        const Size(390, 844),
      );
      await t.tap(find.text('Playlist fixture'));
      await t.pumpAndSettle();
      expect(find.byType(ListTile).evaluate().length, lessThan(20));
      expect(find.text('Collection 400'), findsNothing);
      await f.screenshot(t, 'clients32-content-playlist-picker-390-light');
      expect(t.takeException(), isNull);
      await clean(t, c);
    },
  );

  testWidgets(
    'Detail loading, error and genuine empty states remain reachable',
    (t) async {
      final c = (await t.runAsync(fixture))!, api = c.api as ContentApi;
      api.pendingProfile = Completer<Json>();
      await f.viewport(t, const Size(390, 844));
      await t.pumpWidget(
        app(c, PublicProfileContent(controller: c, user: {'id': 'pending'})),
      );
      await t.pump();
      expect(find.byType(WaveLoadingList), findsOneWidget);
      await f.screenshot(t, 'clients32-content-loading-390-light');
      api.pendingProfile!.completeError(
        StateError('Isolated unavailable fixture'),
      );
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      await f.screenshot(t, 'clients32-content-error-390-light');
      api.pendingProfile = null;
      api.empty = true;
      await t.pumpWidget(
        app(
          c,
          DiscoveryPlaylistContent(controller: c, playlist: {'id': 'empty'}),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(TrackRow), findsNothing);
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byKey(const Key('public-playlist-play')), findsNothing);
      await f.screenshot(t, 'clients32-content-empty-390-light');
      expect(t.takeException(), isNull);
      await clean(t, c);
    },
  );

  testWidgets(
    'Album, genre and taste actual bodies compose at desktop and phone sizes',
    (t) async {
      final c = (await t.runAsync(fixture))!, parity = WaveParity(c.api);
      await t.runAsync(parity.load);
      for (final size in [const Size(1440, 900), const Size(390, 844)]) {
        final tracks = c.results.take(6).toList();
        for (final surface in ['album', 'genre', 'taste']) {
          final Widget content = switch (surface) {
            'album' => AlbumDetailContent(
              controller: c,
              album: {'id': 'moments', 'name': 'Collected moments'},
              artist: qaArtist,
              tracks: tracks,
            ),
            'genre' => GenreDetailContent(controller: c, genre: 'Ambient'),
            _ => TastePage(controller: c, parity: parity, embedded: true),
          };
          await mount(t, c, content, size);
          expect(t.takeException(), isNull, reason: '$surface $size');
          await f.screenshot(
            t,
            'clients32-content-$surface-${size.width.toInt()}-light',
          );
        }
      }
      await clean(t, c);
      parity.dispose();
    },
  );

  for (final spec in [
    (const Size(1440, 900), 'light', 1.0),
    (const Size(768, 900), 'dark', 1.0),
    (const Size(390, 844), 'light', 1.0),
    (const Size(375, 812), 'dark', 1.25),
    (const Size(320, 640), 'amoled', 1.25),
  ]) {
    testWidgets(
      'Actual content captures at ${spec.$1} ${spec.$2} text ${spec.$3}',
      (t) async {
        final c = (await t.runAsync(fixture))!;
        await t.runAsync(() => c.customize({'theme': spec.$2}));
        final name = '${spec.$1.width.toInt()}-${spec.$2}';
        for (final surface in [
          'browse',
          'search',
          'artist',
          'profile',
          'playlist',
        ]) {
          final Widget content = switch (surface) {
            'browse' => results(c, query: '', type: 'all'),
            'search' => results(c),
            'artist' => ArtistDetail(
              controller: c,
              artist: qaArtist,
              embedded: true,
            ),
            'profile' => PublicProfileContent(
              controller: c,
              user: {'id': 'content-listener'},
            ),
            _ => DiscoveryPlaylistContent(
              controller: c,
              playlist: {'id': 'content-public'},
            ),
          };
          await mount(t, c, content, spec.$1, scale: spec.$3);
          expect(t.takeException(), isNull, reason: '$surface $name');
          await f.screenshot(t, 'clients32-content-$surface-$name');
        }
        c.searchProviderErrors = [
          {
            'provider': 'soundcloud',
            'message': 'Isolated provider error fixture',
          },
        ];
        await mount(t, c, results(c), spec.$1, scale: spec.$3);
        await t.tap(find.byKey(const Key('search-provider-errors')));
        await t.pumpAndSettle();
        expect(find.text('Isolated provider error fixture'), findsOneWidget);
        await f.screenshot(t, 'clients32-content-partial-$name');
        expect(t.takeException(), isNull);
        await clean(t, c);
      },
    );
  }
}
