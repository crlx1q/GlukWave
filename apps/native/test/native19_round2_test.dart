import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/ui/app.dart';
import 'native19_ui_test.dart' as fixture;
import 'app_layout_test.dart' as base;
import 'helpers/artwork_fixture.dart';
import 'helpers/fonts.dart';

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
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> mount(WidgetTester tester, fixture.Native19Controller c) async {
    await base.viewport(tester, const Size(320, 568));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('capture'),
        child: GlukWaveApp(controller: c),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'Large-text small-phone auth segment shows whole label and activates registration',
    (tester) async {
      await tester.runAsync(installArtworkFixture);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final c = (await tester.runAsync(
        () => fixture.fixture(mode: 'light', scale: 1.25),
      ))!;
      c.user = null;
      await mount(tester, c);
      final label = find.descendant(
        of: find.byKey(const Key('auth-mode-register')),
        matching: find.byType(Text),
      );
      expect(
        tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
        isFalse,
      );
      expect(tester.widget<Text>(label).overflow, isNot(TextOverflow.ellipsis));
      await base.screenshot(tester, 'native19-round2-320-auth-label');
      await tester.tap(find.byKey(const Key('auth-mode-register')));
      await settle(tester);
      expect(find.byKey(const Key('auth-username')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await base.clean(tester, c);
      clearArtworkFixture();
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets('Large-text small-phone energy heading has no orphan fragment', (
    tester,
  ) async {
    await tester.runAsync(installArtworkFixture);
    final c = (await tester.runAsync(
      () => fixture.fixture(mode: 'light', scale: 1.25),
    ))!;
    await mount(tester, c);
    await tester.tap(find.byKey(const Key('mobile-menu')));
    await settle(tester);
    final settings = find.byWidgetPredicate(
      (widget) => widget is PopupMenuItem<String> && widget.value == 'settings',
    );
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await settle(tester);
    await base.selectSettingsCategory(tester, 'playback', 'Воспроизведение');
    final heading = find.byKey(const Key('energy-heading'));
    expect(tester.widget<Text>(heading).data, 'Экономия заряда');
    final paragraph = tester.renderObject<RenderParagraph>(heading);
    expect(paragraph.didExceedMaxLines, isFalse);
    await base.screenshot(tester, 'native19-round2-320-energy-heading');
    expect(tester.takeException(), isNull);
    await base.clean(tester, c);
    clearArtworkFixture();
  });
}
