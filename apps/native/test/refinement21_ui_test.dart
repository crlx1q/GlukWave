import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/ui/app.dart';
import 'package:glukwave/ui/connect_picker.dart';
import 'package:glukwave/ui/connect_device_tile.dart';
import 'package:glukwave/ui/device_labels.dart';
import 'package:glukwave/ui/widgets.dart';
import 'native19_ui_test.dart' as fixture;
import 'app_layout_test.dart' as base;
import 'helpers/fonts.dart';
import 'helpers/artwork_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  setUp(() async {
    await installArtworkFixture();
    // Desktop catalogue tiles decode this real shipped asset lazily. Resolve
    // the asset transport before the widget test enters its fake frame clock.
    final forest = await rootBundle.load('assets/forest.jpg');
    expect(forest.lengthInBytes, greaterThan(0));
  });
  tearDown(clearArtworkFixture);
  Future<void> settle(WidgetTester t) async {
    await t.pump(const Duration(milliseconds: 400));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await t.pump(const Duration(milliseconds: 400));
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

  for (final size in [
    const Size(320, 568),
    const Size(375, 812),
    const Size(1440, 900),
  ]) {
    testWidgets(
      'Quick Connect has one device action and no duplicate transport ${size.width}',
      (t) async {
        final c = (await t.runAsync(
          () => fixture.fixture(scale: size.width == 320 ? 1.25 : 1),
        ))!;
        c.deviceId = 'qa-browser';
        c.connect = {'activeDeviceId': 'qa-phone', 'independent': false};
        c.devices = [
          {
            'deviceId': 'qa-phone',
            'name': 'GlukWave · Android',
            'kind': 'android',
            'online': true,
            'state': {'playing': true, 'trackId': c.tracks.first.id},
            'track': c.tracks.first.json,
          },
          {
            'deviceId': 'qa-browser',
            'name': 'Chrome · Windows',
            'kind': 'web',
            'online': true,
            'state': {'playing': false, 'trackId': c.tracks[1].id},
            'track': c.tracks[1].json,
          },
          {
            'deviceId': 'qa-offline',
            'name': 'Chrome · Android',
            'kind': 'web',
            'online': false,
            'lastSeen': 1791738600000,
            'state': {'playing': false},
            'track': c.tracks[2].json,
          },
        ];
        await mount(t, c, size);
        c.connect = {'activeDeviceId': 'qa-phone', 'independent': false};
        c.render();
        await settle(t);
        expect(c.controllingRemote, isTrue);
        expect(find.byKey(const Key('mini-active-device')), findsOneWidget);
        final output = t.getRect(find.byKey(const Key('mini-active-device')));
        expect(output.height, lessThan(28));
        int opened = 0;
        unawaited(
          showConnectPicker(
            t.element(find.byType(Scaffold).first),
            c,
            onAllDevices: () => opened++,
          ),
        );
        await settle(t);
        expect(find.byType(ConnectDeviceTile), findsNWidgets(3));
        expect(find.byKey(const Key('connect-play')), findsNothing);
        expect(find.byKey(const Key('connect-seek')), findsNothing);
        final offline = t.widget<IconButton>(
          find.byKey(const Key('connect-transfer-qa-offline')),
        );
        expect(offline.onPressed, isNull);
        expect(t.takeException(), isNull);
        final box = t.getRect(find.byKey(const Key('connect-quick-picker')));
        expect(box.left, greaterThanOrEqualTo(0));
        expect(box.right, lessThanOrEqualTo(size.width));
        expect(box.bottom, lessThanOrEqualTo(size.height));
        await base.screenshot(
          t,
          'refinement21-${size.width.toInt()}-quick-connect',
        );
        final manage = find.text('Все устройства');
        if (manage.evaluate().isNotEmpty) {
          await t.ensureVisible(manage);
          await t.tap(manage);
          await settle(t);
          expect(opened, 1);
        } else {
          Navigator.of(
            t.element(find.byKey(const Key('connect-quick-picker'))),
          ).pop();
          await settle(t);
        }
        c.connect = {'activeDeviceId': c.deviceId, 'independent': false};
        c.render();
        await settle(t);
        expect(find.byKey(const Key('mini-active-device')), findsNothing);
        await base.screenshot(
          t,
          'refinement21-${size.width.toInt()}-local-output',
        );
        await base.clean(t, c);
        clearArtworkFixture();
      },
    );
  }
  testWidgets(
    'Listening wave remains bounded and phase does not rewind after ninety seconds',
    (t) async {
      final c = (await t.runAsync(fixture.fixture))!;
      await t.runAsync(() => c.customize({'reducedMotion': false}));
      await mount(t, c, const Size(1440, 900));
      WavePainter painter() => t
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<WavePainter>()
          .first;
      await t.pump(const Duration(milliseconds: 89900));
      final before = painter().phase;
      await t.pump(const Duration(milliseconds: 250));
      final after = painter().phase;
      expect(after, greaterThanOrEqualTo(before));
      expect(after - before, lessThan(.1));
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: ListeningWave(playing: true, size: 18)),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 500));
      final rect = t.getRect(find.byKey(const Key('listening-wave')));
      expect(rect.size, const Size(18, 18));
      expect(t.takeException(), isNull);
      await base.clean(t, c);
      clearArtworkFixture();
    },
  );
}
