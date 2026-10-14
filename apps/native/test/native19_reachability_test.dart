import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/ui/app.dart';
import 'package:glukwave/ui/widgets.dart';
import 'native19_ui_test.dart' as fixture;
import 'app_layout_test.dart' as base;
import 'helpers/artwork_fixture.dart';
import 'helpers/fonts.dart';

class CameraFixture extends MobileScannerPlatform {
  bool denied = true;
  int starts = 0, stops = 0;
  @override
  Stream<BarcodeCapture?> get barcodesStream => const Stream.empty();
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const ColoredBox(color: Color(0xff252728));
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts++;
    if (denied) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
    }
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(320, 240),
    );
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {}
  @override
  Future<void> updateScanWindow(Rect? window) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final captures = <String>[], checks = <String>[];
  final realScanner = MobileScannerPlatform.instance;
  setUpAll(() async {
    await loadAppFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
  });
  setUp(installArtworkFixture);
  tearDown(() {
    clearArtworkFixture();
    debugDefaultTargetPlatformOverride = null;
    MobileScannerPlatform.instance = realScanner;
  });
  tearDownAll(() async {
    await File('../../work/qa/native19-ui-extra-proof.json').writeAsString(
      jsonEncode({
        'passed': false,
        'status': 'awaiting_cli_result',
        'checks': checks,
        'screenshots': captures,
        'scope':
            'Actual Flutter routes, isolated test catalogue and camera platform. No physical camera/OS battery verification.',
      }),
    );
  });
  Future<void> settle(WidgetTester t) async {
    await t.pump(const Duration(milliseconds: 400));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<void> shot(WidgetTester t, String name) async {
    expect(t.takeException(), isNull);
    // File and codec completions started in the widget zone need pump turns.
    for (var frame = 0; frame < 8; frame++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pump();
    }
    await base.screenshot(t, 'native19-$name');
    captures.add('work/qa/native-native19-$name.png');
  }

  Future<void> mount(
    WidgetTester t,
    fixture.Native19Controller c,
    Size size,
  ) async {
    await base.viewport(t, size);
    await t.pumpWidget(
      RepaintBoundary(
        key: const Key('capture'),
        child: GlukWaveApp(controller: c),
      ),
    );
    await settle(t);
  }

  Future<void> clean(WidgetTester t, fixture.Native19Controller c) async {
    await base.clean(t, c);
    clearArtworkFixture();
    debugDefaultTargetPlatformOverride = null;
    MobileScannerPlatform.instance = realScanner;
  }

  Future<void> route(WidgetTester t, String value, double width) async {
    if (width >= 900 && find.byKey(Key('nav-$value')).evaluate().isNotEmpty) {
      await t.ensureVisible(find.byKey(Key('nav-$value')));
      await t.tap(find.byKey(Key('nav-$value')));
    } else {
      await t.tap(find.byKey(const Key('mobile-menu')));
      await settle(t);
      final item = find.byWidgetPredicate(
        (w) => w is PopupMenuItem<String> && w.value == value,
      );
      await t.ensureVisible(item);
      await t.tap(item);
    }
    await settle(t);
    expect(t.takeException(), isNull);
  }

  for (final config in [
    (320.0, 568.0, 'light', 1.25),
    (375.0, 812.0, 'dark', 1.0),
    (768.0, 1024.0, 'amoled', 1.0),
    (938.0, 600.0, 'amoled', 1.0),
    (1440.0, 900.0, 'light', 1.0),
  ]) {
    testWidgets('Secondary routes and keyboard fit ${config.$1} ${config.$3}', (
      t,
    ) async {
      final c = (await t.runAsync(
        () => fixture.fixture(mode: config.$3, scale: config.$4),
      ))!;
      await mount(t, c, Size(config.$1, config.$2));
      if (config.$1 < 900) {
        await t.tap(find.byKey(const Key('nav-search')));
        await settle(t);
      } else {
        await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await t.sendKeyEvent(LogicalKeyboardKey.keyK);
        await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await settle(t);
        expect(
          t
              .widget<EditableText>(find.byType(EditableText).first)
              .focusNode
              .hasFocus,
          isTrue,
        );
      }
      await shot(t, '${config.$1.toInt()}-${config.$3}-search');
      FocusManager.instance.primaryFocus?.unfocus();
      await t.tap(find.byKey(const Key('nav-library')));
      await settle(t);
      await shot(t, '${config.$1.toInt()}-${config.$3}-library');
      await route(t, 'rooms', config.$1);
      await shot(t, '${config.$1.toInt()}-${config.$3}-rooms');
      await route(t, 'devices', config.$1);
      await shot(t, '${config.$1.toInt()}-${config.$3}-connect');
      await route(t, 'settings', config.$1);
      await shot(t, '${config.$1.toInt()}-${config.$3}-settings');
      checks.add(
        'search/library/rooms/Connect/settings ${config.$1} ${config.$3} scale ${config.$4}',
      );
      await clean(t, c);
    });
  }
  testWidgets('Windows displays QR while mobile sign-in is conventional', (
    t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final c = (await t.runAsync(fixture.fixture))!;
    c.user = null;
    await mount(t, c, const Size(938, 600));
    expect(find.byKey(const Key('auth-qr')), findsOneWidget);
    await shot(t, '938-auth-desktop');
    // Render the actual production dialog with an expired isolated challenge.
    // The poll immediately expires, leaving its honest error + refresh flow.
    final context = t.element(find.byKey(const Key('auth-submit')));
    showWaveDialog<void>(
      context: context,
      builder: (_) => QrLoginDialog(
        controller: c,
        qr: {
          'id': 'own-native19-code',
          'secret': 'test-only',
          'url': 'https://fixture.invalid/app?qr=own-native19-code',
          'expiresAt': DateTime.now()
              .subtract(const Duration(seconds: 1))
              .toIso8601String(),
        },
      ),
    );
    await settle(t);
    expect(find.byType(QrImageView), findsOneWidget);
    await shot(t, '938-auth-desktop-qr');
    checks.add('Windows actual QR dialog + expiry rendering, no phone QR');
    await clean(t, c);
  });
  testWidgets(
    'Guard camera denial exposes manual fallback and expires pending approval',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final camera = CameraFixture();
      MobileScannerPlatform.instance = camera;
      final c = (await t.runAsync(() => fixture.fixture(scale: 1.25)))!;
      await mount(t, c, const Size(320, 568));
      await t.tap(find.byKey(const Key('mobile-guard')));
      await settle(t);
      await t.tap(find.byKey(const Key('guard-scan')));
      await settle(t);
      expect(camera.starts, greaterThan(0));
      expect(find.text('Нужен доступ к камере'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('guard-camera-retry')));
      await settle(t);
      final retry = t.getRect(find.byKey(const Key('guard-camera-retry')));
      expect(retry.bottom, lessThanOrEqualTo(568));
      expect(retry.top, greaterThanOrEqualTo(0));
      await shot(t, '320-guard-camera-denied');
      await t.tap(find.byKey(const Key('guard-camera-retry')));
      await settle(t);
      expect(camera.starts, 2);
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.byKey(const Key('guard-manual')));
      await t.tap(find.byKey(const Key('guard-manual')));
      await settle(t);
      expect(find.byKey(const Key('guard-manual-code')), findsOneWidget);
      expect(find.byKey(const Key('guard-scan-again')), findsOneWidget);
      await shot(t, '320-guard-manual');
      c.qrLifetime = const Duration(seconds: 2);
      await t.enterText(
        find.byKey(const Key('guard-manual-code')),
        'own-expiring-code',
      );
      await t.ensureVisible(find.byKey(const Key('guard-inspect')));
      await t.tap(find.byKey(const Key('guard-inspect')));
      await settle(t);
      expect(find.byKey(const Key('guard-approve')), findsOneWidget);
      expect(c.approved, isNull);
      await t.pump(const Duration(seconds: 3));
      await settle(t);
      expect(find.byKey(const Key('guard-approve')), findsNothing);
      await shot(t, '320-guard-expired');
      c.user = null;
      c.render();
      await settle(t);
      expect(find.byKey(const Key('guard-inspect')), findsNothing);
      expect(find.byKey(const Key('guard-approve')), findsNothing);
      checks.add(
        'camera denied/retry/manual/expiry + account loss removes approval',
      );
      await clean(t, c);
    },
  );
  testWidgets(
    'Saved cover and accent use durable files; energy removes expensive visuals',
    (t) async {
      final c = (await t.runAsync(fixture.fixture))!;
      final folder = (await t.runAsync(
        () => Directory.systemTemp.createTemp('wave19-art-'),
      ))!;
      await t.runAsync(() async {
        final bytes = (await rootBundle.load(
          'assets/coast.jpg',
        )).buffer.asUint8List();
        await File('${folder.path}/cover.jpg').writeAsBytes(bytes);
      });
      c.cache.directory = folder;
      c.cache.ready = true;
      for (final key in c.cache.entries.keys) {
        (c.cache.entries[key] as Json)['cover'] = 'cover.jpg';
      }
      c.online = false;
      expect(waveArtworkProvider(c, c.tracks.first.artwork), isA<FileImage>());
      await mount(t, c, const Size(375, 812));
      await t.tap(find.byKey(const Key('mini-gesture')));
      await settle(t);
      expect(find.byKey(const Key('album-3d')), findsOneWidget);
      final trackId = c.audio.viewCurrent?.id, wasPlaying = c.audio.playing;
      await shot(t, '375-offline-file-cover');
      await t.runAsync(() => c.setEnergyMode('on'));
      await settle(t);
      expect(find.byKey(const Key('album-3d')), findsNothing);
      expect(find.byKey(const Key('cover-ambient-transform')), findsNothing);
      expect(c.audio.viewCurrent?.id, trackId);
      expect(c.audio.playing, wasPlaying);
      await shot(t, '375-energy-player');
      checks.add(
        'offline durable art/provider/accent + energy static cover/audio state preserved',
      );
      await clean(t, c);
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await t.runAsync(() => folder.delete(recursive: true));
    },
  );
  testWidgets('Loading and offline empty collection remain navigable', (
    t,
  ) async {
    final c = (await t.runAsync(fixture.fixture))!;
    c.cache.entries = {};
    c.tracks = [];
    c.loading = true;
    c.online = false;
    await mount(t, c, const Size(375, 812));
    expect(find.byKey(const Key('route-loading')), findsOneWidget);
    await shot(t, '375-offline-loading');
    await t.tap(find.byKey(const Key('nav-library')));
    await settle(t);
    c.loading = false;
    c.render();
    await settle(t);
    await t.tap(find.byKey(const Key('library-saved')));
    await settle(t);
    expect(find.byKey(const Key('saved-view')), findsOneWidget);
    await shot(t, '375-offline-empty-saved');
    checks.add('initial loading + offline empty saved accessible');
    await clean(t, c);
  });
  for (final size in [const Size(320, 568), const Size(375, 812)]) {
    testWidgets(
      'Opt-in two-line synced preview fits $size with pinned controls',
      (t) async {
        final c = (await t.runAsync(
          () => fixture.fixture(scale: size.width == 320 ? 1.25 : 1),
        ))!;
        c.settings['lyrics'] = true;
        c.settings['lyricsUnderCover'] = true;
        await mount(t, c, size);
        await t.tap(find.byKey(const Key('mini-gesture')));
        await settle(t);
        // Both excerpts remain available on short screens; internal scrolling
        // preserves the sleeve size and keeps transport controls reachable.
        expect(find.byKey(const Key('mini-lyric-0')), findsOneWidget);
        expect(find.byKey(const Key('mini-lyric-1')), findsOneWidget);
        expect(find.byKey(const Key('mini-lyric-2')), findsNothing);
        final cover = t.getRect(find.byKey(const Key('album-stage-bounds')));
        expect(cover.top, greaterThanOrEqualTo(0));
        await t.ensureVisible(find.byKey(const Key('player-play')));
        await settle(t);
        final play = t.getRect(find.byKey(const Key('player-play')));
        expect(play.top, greaterThanOrEqualTo(0));
        expect(play.bottom, lessThanOrEqualTo(size.height));
        expect(
          t.getSize(find.byKey(const Key('album-stage-bounds'))),
          cover.size,
        );
        await shot(t, '${size.width.toInt()}-mini-lyrics-enabled');
        await t.tap(find.byKey(const Key('player-lyrics-toggle')));
        await settle(t);
        expect(find.byKey(const Key('player-compact-lyrics')), findsNothing);
        expect(find.byKey(const Key('album-stage-bounds')), findsNothing);
        expect(
          find.byKey(const Key('lyrics-persistent-controls')),
          findsOneWidget,
        );
        await shot(t, '${size.width.toInt()}-mini-to-full-lyrics');
        checks.add(
          'opt-in current/next mini lines + full reading layout $size',
        );
        await clean(t, c);
      },
    );
  }
}
