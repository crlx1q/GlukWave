import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/ui/app.dart';
import 'package:glukwave/ui/album_stage.dart';
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
    await rootBundle.load('assets/forest.jpg');
  });
  tearDown(clearArtworkFixture);
  Future<void> settle(WidgetTester t) async {
    await t.pump(const Duration(milliseconds: 400));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<void> decoded(WidgetTester t) async {
    final images = find.descendant(
      of: find.byKey(const Key('album-front-sleeve')),
      matching: find.byType(RawImage),
    );
    for (var i = 0; i < 15; i++) {
      if (images.evaluate().isNotEmpty &&
          t.widget<RawImage>(images.first).image != null) {
        return;
      }
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(t.widget<RawImage>(images.first).image, isNotNull);
  }

  for (final size in [
    const Size(1440, 900),
    const Size(375, 812),
    const Size(320, 568),
    const Size(812, 375),
  ]) {
    testWidgets(
      'Reference sleeve keeps logo and fixed dimensions through front back edge ${size.width}x${size.height}',
      (t) async {
        final c = (await t.runAsync(fixture.fixture))!;
        await base.viewport(t, size);
        await t.pumpWidget(
          RepaintBoundary(
            key: const Key('capture'),
            child: GlukWaveApp(controller: c),
          ),
        );
        await settle(t);
        await t.tap(find.byKey(const Key('mini-gesture')));
        await settle(t);
        await decoded(t);
        final stage = find.byType(AlbumStage),
            original = t.getSize(find.byKey(const Key('album-stage-bounds'))),
            cover = t.widget<AlbumStage>(stage);
        expect(find.byKey(const Key('album-front-brand')), findsOneWidget);
        final transform = t
            .widget<Transform>(find.byKey(const Key('album-3d-transform')))
            .transform;
        final expected = Matrix4.identity()
          ..setEntry(3, 2, -1 / 1100)
          ..translateByDouble(
            -.12 * cover.size * math.cos(-18 * math.pi / 180),
            0,
            0,
            1,
          )
          ..rotateX(-9 * math.pi / 180)
          ..rotateY(-18 * math.pi / 180);
        for (var i = 0; i < 16; i++) {
          expect(transform.storage[i], closeTo(expected.storage[i], .00001));
        }
        final disc = t.widget<AnimatedPositioned>(
          find.byKey(const Key('album-record-position')),
        );
        expect(disc.left, closeTo(cover.size * .46, .001));
        await base.screenshot(
          t,
          'refinement21-cover-${size.width.toInt()}-${size.height.toInt()}-front',
        );
        final gesture = t.widget<GestureDetector>(
          find.byKey(const Key('album-3d')),
        );
        gesture.onLongPressStart!(const LongPressStartDetails());
        gesture.onLongPressMoveUpdate!(
          const LongPressMoveUpdateDetails(
            offsetFromOrigin: Offset(180 / .65, 0),
          ),
        );
        await t.pump();
        expect(find.byKey(const Key('album-back-sleeve')), findsOneWidget);
        expect(
          t.getSize(find.byKey(const Key('album-stage-bounds'))),
          original,
        );
        expect(find.byKey(const Key('album-bottom-face')), findsOneWidget);
        expect(find.byKey(const Key('album-inner-face')), findsOneWidget);
        await base.screenshot(
          t,
          'refinement21-cover-${size.width.toInt()}-${size.height.toInt()}-back',
        );
        gesture.onLongPressStart!(const LongPressStartDetails());
        gesture.onLongPressMoveUpdate!(
          const LongPressMoveUpdateDetails(
            offsetFromOrigin: Offset(-90 / .65, -130),
          ),
        );
        await t.pump();
        expect(
          t.getSize(find.byKey(const Key('album-stage-bounds'))),
          original,
        );
        await base.screenshot(
          t,
          'refinement21-cover-${size.width.toInt()}-${size.height.toInt()}-edge',
        );
        expect(t.takeException(), isNull);
        await base.clean(t, c);
        clearArtworkFixture();
      },
    );
  }
  testWidgets(
    'Reference mouse drag starts immediately and hover extends disc without resizing',
    (t) async {
      final c = (await t.runAsync(fixture.fixture))!;
      await base.viewport(t, const Size(1440, 900));
      await t.pumpWidget(
        RepaintBoundary(
          key: const Key('capture'),
          child: GlukWaveApp(controller: c),
        ),
      );
      await settle(t);
      await t.tap(find.byKey(const Key('mini-gesture')));
      await settle(t);
      await decoded(t);
      final stage = find.byKey(const Key('album-3d')),
          original = t.getSize(find.byKey(const Key('album-stage-bounds'))),
          size = t.widget<AlbumStage>(find.byType(AlbumStage)).size;
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: t.getCenter(stage));
      await t.pump(const Duration(milliseconds: 700));
      expect(
        t
            .widget<AnimatedPositioned>(
              find.byKey(const Key('album-record-position')),
            )
            .left,
        closeTo(size * .54, .001),
      );
      await base.screenshot(t, 'refinement21-cover-hover');
      await mouse.down(t.getCenter(stage));
      await mouse.moveBy(const Offset(100, 50));
      await t.pump();
      final matrix = t
          .widget<Transform>(find.byKey(const Key('album-3d-transform')))
          .transform;
      final expected = Matrix4.identity()
        ..setEntry(3, 2, -1 / 1100)
        ..translateByDouble(-.12 * size * math.cos(47 * math.pi / 180), 0, 0, 1)
        ..rotateX(-20 * math.pi / 180)
        ..rotateY(47 * math.pi / 180);
      for (var i = 0; i < 16; i++) {
        expect(matrix.storage[i], closeTo(expected.storage[i], .00001));
      }
      expect(t.getSize(find.byKey(const Key('album-stage-bounds'))), original);
      await base.screenshot(t, 'refinement21-cover-drag');
      await mouse.up();
      await mouse.moveTo(const Offset(1, 1));
      await t.pump(const Duration(milliseconds: 700));
      expect(
        t
            .widget<AnimatedPositioned>(
              find.byKey(const Key('album-record-position')),
            )
            .left,
        closeTo(size * .46, .001),
      );
      expect(t.takeException(), isNull);
      await base.clean(t, c);
      clearArtworkFixture();
    },
  );
}
