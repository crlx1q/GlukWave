import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/ui/queue_panel.dart';
import 'dart:async';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/ui/playback_progress.dart';
import 'package:glukwave/ui/player_gestures.dart';
// Actual native widgets; isolated account and muted catalogue, no owner session.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/ui/app.dart';
import 'package:glukwave/ui/client32_design.dart';
import 'package:glukwave/ui/client32_workspace.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/widgets.dart';
import 'helpers/fonts.dart';
import 'helpers/parity_fixture.dart';
import 'app_layout_test.dart' as f;

class _PulseAudio extends WaveAudioHandler {
  _PulseAudio(super.api, super.cache);
  @override
  bool get outputPlaying => true;
  @override
  bool get sourceReady => true;
  @override
  Duration get outputPosition => const Duration(seconds: 1);
  @override
  Duration? get duration => const Duration(seconds: 240);
  @override
  Stream<Duration> get positionStream => const Stream.empty();
}

Future<void> prepareClient32Fonts() async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.audio_session'),
        (_) async => null,
      );
  await loadAppFonts();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

Future<ParityController> client32Fixture(
  WidgetTester tester, {
  int tracks = 1,
}) async {
  final c = (await tester.runAsync(parityController))!;
  await tester.runAsync(
    () => c.customize({'language': 'en', 'reducedMotion': true}),
  );
  c.tracks = List.generate(
    tracks,
    (i) => WaveTrack({
      ...qaTrack,
      'id': i == 0 ? 'qa-permitted' : 'qa-track-$i',
      'title': i == 0 ? 'A quiet place' : 'Library recording $i',
    }),
  );
  c.audio.current = c.tracks.first;
  c.audio.tracks = c.tracks;
  return c;
}

Future<void> pumpClient32(
  WidgetTester tester,
  ParityController c,
  Size size,
) async {
  await f.viewport(tester, size);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('clients32-capture'),
      child: GlukWaveApp(controller: c),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> captureClient32(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        tester
                .element(find.byKey(const Key('clients32-capture')))
                .findRenderObject()!
            as RenderRepaintBoundary;
    final bitmap = await boundary.toImage(pixelRatio: 1);
    final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      '../../docs/verification/2026-11-01/clients32/after/$name.png',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    bitmap.dispose();
  });
}

