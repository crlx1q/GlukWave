import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/services/desktop.dart';
import 'package:glukwave/ui/app.dart';
import 'package:glukwave/ui/auth_visuals.dart';
import 'package:glukwave/ui/desktop_player.dart';
import 'app_layout_test.dart' as fixtures;
import 'helpers/fonts.dart';

class CaptureAudio extends WaveAudioHandler {
  int next = 0, previous = 0;
  CaptureAudio(super.api, super.cache);
  @override
  Future<void> skipToNext() async {
    next++;
  }

  @override
  Future<void> skipToPrevious() async {
    previous++;
  }
}

class CaptureAuth extends fixtures.LayoutController {
  Json? submitted;
  CaptureAuth(super.api, super.cache, super.audio);
  @override
  Future<void> authenticate(
    String email,
    String password, {
    String? username,
    String? displayName,
  }) async {
    submitted = {
      'email': email,
      'password': password,
      'username': username,
      'displayName': displayName,
    };
  }
}

Future<CaptureAuth> setup() async {
  SharedPreferences.setMockInitialValues({});
  final api = fixtures.LayoutApi(), cache = MusicCache(api);
  final c = CaptureAuth(api, cache, CaptureAudio(api, cache));
  c.preferences = await SharedPreferences.getInstance();
  await c.restoreCustomizationScope();
  await c.customize({'reducedMotion': true, 'language': 'en'});
  c.loading = false;
  c.online = true;
  c.config = {
    'auth': {'google': true},
  };
  return c;
}

Future<void> mount(WidgetTester tester, CaptureAuth c, Size size) async {
  await fixtures.viewport(tester, size);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('capture'),
      child: GlukWaveApp(controller: c),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('Compact window reserves visible official source controls', () {
    expect(compactPlayerSize(quick: false), const Size(410, 116));
    expect(
      compactPlayerSize(quick: false, source: 'soundcloud'),
      const Size(410, 250),
    );
    expect(
      compactPlayerSize(quick: false, source: 'youtube'),
      const Size(410, 350),
    );
    expect(
      compactPlayerSize(quick: true, source: 'youtube'),
      const Size(360, 654),
    );
  });
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

  for (final size in [
    const Size(320, 740),
    const Size(390, 844),
    const Size(1280, 860),
  ]) {
    testWidgets(
      'Native email registration and login are real fields at $size',
      (tester) async {
        final c = (await tester.runAsync(setup))!;
        debugDefaultTargetPlatformOverride = size.width < 900
            ? TargetPlatform.android
            : TargetPlatform.windows;
        await mount(tester, c, size);
        expect(find.byKey(const Key('auth-email')), findsOneWidget);
        expect(find.byType(GoogleIdentityMark), findsOneWidget);
        expect(
          find.byKey(const Key('auth-qr')),
          size.width < 900 ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        if (size.width == 390) {
          await fixtures.screenshot(tester, 'auth-v9-mobile');
        }
        if (size.width == 1280) {
          await fixtures.screenshot(tester, 'auth-v9-desktop');
        }
        await tester.tap(find.byKey(const Key('auth-mode-register')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('auth-email')),
          'listener@example.test',
        );
        await tester.enterText(
          find.byKey(const Key('auth-password')),
          'A native password',
        );
        await tester.enterText(
          find.byKey(const Key('auth-username')),
          'listener',
        );
        await tester.enterText(find.byKey(const Key('auth-name')), 'Listener');
        await tester.ensureVisible(find.byKey(const Key('auth-submit')));
        await tester.tap(find.byKey(const Key('auth-submit')));
        await tester.pumpAndSettle();
        expect(c.submitted, {
          'email': 'listener@example.test',
          'password': 'A native password',
          'username': 'listener',
          'displayName': 'Listener',
        });
        expect(tester.takeException(), isNull);
        await fixtures.clean(tester, c);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('Startup belongs to actual initialization state', (tester) async {
    final c = (await tester.runAsync(setup))!;
    c.loading = true;
    await fixtures.viewport(tester, const Size(390, 844));
    await tester.pumpWidget(GlukWaveApp(controller: c));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('native-startup')), findsOneWidget);
    expect(find.byKey(const Key('auth-email')), findsNothing);
    c.loading = false;
    c.render();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('native-startup')), findsNothing);
    expect(find.byKey(const Key('auth-email')), findsOneWidget);
    await fixtures.clean(tester, c);
  });

  testWidgets('Legacy CAPTCHA server is an honest browser fallback', (
    tester,
  ) async {
    final c = (await tester.runAsync(setup))!;
    c.config = {
      'auth': {'google': true, 'turnstileSiteKey': 'test-sitekey'},
    };
    await mount(tester, c, const Size(390, 844));
    expect(find.byKey(const Key('auth-email')), findsNothing);
    expect(
      find.textContaining('Secure sign in opens in your browser.'),
      findsOneWidget,
    );
    c.config = {
      'auth': {
        'google': true,
        'turnstileSiteKey': 'test-sitekey',
        'nativeCaptcha': true,
      },
    };
    c.render();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('auth-email')), findsOneWidget);
    await fixtures.clean(tester, c);
  });

  for (final theme in ['light', 'dark', 'amoled']) {
    testWidgets(
      'Tray quick player and frameless mini fit $theme, wheel changes queue',
      (tester) async {
        final c = (await tester.runAsync(setup))!;
        await tester.runAsync(() => c.customize({'theme': theme}));
        c.user = WaveUser({
          'id': 'listener',
          'username': 'listener',
          'displayName': 'Listener',
        });
        c.audio.current = WaveTrack({
          'id': 'test-track',
          'title': 'On your wave',
          'artist': 'GlukWave',
          'artwork': '',
          'duration': 180,
          'source': 'local',
          'playback': {},
        });
        c.desktop.quick = true;
        await mount(tester, c, const Size(360, 420));
        expect(find.byType(DesktopCompactPlayer), findsOneWidget);
        expect(find.byKey(const Key('desktop-quick-volume')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await fixtures.screenshot(tester, 'tray-$theme');
        await tester.tap(find.byKey(const Key('desktop-quick-next')));
        await tester.pump();
        expect((c.audio as CaptureAudio).next, 1);
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(
              find.byKey(const Key('desktop-player-scroll')),
            ),
            scrollDelta: const Offset(0, -30),
          ),
        );
        await tester.pump();
        expect((c.audio as CaptureAudio).previous, 1);
        c.desktop.quick = false;
        c.desktop.mini = true;
        c.render();
        await fixtures.viewport(tester, const Size(410, 116));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('desktop-quick-dismiss')), findsNothing);
        expect(find.byKey(const Key('desktop-player-drag')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await fixtures.screenshot(tester, 'mini-$theme');
        await tester.drag(
          find.byKey(const Key('desktop-player-swipe')),
          const Offset(-80, 0),
        );
        await tester.pump();
        expect((c.audio as CaptureAudio).next, 2);
        await fixtures.clean(tester, c);
      },
    );
  }
}
