import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/ui/player.dart';
import 'native19_ui_test.dart' as fixture;
import 'app_layout_test.dart' as base;
import 'audio_design_test.dart' as audio;
import 'helpers/artwork_fixture.dart';
import 'helpers/fonts.dart';

Future<void> settlePlayerTest(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
  });
  testWidgets(
    'Online re-entry refreshes same-track lyrics once despite comments outage and ticks',
    (tester) async {
      await tester.runAsync(loadAppFonts);
      await tester.runAsync(installArtworkFixture);
      final c = (await tester.runAsync(fixture.fixture))!;
      final api = c.api as fixture.Native19Api;
      c.online = false;
      await base.viewport(tester, const Size(375, 812));
      await tester.pumpWidget(
        audio.shell(c, PlayerPage(controller: c, onMore: (_) {})),
      );
      await settlePlayerTest(tester);
      await tester.tap(find.byKey(const Key('player-lyrics-toggle')));
      await settlePlayerTest(tester);
      expect(find.text('Там, где тихо — мы услышим море'), findsNothing);
      expect(api.lyricsRequests, 0);
      api.commentsFail = true;
      c.online = true;
      c.render();
      await settlePlayerTest(tester);
      expect(find.text('Там, где тихо — мы услышим море'), findsWidgets);
      expect(api.lyricsRequests, 1);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      for (var tick = 0; tick < 3; tick++) {
        c.render();
        await tester.pump();
      }
      expect(api.lyricsRequests, 1);
      expect(tester.takeException(), isNull);
      await base.clean(tester, c);
      clearArtworkFixture();
    },
  );
}