Future<void> clientTap(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  if (target.evaluate().isEmpty) {
    final sidebar = find.byKey(const Key('desktop-navigation-sidebar'));
    final page = find.byType(ClientScrollPage);
    final scrollable = key.startsWith('nav-') && sidebar.evaluate().isNotEmpty
        ? find.descendant(of: sidebar, matching: find.byType(Scrollable)).first
        : page.evaluate().isNotEmpty
        ? find.descendant(of: page, matching: find.byType(Scrollable)).first
        : find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      target,
      key.startsWith('nav-') ? -160 : 240,
      scrollable: scrollable,
    );
  }
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareClient32Fonts);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets(
    'desktop details retain labelled library and one full-width dock',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final c = await client32Fixture(tester);
      await pumpClient32(tester, c, const Size(1440, 900));
      expect(
        find.byKey(const Key('desktop-navigation-sidebar')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('desktop-listening-rail')), findsOneWidget);
      final dock = tester.getRect(find.byKey(const Key('desktop-main-dock')));
      expect(dock.width, 1416);
      expect(
        tester.getCenter(find.byKey(const Key('mini-play'))).dx,
        closeTo(dock.center.dx, 1),
      );
      await clientTap(tester, 'nav-artists');
      await clientTap(tester, 'artist-qa-artist');
      expect(find.byType(ClientDetailPage), findsOneWidget);
      expect(find.byKey(const Key('desktop-main-dock')), findsOneWidget);
      expect(
        find.byKey(const Key('desktop-navigation-sidebar')),
        findsOneWidget,
      );
      expect(tester.getRect(find.byKey(const Key('desktop-main-dock'))), dock);
      await captureClient32(tester, 'desktop-artist-1440');
      await clientTap(tester, 'workspace-back');
      expect(find.byKey(const Key('artist-qa-artist')), findsOneWidget);
      await clientTap(tester, 'sidebar-playlist-qa-playlist');
      expect(find.text('Quiet hours'), findsWidgets);
      expect(
        find.byType(ClientTrackRows),
        findsNothing,
      ); // converted to lazy slivers
      await clientTap(tester, 'workspace-back');
      expect(find.byKey(const Key('artist-qa-artist')), findsOneWidget);
      await clientTap(tester, 'workspace-forward');
      expect(find.text('Quiet hours'), findsWidgets);
      expect(tester.takeException(), isNull);
      await f.clean(tester, c);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'resized Windows client keeps compact desktop rail and dock at 800',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final c = await client32Fixture(tester);
      await pumpClient32(tester, c, const Size(800, 700));
      expect(find.byKey(const Key('desktop-navigation-rail')), findsOneWidget);
      expect(find.byKey(const Key('desktop-main-dock')), findsOneWidget);
      expect(find.byKey(const Key('nav-profile')), findsNothing);
      expect(
        ClientLayout.of(tester.element(find.byType(MiniPlayer))).desktop,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await captureClient32(tester, 'desktop-compact-800');
      await f.clean(tester, c);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('large library is lazy and workspace back restores scroll', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final c = await client32Fixture(tester, tracks: 1500);
    await pumpClient32(tester, c, const Size(1280, 900));
    await clientTap(tester, 'nav-library');
    expect(find.byType(TrackRow).evaluate().length, lessThan(40));
    final scroll = find.byKey(const PageStorageKey('workspace-library:'));
    await tester.drag(scroll, const Offset(0, -1300));
    await tester.pumpAndSettle();
    final offset = tester
        .state<ScrollableState>(
          find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
        )
        .position
        .pixels;
    expect(offset, greaterThan(600));
    expect(find.byType(TrackRow).evaluate().length, lessThan(40));
    await clientTap(tester, 'nav-search');
    await clientTap(tester, 'workspace-back');
    final restored = tester
        .state<ScrollableState>(
          find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
        )
        .position
        .pixels;
    expect(restored, closeTo(offset, 1));
    expect(tester.takeException(), isNull);
    await captureClient32(tester, 'desktop-library-1280');
    await f.clean(tester, c);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'phone has four tabs, account destinations, category sheet and no volume',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final c = await client32Fixture(tester);
      await pumpClient32(tester, c, const Size(390, 844));
      for (final page in ['home', 'search', 'library', 'profile']) {
        expect(find.byKey(Key('nav-$page')), findsOneWidget);
      }
      expect(find.byKey(const Key('desktop-main-dock')), findsNothing);
      expect(tester.getSize(find.byType(MiniPlayer)).height, 60);
      expect(find.byKey(const Key('mini-next')), findsOneWidget);
      await clientTap(tester, 'nav-profile');
      await clientTap(tester, 'profile-settings');
      await clientTap(tester, 'settings-category-picker');
      await clientTap(tester, 'settings-playback');
      expect(find.byKey(const Key('settings-category-picker')), findsOneWidget);
      await captureClient32(tester, 'phone-settings-390');
      await clientTap(tester, 'mini-gesture');
      expect(find.byKey(const Key('full-player')), findsOneWidget);
      expect(find.byKey(const Key('player-volume')), findsNothing);
      expect(tester.takeException(), isNull);
      await captureClient32(tester, 'phone-player-390');
      await f.clean(tester, c);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('full-player queue keeps 1500 entries virtualized', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final c = await client32Fixture(tester, tracks: 1500);
    await f.viewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWaveTheme(c.customization, Brightness.light),
        home: Scaffold(
          body: PlayerPage(controller: c, initialTab: 2, onMore: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final queue = find.byKey(const Key('native-queue-list'));
    expect(queue, findsOneWidget);
    expect(
      find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith('queue-actions-'),
          )
          .evaluate()
          .length,
      lessThan(30),
    );
    await tester.drag(queue, const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('queue-actions-qa-track-1499')), findsNothing);
    expect(tester.takeException(), isNull);
    await f.clean(tester, c);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'queue duplicate occurrences keep their own keys through real move action',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final c = await client32Fixture(tester);
      final first = WaveTrack({...qaTrack, 'title': 'First occurrence'});
      final second = WaveTrack({...qaTrack, 'title': 'Second occurrence'});
      final other = WaveTrack({
        ...qaTrack,
        'id': 'other',
        'title': 'Other recording',
      });
      c.audio.tracks = [first, second, other];
      c.tracks = [first, second, other];
      await f.viewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaveTheme(c.customization, Brightness.light),
          home: Scaffold(
            body: QueuePanel(controller: c, onMore: (_) {}, bounded: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder row(String title) => find
          .ancestor(
            of: find.text(title),
            matching: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_QueueSettlement',
            ),
          )
          .first;
      final firstKey = tester.widget(row('First occurrence')).key;
      final secondKey = tester.widget(row('Second occurrence')).key;
      expect(firstKey, isNot(secondKey));
      final menu = tester.widget<PopupMenuButton<String>>(
        find.descendant(
          of: row('Second occurrence'),
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      menu.onSelected!('down');
      await tester.pumpAndSettle();
      expect(c.audio.viewTracks.map((t) => t.title), [
        'First occurrence',
        'Other recording',
        'Second occurrence',
      ]);
      expect(tester.widget(row('First occurrence')).key, firstKey);
      expect(tester.widget(row('Second occurrence')).key, secondKey);
      expect(tester.takeException(), isNull);
      await f.clean(tester, c);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'smooth phone progress frames retain metadata and gesture widgets',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final c = (await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final api = ParityApi();
        final cache = MusicCache(api);
        final pulse = _PulseAudio(api, cache);
        final c = ParityController(api, cache, pulse);
        c.preferences = await SharedPreferences.getInstance();
        await c.restoreCustomizationScope();
        c.loading = false;
        c.online = true;
        c.tracks = [WaveTrack(qaTrack)];
        return c;
      }))!;
      final pulse = c.audio;
      pulse.current = c.tracks.first;
      pulse.tracks = c.tracks;
      var physical = 0;
      await f.viewport(tester, const Size(390, 844));
      await tester.pumpWidget(
        ProgressTimeSource(
          milliseconds: () => physical,
          child: MaterialApp(
            theme: buildWaveTheme(c.customization, Brightness.light),
            home: Scaffold(
              body: Center(
                child: MiniPlayer(controller: c, onOpen: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final before = tester.widget(find.byType(PlayerGestureSurface));
      final start = tester
          .widget<FractionallySizedBox>(
            find.byKey(const Key('mini-card-progress')),
          )
          .widthFactor!;
      for (var frame = 0; frame < 30; frame++) {
        physical += 16;
        await tester.pump(const Duration(milliseconds: 16));
      }
      final after = tester.widget(find.byType(PlayerGestureSurface));
      final finish = tester
          .widget<FractionallySizedBox>(
            find.byKey(const Key('mini-card-progress')),
          )
          .widthFactor!;
      expect(finish, greaterThan(start));
      expect(identical(before, after), isTrue);
      expect(tester.takeException(), isNull);
      await f.clean(tester, c);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('six languages retain account settings and room navigation', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final c = await client32Fixture(tester);
    await pumpClient32(tester, c, const Size(390, 844));
    for (final language in ['ru', 'en', 'kk', 'uk', 'de', 'es']) {
      await tester.runAsync(() => c.customize({'language': language}));
      await tester.pumpAndSettle();
      await clientTap(tester, 'nav-profile');
      await clientTap(tester, 'profile-settings');
      await clientTap(tester, 'settings-category-picker');
      await clientTap(tester, 'settings-privacy');
      await clientTap(tester, 'nav-profile');
      await clientTap(tester, 'profile-rooms');
      expect(tester.takeException(), isNull, reason: language);
    }
    await f.clean(tester, c);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final roomSize in [
    const Size(1440, 900),
    const Size(390, 844),
    const Size(320, 640),
  ]) {
    testWidgets(
      'populated room $roomSize has bounded lazy chat and real permission/send actions',
      (tester) async {
        debugDefaultTargetPlatformOverride = roomSize.width >= 900
            ? TargetPlatform.windows
            : TargetPlatform.android;
        final c = await client32Fixture(tester);
        await tester.runAsync(
          () => c.customize({'fontScale': roomSize.width == 320 ? 1.25 : 1.0}),
        );
        c.connected = true;
        c.room = {
          'id': 'qa-room',
          'name': 'Quiet hours together',
          'ownerId': c.user!.id,
          'inviteCode': 'qa-invite',
          'type': 'room',
          'members': [
            {
              'userId': c.user!.id,
              'displayName': 'QA host',
              'role': 'owner',
              'online': true,
              'canControl': true,
              'devices': [
                {
                  'kind': 'android',
                  'name': 'QA phone',
                  'outputActive': true,
                  'playing': false,
                },
              ],
            },
            for (var index = 1; index < 20; index++)
              {
                'userId': 'guest-$index',
                'displayName': 'QA listener $index',
                'online': true,
                'canControl': false,
              },
          ],
        };
        c.messages = List.generate(
          1000,
          (index) => <String, dynamic>{
            'id': 'qa-message-$index',
            'userId': index.isEven ? c.user!.id : 'guest-1',
            'displayName': index.isEven ? 'QA host' : 'QA listener 1',
            'text': 'A shared listening message $index',
          },
        );
        await pumpClient32(tester, c, roomSize);
        await clientTap(tester, 'pinned-room');
        expect(find.byKey(const Key('active-room-workspace')), findsOneWidget);
        expect(find.byKey(const Key('desktop-listening-rail')), findsNothing);
        expect(
          find
              .byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    (w.key as ValueKey<String>).value.startsWith(
                      'room-message-',
                    ),
              )
              .evaluate()
              .length,
          lessThan(30),
        );
        await tester.enterText(
          find.byKey(const Key('room-chat-input')),
          'A real room callback',
        );
        await tester.pump();
        await clientTap(tester, 'room-chat-send');
        final api = c.api as ParityApi;
        expect(
          api.requests.any(
            (r) =>
                r.path == '/api/rooms/qa-room/messages' &&
                r.method == 'POST' &&
                r.data['text'] == 'A real room callback',
          ),
          isTrue,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('room-chat-input')))
              .controller!
              .text,
          isEmpty,
        );
        if (roomSize.width < 900) {
          await clientTap(tester, 'room-members-open');
        }
        await clientTap(tester, 'room-permission-guest-1');
        expect(
          api.requests.any(
            (r) =>
                r.path == '/api/rooms/qa-room/members/guest-1' &&
                r.method == 'PATCH' &&
                r.data['canControl'] == true,
          ),
          isTrue,
        );
        if (roomSize.width < 900) {
          await tester.tapAt(const Offset(5, 5));
          await tester.pumpAndSettle();
        }
        await captureClient32(tester, 'active-room-${roomSize.width.toInt()}');
        c.room!['type'] = 'jam';
        c.render();
        await tester.pumpAndSettle();
        if (roomSize.width < 900) {
          await clientTap(tester, 'room-members-open');
        }
        expect(find.byKey(const Key('room-permission-guest-1')), findsNothing);
        expect(tester.takeException(), isNull);
        await f.clean(tester, c);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets(
    'own playlist grid entry participates in workspace back history',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final c = await client32Fixture(tester);
      await pumpClient32(tester, c, const Size(1440, 900));
      await clientTap(tester, 'profile-link');
      await clientTap(tester, 'library-playlist-qa-playlist');
      expect(
        find.byKey(const Key('desktop-track-table-header')),
        findsOneWidget,
      );
      await clientTap(tester, 'workspace-back');
      expect(
        find.byKey(const PageStorageKey('workspace-profile:')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('library-playlist-qa-playlist')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('desktop-main-dock')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await f.clean(tester, c);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('room composer remains reachable above keyboard at 320', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final c = await client32Fixture(tester);
    await tester.runAsync(() => c.customize({'fontScale': 1.25}));
    c.connected = true;
    c.room = {
      'id': 'qa-keyboard',
      'name': 'Listening together',
      'ownerId': c.user!.id,
      'inviteCode': 'qa-invite',
      'members': <Json>[],
    };
    c.messages = List.generate(
      100,
      (i) => <String, dynamic>{
        'id': 'message-$i',
        'userId': c.user!.id,
        'displayName': 'QA listener',
        'text': 'A quiet conversation $i',
      },
    );
    await pumpClient32(tester, c, const Size(320, 640));
    await clientTap(tester, 'pinned-room');
    await tester.tap(find.byKey(const Key('room-chat-input')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final input = tester.getRect(find.byKey(const Key('room-chat-input')));
    final send = tester.getRect(find.byKey(const Key('room-chat-send')));
    expect(input.bottom, lessThanOrEqualTo(390));
    expect(send.bottom, lessThanOrEqualTo(390));
    expect(input.height, greaterThanOrEqualTo(44));
    await tester.enterText(
      find.byKey(const Key('room-chat-input')),
      'A keyboard message',
    );
    await clientTap(tester, 'room-chat-send');
    expect(
      (c.api as ParityApi).requests.any(
        (r) =>
            r.path == '/api/rooms/qa-keyboard/messages' &&
            r.data['text'] == 'A keyboard message',
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await captureClient32(tester, 'active-room-keyboard-320');
    tester.view.resetViewInsets();
    await f.clean(tester, c);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final width in [320.0, 375.0, 390.0]) {
    testWidgets(
      'phone $width enlarged text and short settings/actions stay reachable',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final c = await client32Fixture(tester);
        await tester.runAsync(
          () => c.customize({
            'fontScale': 1.25,
            'theme': width == 320 ? 'amoled' : 'light',
          }),
        );
        await pumpClient32(tester, c, Size(width, 640));
        await captureClient32(tester, 'phone-home-${width.toInt()}');
        await clientTap(tester, 'nav-profile');
        await clientTap(tester, 'profile-settings');
        await clientTap(tester, 'settings-category-picker');
        expect(find.byKey(const Key('settings-appearance')), findsOneWidget);
        await clientTap(tester, 'settings-appearance');
        expect(tester.takeException(), isNull);
        await f.clean(tester, c);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
