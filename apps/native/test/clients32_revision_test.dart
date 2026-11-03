// Regression journeys for the independent Clients32 design corrections.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/ui/client32_design.dart';
import 'package:glukwave/ui/client32_workspace.dart';
import 'package:glukwave/ui/discovery.dart';
import 'package:glukwave/ui/parity_panels.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/public_import_strings.dart';
import 'package:glukwave/ui/source_mark.dart';
import 'package:glukwave/ui/widgets.dart';
import 'app_layout_test.dart' as f;
import 'clients32_content_test.dart' as content;
import 'clients32_shell_test.dart' as shell;

Future<void> tapKey(WidgetTester t, String key) async {
  final target = find.byKey(Key(key));
  if (target.evaluate().isEmpty) {
    final sidebar = find.byKey(const Key('desktop-navigation-sidebar'));
    final discovery = find.byKey(const Key('discovery-scroll'));
    final root = key.startsWith('nav-') && sidebar.evaluate().isNotEmpty
        ? sidebar
        : discovery.evaluate().isNotEmpty
        ? discovery
        : find.byType(ClientScrollPage);
    final scroll = find
        .descendant(of: root, matching: find.byType(Scrollable))
        .first;
    await t.scrollUntilVisible(target, 180, scrollable: scroll);
  }
  await Scrollable.ensureVisible(t.element(target), alignment: .5);
  await t.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await t.tap(target);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(shell.prepareClient32Fonts);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets(
    'phone artist, album and public playlist retain one controllable mini and Back',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final c = (await t.runAsync(content.fixture))!;
      (c.api as content.ContentApi).catalogue.removeRange(6, 1000);
      c.playlists = [
        {
          'id': 'content-public',
          'name': 'After hours',
          'public': true,
          'trackIds': c.tracks.take(6).map((track) => track.id).toList(),
        },
      ];
      c.audio.current = c.tracks.first;
      c.audio.tracks = c.tracks.take(2).toList();
      final current = c.audio.current;
      final queue = c.audio.tracks;
      try {
        await shell.pumpClient32(t, c, const Size(375, 812));
        await tapKey(t, 'nav-search');
        await tapKey(t, 'search-artist-qa-artist');
        expect(find.byType(ArtistDetail), findsOneWidget);
        void transport() {
          final mini = find.byType(MiniPlayer).hitTestable();
          expect(mini, findsOneWidget);
          expect(
            find.byKey(const Key('mini-next')).hitTestable(),
            findsOneWidget,
          );
          expect(
            t.widget<IconButton>(find.byKey(const Key('mini-next'))).onPressed,
            isNotNull,
          );
          expect(c.audio.current, same(current));
          expect(c.audio.tracks, same(queue));
        }

        transport();
        final scroll = find
            .descendant(
              of: find.byType(ArtistDetail),
              matching: find.byType(Scrollable),
            )
            .first;
        final position = t.state<ScrollableState>(scroll).position;
        position.jumpTo(position.maxScrollExtent);
        await t.pumpAndSettle();
        await tapKey(t, 'artist-album-moments');
        expect(find.byType(AlbumDetailContent), findsOneWidget);
        transport();
        await t.tap(find.byKey(const Key('album-play-all')));
        await t.pumpAndSettle();
        expect(c.playedQueue?.length, 6);
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.byType(ArtistDetail), findsOneWidget);
        transport();
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        await tapKey(t, 'search-playlist-content-public');
        expect(find.byType(DiscoveryPlaylistContent), findsOneWidget);
        transport();
        await shell.captureClient32(t, 'revision-phone-public-playlist-375');
        await t.tap(find.byKey(const Key('mini-gesture')));
        await t.pumpAndSettle();
        expect(
          find.byKey(const Key('full-player')).hitTestable(),
          findsOneWidget,
        );
        expect(c.audio.current, same(current));
        expect(c.audio.tracks, same(queue));
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.byKey(const Key('full-player')), findsNothing);
        expect(find.byType(DiscoveryPlaylistContent), findsOneWidget);
        transport();
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.byType(ClientDetailPage), findsNothing);
        expect(find.byKey(const Key('discovery-scroll')), findsOneWidget);
        transport();
        expect(t.takeException(), isNull);
      } finally {
        await f.clean(t, c);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  for (final spec in [
    (375.0, 812.0, TargetPlatform.android, 18.0),
    (768.0, 1024.0, TargetPlatform.android, 18.0),
    (1440.0, 900.0, TargetPlatform.windows, 30.0),
  ]) {
    testWidgets('Search and Saved share responsive gutters at ${spec.$1}', (
      t,
    ) async {
      debugDefaultTargetPlatformOverride = spec.$3;
      final c = await shell.client32Fixture(t);
      try {
        await shell.pumpClient32(t, c, Size(spec.$1, spec.$2));
        for (final page in ['search', 'downloads']) {
          await f.navigateShell(t, page);
          final viewport = find.byKey(
            Key(page == 'search' ? 'discovery-scroll' : 'saved-view'),
          );
          final heading = find
              .descendant(of: viewport, matching: find.byType(PageHeading))
              .first;
          expect(
            t.getRect(heading).left - t.getRect(viewport).left,
            closeTo(spec.$4, .1),
          );
          expect(
            t.getRect(viewport).right - t.getRect(heading).right,
            closeTo(spec.$4, .1),
          );
          expect(t.takeException(), isNull);
        }
      } finally {
        await f.clean(t, c);
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  for (final theme in ['light', 'dark', 'amoled']) {
    testWidgets(
      'filled room and profile actions have contrasting glyphs in $theme',
      (t) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final c = await shell.client32Fixture(t);
        c.connected = true;
        c.room = {
          'id': 'revision-room',
          'name': 'Quiet room',
          'ownerId': c.user!.id,
          'members': <Map<String, dynamic>>[],
        };
        try {
          await t.runAsync(() => c.customize({'theme': theme}));
          await shell.pumpClient32(t, c, const Size(390, 844));
          await tapKey(t, 'pinned-room');
          void contrast(String key) {
            final button = find.byKey(Key(key));
            final icon = find.descendant(
              of: button,
              matching: find.byType(Icon),
            );
            final foreground =
                t.widget<Icon>(icon).color ??
                IconTheme.of(t.element(icon)).color!;
            final background = t
                .widget<IconButton>(button)
                .style!
                .backgroundColor!
                .resolve({})!;
            final luminance = [
              foreground.computeLuminance(),
              background.computeLuminance(),
            ]..sort();
            expect(
              (luminance.last + .05) / (luminance.first + .05),
              greaterThanOrEqualTo(3),
            );
          }

          contrast('room-chat-send');
          await tapKey(t, 'nav-profile');
          contrast('profile-banner-action');
          await shell.captureClient32(t, 'revision-profile-action-$theme-390');
          expect(t.takeException(), isNull);
        } finally {
          await f.clean(t, c);
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }

  testWidgets(
    'unconfigured sources retain public import without claiming connection',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final c = await shell.client32Fixture(t);
      try {
        await shell.pumpClient32(t, c, const Size(1440, 900));
        await f.navigateShell(t, 'sources');
        final spotify = find.byKey(const Key('source-row-spotify'));
        await t.ensureVisible(spotify);
        await t.pumpAndSettle();
        expect(
          find.descendant(of: spotify, matching: find.byType(SourceMark)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: spotify,
            matching: find.byIcon(Icons.multitrack_audio_rounded),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: spotify,
            matching: find.text(
              publicImportText(t.element(spotify), 'connected'),
            ),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: spotify,
            matching: find.text(
              publicImportText(t.element(spotify), 'accountUnavailable'),
            ),
          ),
          findsOneWidget,
        );
        expect(
          t
              .widget<IconButton>(
                find.byKey(const Key('public-import-open-spotify')),
              )
              .onPressed,
          isNotNull,
        );
        await shell.captureClient32(t, 'revision-sources-1440');
        expect(t.takeException(), isNull);
      } finally {
        await f.clean(t, c);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
