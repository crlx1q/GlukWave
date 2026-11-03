import 'package:flutter/services.dart';
// Actual application route composition, with only isolated QA catalogue data.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/ui/player.dart';
import '../test/app_layout_test.dart' as f;
import '../test/clients32_shell_test.dart'
    show
        prepareClient32Fonts,
        client32Fixture,
        pumpClient32,
        captureClient32,
        clientTap;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareClient32Fonts);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final width in [1280.0, 1440.0]) {
    testWidgets('capture Clients32 desktop routes $width', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final c = await client32Fixture(tester, tracks: 24);
      await pumpClient32(tester, c, Size(width, 900));
      await captureClient32(tester, 'desktop-home-${width.toInt()}');
      for (final route in [
        'search',
        'library',
        'liked',
        'downloads',
        'artists',
        'discover',
        'rooms',
        'friends',
        'sources',
        'devices',
        'settings',
      ]) {
        await clientTap(tester, 'nav-$route');
        expect(tester.takeException(), isNull, reason: route);
        await captureClient32(tester, 'desktop-$route-${width.toInt()}');
      }
      await clientTap(tester, 'sidebar-playlist-qa-playlist');
      await captureClient32(tester, 'desktop-playlist-${width.toInt()}');
      await clientTap(tester, 'profile-link');
      await captureClient32(tester, 'desktop-profile-${width.toInt()}');
      await clientTap(tester, 'nav-home');
      await tester.runAsync(() => c.customize({'theme': 'dark'}));
      await tester.pumpAndSettle();
      await captureClient32(tester, 'desktop-home-dark-${width.toInt()}');
      await clientTap(tester, 'mini-gesture');
      await captureClient32(tester, 'desktop-player-${width.toInt()}');
      await clientTap(tester, 'player-lyrics-toggle');
      await captureClient32(tester, 'desktop-lyrics-${width.toInt()}');
      await clientTap(tester, 'player-queue-toggle');
      await captureClient32(tester, 'desktop-queue-${width.toInt()}');
      expect(tester.takeException(), isNull);
      await f.clean(tester, c);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('capture phone and tablet actual navigation routes', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final c = await client32Fixture(tester, tracks: 24);
    await pumpClient32(tester, c, const Size(390, 844));
    await captureClient32(tester, 'phone-home-light-390');
    for (final route in ['search', 'library', 'profile']) {
      await clientTap(tester, 'nav-$route');
      await captureClient32(tester, 'phone-$route-390');
      expect(tester.takeException(), isNull, reason: route);
    }
    for (final route in [
      'friends',
      'rooms',
      'sources',
      'devices',
      'downloads',
      'settings',
    ]) {
      await clientTap(tester, 'nav-profile');
      await clientTap(tester, 'profile-$route');
      await captureClient32(tester, 'phone-$route-390');
      expect(tester.takeException(), isNull, reason: route);
    }
    await clientTap(tester, 'nav-home');
    await tester.runAsync(() => c.customize({'theme': 'dark'}));
    await tester.pumpAndSettle();
    await captureClient32(tester, 'phone-home-dark-390');
    await clientTap(tester, 'mini-gesture');
    await captureClient32(tester, 'phone-player-dark-390');
    await clientTap(tester, 'player-lyrics-toggle');
    await captureClient32(tester, 'phone-lyrics-390');
    await clientTap(tester, 'player-queue-toggle');
    await captureClient32(tester, 'phone-queue-390');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.runAsync(() => c.customize({'theme': 'amoled'}));
    await tester.pumpAndSettle();
    await captureClient32(tester, 'phone-home-amoled-390');
    await f.viewport(tester, const Size(768, 1024));
    await tester.pumpAndSettle();
    expect(find.byType(MiniPlayer), findsOneWidget);
    await captureClient32(tester, 'tablet-home-amoled-768');
    await f.clean(tester, c);
    debugDefaultTargetPlatformOverride = null;
  });
}
