// Composition evidence only. Isolated synthetic account/catalogue responses,
// muted remote transport, no owner session, no physical audio claims.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/core/parity.dart';
import 'package:glukwave/l10n/wave_localizations.dart';
import 'package:glukwave/ui/app.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/parity_panels.dart';
import 'package:glukwave/ui/widgets.dart';
import '../test/helpers/fonts.dart';
import '../test/helpers/parity_fixture.dart';
import '../test/app_layout_test.dart' show viewport, screenshot, clean;
import 'render_artwork_test.dart' show seedArtwork, artworkUrl;

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
  for (final language in ['ru', 'en', 'kk', 'uk', 'de', 'es']) {
    for (final theme
        in language == 'ru' ? ['light', 'dark', 'amoled'] : ['light']) {
      for (final width in [390.0, 1280.0]) {
        testWidgets(
          'Parity composition $language $theme $width at 1.25 text scale',
          (tester) async {
            final c = (await tester.runAsync(parityController))!;
            await tester.runAsync(
              () => c.customize({
                'theme': theme,
                'language': language,
                'fontScale': 1.25,
              }),
            );
            final cover = File(
              '../../work/qa/forss-flickermood-artwork-500.jpg',
            );
            if (await tester.runAsync(cover.exists) == true) {
              await tester.runAsync(() async {
                final bytes = await cover.readAsBytes();
                for (final size in [
                  64,
                  66,
                  70,
                  100,
                  110,
                  128,
                  130,
                  132,
                  140,
                  148,
                  160,
                  166,
                  170,
                  176,
                  200,
                  204,
                  218,
                  228,
                  256,
                  258,
                  324,
                  400,
                  600,
                ]) {
                  await seedArtwork(size, bytes);
                }
              });
              qaTrack['artwork'] = artworkUrl;
              c.tracks = [WaveTrack(qaTrack)];
              c.playlists.first['coverArtworks'] = [artworkUrl];
            }
            await c.receiveAccountState({
              'independent': false,
              'activeDeviceId': 'qa-muted-browser',
              'activeSurfaceId': 'qa-tab',
              'track': qaTrack,
              'queueTracks': [qaTrack],
              'state': {
                'trackId': 'qa-permitted',
                'position': 42,
                'playing': false,
                'volume': 0,
                'updatedAt': 20000,
              },
              'serverTime': 20000,
            });
            await viewport(tester, Size(width, 900));
            await tester.pumpWidget(
              RepaintBoundary(
                key: const Key('capture'),
                child: GlukWaveApp(controller: c),
              ),
            );
            await tester.pumpAndSettle();
            await tester.runAsync(
              () => precacheImage(
                const AssetImage('assets/logo.png'),
                tester.element(find.byType(WaveShell)),
              ),
            );
            await tester.pumpAndSettle();
            expect(c.audio.outputPlaying, isFalse);
            expect(tester.takeException(), isNull);
            if (language == 'ru') {
              await screenshot(
                tester,
                'parity-home-$language-$theme-${width.toInt()}',
              );
              await tester.tap(find.byKey(const Key('profile-link')));
              await tester.pumpAndSettle();
              await tester.ensureVisible(find.text('Настройки').last);
              await tester.tap(find.text('Настройки').last);
              await tester.pumpAndSettle();
              await tester.ensureVisible(
                find.byKey(const Key('settings-appearance')),
              );
              await tester.tap(find.byKey(const Key('settings-appearance')));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              await screenshot(
                tester,
                'parity-settings-$language-$theme-${width.toInt()}',
              );
            }
            Widget panel(Widget child) => RepaintBoundary(
              key: const Key('capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: Locale(language),
                supportedLocales: WaveStrings.supportedLocales,
                localizationsDelegates: WaveStrings.delegates,
                theme: buildWaveTheme(
                  c.customization,
                  theme == 'light' ? Brightness.light : Brightness.dark,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.25)),
                  child: child!,
                ),
                home: Scaffold(
                  body: SafeArea(
                    child: ListView(
                      padding: EdgeInsets.all(width < 900 ? 20 : 40),
                      children: [child],
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpWidget(
              panel(FriendsPage(controller: c, onRoom: () {})),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (language == 'ru') {
              await screenshot(
                tester,
                'parity-friends-$language-$theme-${width.toInt()}',
              );
            }
            final parity = WaveParity(c.api);
            await parity.load();
            await tester.pumpWidget(
              RepaintBoundary(
                key: const Key('capture'),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: Locale(language),
                  supportedLocales: WaveStrings.supportedLocales,
                  localizationsDelegates: WaveStrings.delegates,
                  theme: buildWaveTheme(
                    c.customization,
                    theme == 'light' ? Brightness.light : Brightness.dark,
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(1.25)),
                    child: child!,
                  ),
                  home: TastePage(controller: c, parity: parity),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (language == 'ru') {
              await screenshot(
                tester,
                'parity-taste-$language-$theme-${width.toInt()}',
              );
            }
            if (language == 'ru') {
              await tester.pumpWidget(
                RepaintBoundary(
                  key: const Key('capture'),
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    locale: Locale(language),
                    supportedLocales: WaveStrings.supportedLocales,
                    localizationsDelegates: WaveStrings.delegates,
                    theme: buildWaveTheme(
                      c.customization,
                      theme == 'light' ? Brightness.light : Brightness.dark,
                    ),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: const TextScaler.linear(1.25)),
                      child: child!,
                    ),
                    home: Scaffold(
                      body: PlayerPage(
                        controller: c,
                        initialTrack: c.tracks.first,
                        onMore: (_) {},
                        onClose: () {},
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              await screenshot(
                tester,
                'parity-player-$language-$theme-${width.toInt()}',
              );
              await tester.pumpWidget(
                panel(
                  Column(
                    children: [
                      AccountActions(controller: c),
                      const SizedBox(height: 24),
                      PrivacyPanel(controller: c),
                      const SizedBox(height: 24),
                      ListeningStats(controller: c),
                    ],
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              await screenshot(
                tester,
                'parity-account-$language-$theme-${width.toInt()}',
              );
              await tester.pumpWidget(panel(AdminParity(controller: c)));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              await screenshot(
                tester,
                'parity-admin-$language-$theme-${width.toInt()}',
              );
            }
            await tester.pumpWidget(const SizedBox());
            parity.dispose();
            await clean(tester, c);
            PaintingBinding.instance.imageCache.clear();
          },
        );
      }
    }
  }
}
