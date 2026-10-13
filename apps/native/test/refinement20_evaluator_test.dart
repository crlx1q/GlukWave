import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/ui/app.dart';
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
  setUp(installArtworkFixture);
  tearDown(clearArtworkFixture);
  testWidgets('Independent actual native EQ pointer drag', (tester) async {
    final c = (await tester.runAsync(fixture.fixture))!;
    await tester.runAsync(
      () => c.customize({
        'equalizer': {'enabled': true},
      }),
    );
    await base.viewport(tester, const Size(1440, 900));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('capture'),
        child: GlukWaveApp(controller: c),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('mini-equalizer')));
    await tester.pump(const Duration(milliseconds: 500));
    final band = find.byKey(const Key('compact-eq-band-4'));
    final gesture = await tester.startGesture(tester.getCenter(band));
    await gesture.moveBy(const Offset(0, -50));
    await tester.pump();
    expect(c.customization.equalizer.bands[4], greaterThan(5));
    expect(
      tester.widget<Slider>(band).value,
      c.customization.equalizer.bands[4],
    );
    expect(tester.takeException(), isNull);
    await base.screenshot(tester, 'refinement20-eval-eq-pointer');
    await gesture.up();
    await base.clean(tester, c);
    clearArtworkFixture();
  });
  testWidgets('Independent short phone cover after actual image decoding', (
    tester,
  ) async {
    final c = (await tester.runAsync(
      () => fixture.fixture(mode: 'light', scale: 1.25),
    ))!;
    await base.viewport(tester, const Size(320, 568));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('capture'),
        child: GlukWaveApp(controller: c),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('mini-gesture')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 350)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 350)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    final r = tester.getRect(find.byKey(const Key('album-front-sleeve')));
    debugPrint('INDEPENDENT_SHORT_SLEEVE ${r.size}');
    await base.screenshot(tester, 'refinement20-eval-320-decoded');
    await base.clean(tester, c);
    clearArtworkFixture();
  });
}
