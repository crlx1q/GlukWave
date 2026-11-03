// Independent evaluator journeys. No production routes import this file.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/ui/client32_design.dart';
import 'package:glukwave/ui/client32_workspace.dart';
import 'package:glukwave/ui/player.dart';
import 'app_layout_test.dart' as f;
import 'clients32_shell_test.dart' as fixture;
import 'helpers/artwork_fixture.dart';

Future<void> captureEvaluator(WidgetTester tester, String name) => fixture
    .captureClient32(tester, name.replaceFirst('evaluator-', 'evaluator-r2-'));

Future<void> tapKey(WidgetTester t, String key) async {
  final target = find.byKey(Key(key));
  if (target.evaluate().isEmpty) {
    final sidebar = find.byKey(const Key('desktop-navigation-sidebar'));
    final page = find.byType(ClientScrollPage);
    final discovery = find.byKey(const Key('discovery-scroll'));
    final root = key.startsWith('nav-') && sidebar.evaluate().isNotEmpty
        ? sidebar
        : discovery.evaluate().isNotEmpty
        ? discovery
        : page;
    final scroll = find
        .descendant(of: root, matching: find.byType(Scrollable))
        .first;
    t.state<ScrollableState>(scroll).position.jumpTo(0);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(target, 160, scrollable: scroll);
  }
  await Scrollable.ensureVisible(t.element(target), alignment: .5);
  await t.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await t.tap(target);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(fixture.prepareClient32Fonts);
  setUp(installArtworkFixture);
  tearDown(() {
    clearArtworkFixture();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'Evaluator: phone artist detail retains direct access to current playback',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final c = await fixture.client32Fixture(t);
      c.audio.current!.json['artwork'] = 'https://fixture.test/coast.jpg';
      final track = c.audio.current;
      try {
        await t.runAsync(() => c.customize({'language': 'ru'}));
        await fixture.pumpClient32(t, c, const Size(375, 812));
        await tapKey(t, 'nav-search');
        await tapKey(t, 'search-artist-qa-artist');
        expect(find.byType(ClientDetailPage), findsOneWidget);
        expect(c.audio.current, same(track));
        await captureEvaluator(t, 'evaluator-phone-artist-375');
        expect(
          find.byType(MiniPlayer).hitTestable(),
          findsOneWidget,
          reason:
              'Playing music must remain directly controllable on a music detail page',
        );
        await tapKey(t, 'mini-gesture');
        expect(
          find.byKey(const Key('full-player')).hitTestable(),
          findsOneWidget,
        );
        expect(c.audio.current, same(track));
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.byType(ClientDetailPage), findsOneWidget);
        expect(find.byType(MiniPlayer).hitTestable(), findsOneWidget);
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.byType(ClientDetailPage), findsNothing);
        expect(find.byKey(const Key('discovery-scroll')), findsOneWidget);
        expect(t.takeException(), isNull);
      } finally {
        await f.clean(t, c);
        clearArtworkFixture();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  for (final spec in [
    (1440.0, 900.0, TargetPlatform.windows),
    (768.0, 1024.0, TargetPlatform.android),
    (375.0, 812.0, TargetPlatform.android),
  ]) {
    testWidgets('Evaluator: fresh search composition at ${spec.$1}', (t) async {
      debugDefaultTargetPlatformOverride = spec.$3;
      final c = await fixture.client32Fixture(t);
      c.audio.current!.json['artwork'] = 'https://fixture.test/coast.jpg';
      try {
        await t.runAsync(
          () => c.customize({'language': 'ru', 'theme': 'dark'}),
        );
        await fixture.pumpClient32(t, c, Size(spec.$1, spec.$2));
        await t.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await t.pumpAndSettle();
        await captureEvaluator(t, 'evaluator-home-${spec.$1.toInt()}-ru');
        await tapKey(t, 'nav-search');
        await captureEvaluator(t, 'evaluator-search-${spec.$1.toInt()}');
        await f.navigateShell(t, 'downloads');
        await captureEvaluator(t, 'evaluator-saved-${spec.$1.toInt()}');
        if (spec.$3 == TargetPlatform.windows) {
          await f.navigateShell(t, 'sources');
          await captureEvaluator(t, 'evaluator-sources-${spec.$1.toInt()}');
        }
        expect(t.takeException(), isNull);
      } finally {
        await f.clean(t, c);
        clearArtworkFixture();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  for (final theme in ['light', 'dark']) {
    testWidgets('Evaluator: filled room action remains readable in $theme', (
      t,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final c = await fixture.client32Fixture(t);
      c.connected = true;
      c.room = {
        'id': 'qa-evaluator-room',
        'name': 'Тихий вечер',
        'ownerId': c.user!.id,
        'members': <Map<String, dynamic>>[],
      };
      try {
        await t.runAsync(() => c.customize({'language': 'ru', 'theme': theme}));
        await fixture.pumpClient32(t, c, const Size(390, 844));
        await tapKey(t, 'pinned-room');
        final button = find.byKey(const Key('room-chat-send'));
        final icon = find.descendant(of: button, matching: find.byType(Icon));
        final foreground =
            t.widget<Icon>(icon).color ?? IconTheme.of(t.element(icon)).color!;
        final background = Theme.of(t.element(button)).colorScheme.primary;
        final luminances = [
          foreground.computeLuminance(),
          background.computeLuminance(),
        ]..sort();
        final contrast = (luminances.last + .05) / (luminances.first + .05);
        await captureEvaluator(t, 'evaluator-room-send-$theme-390');
        expect(
          contrast,
          greaterThanOrEqualTo(3),
          reason: 'The visible send arrow must contrast with its filled button',
        );
        expect(t.takeException(), isNull);
      } finally {
        await f.clean(t, c);
        clearArtworkFixture();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets(
    'Evaluator: Windows live resize retains music, workspace and dock',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final c = await fixture.client32Fixture(t);
      c.audio.current!.json['artwork'] = 'https://fixture.test/coast.jpg';
      final track = c.audio.current;
      try {
        await fixture.pumpClient32(t, c, const Size(1440, 900));
        await tapKey(t, 'toggle-listening-context');
        expect(find.byKey(const Key('desktop-listening-rail')), findsNothing);
        await tapKey(t, 'nav-artists');
        await tapKey(t, 'artist-qa-artist');
        expect(find.byType(ClientDetailPage), findsOneWidget);
        for (final size in [
          const Size(1280, 600),
          const Size(800, 600),
          const Size(720, 600),
        ]) {
          await f.viewport(t, size);
          await t.pumpAndSettle();
          expect(find.byType(ClientDetailPage), findsOneWidget);
          expect(find.byKey(const Key('desktop-main-dock')), findsOneWidget);
          expect(find.byKey(const Key('nav-profile')), findsNothing);
          expect(c.audio.current, same(track));
          expect(t.takeException(), isNull, reason: '$size');
        }
        await captureEvaluator(t, 'evaluator-desktop-artist-720-short');
        await tapKey(t, 'workspace-back');
        expect(find.byKey(const Key('artist-qa-artist')), findsOneWidget);
        expect(c.audio.current, same(track));
      } finally {
        await f.clean(t, c);
        clearArtworkFixture();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'Evaluator: short 125 percent desktop keeps every settings category usable',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final c = await fixture.client32Fixture(t);
      try {
        await t.runAsync(
          () => c.customize({'fontScale': 1.25, 'theme': 'dark'}),
        );
        await fixture.pumpClient32(t, c, const Size(1280, 600));
        await tapKey(t, 'nav-settings');
        for (final category in [
          'account',
          'privacy',
          'appearance',
          'security',
          'playback',
          'storage',
          'connections',
          'notifications',
          'devices',
          'hotkeys',
          'about',
        ]) {
          await f.selectSettingsCategory(t, category);
          expect(find.byKey(const Key('desktop-main-dock')), findsOneWidget);
          expect(t.takeException(), isNull, reason: category);
        }
        await captureEvaluator(
          t,
          'evaluator-desktop-about-1280-short-125-dark',
        );
      } finally {
        await f.clean(t, c);
        clearArtworkFixture();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  for (final language in ['en', 'ru', 'kk', 'uk', 'de', 'es']) {
    testWidgets(
      'Evaluator: 320 phone at125 percent exposes account destinations in $language',
      (t) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final c = await fixture.client32Fixture(t);
        final track = c.audio.current;
        try {
          await t.runAsync(
            () => c.customize({
              'fontScale': 1.25,
              'theme': language == 'en' ? 'light' : 'amoled',
              'language': language,
            }),
          );
          await fixture.pumpClient32(t, c, const Size(320, 640));
          for (final destination in [
            'settings',
            'friends',
            'rooms',
            'devices',
            'sources',
            'downloads',
          ]) {
            await tapKey(t, 'nav-profile');
            await tapKey(t, 'profile-$destination');
            expect(find.byType(MiniPlayer), findsOneWidget);
            expect(find.byKey(const Key('desktop-main-dock')), findsNothing);
            expect(find.byKey(const Key('player-volume')), findsNothing);
            expect(c.audio.current, same(track));
            expect(t.takeException(), isNull, reason: '$language $destination');
          }
          await captureEvaluator(t, 'evaluator-phone-saved-320-125-$language');
        } finally {
          await f.clean(t, c);
          clearArtworkFixture();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
