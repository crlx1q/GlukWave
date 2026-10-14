import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/ui/playlist_manager.dart';
import 'playlist22_test.dart' as fixture;
import 'app_layout_test.dart' as layout;
import 'helpers/fonts.dart';
import 'helpers/artwork_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('com.ryanheise.audio_session'), (_) async => null);
  });
  for (final size in [const Size(320, 568), const Size(375, 812), const Size(1280, 900)]) {
    testWidgets('Independent short playlist picker with multiple long-name memberships ${size.width}', (t) async {
      final c = (await t.runAsync(() => fixture.controller(persist: false)))!;
      final id = c.tracks.first.id;
      c.playlists = [
        {'id': 'long-one', 'name': 'Вечер у моря — длинное название любимого плейлиста для спокойного настроения', 'trackIds': [id]},
        {'id': 'long-two', 'name': 'После дождя и долгой ночной прогулки по морскому побережью', 'trackIds': [id]},
      ];
      await t.runAsync(installArtworkFixture);
      await layout.viewport(t, size);
      await t.pumpWidget(fixture.shell(c, PlaylistMembershipDialog(controller: c, track: c.tracks.first), mode: size.width == 375 ? 'light' : 'dark', scale: 1.25));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(c.playlistsForTrack(id).length, 2);
      final rect = t.getRect(find.byType(Dialog));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(size.width));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(size.height));
      await layout.screenshot(t, 'playlist22-eval-${size.width.toInt()}-multiple-memberships');
      await t.enterText(find.byKey(const Key('playlist-new-name')), 'Сохранить для прогулки');
      await t.pump();
      await t.ensureVisible(fixture.action('Новый плейлист'));
      await t.tap(fixture.action('Новый плейлист'));
      await t.pump();
      expect(find.text('Сохраняем…'), findsWidgets);
      await t.runAsync(fixture.tick);
      final api = c.api as fixture.PendingApi;
      expect(api.writes.length, 1);
      api.writes.first.completeError(Exception('Сохранение не удалось'));
      await t.pumpAndSettle();
      expect(find.text('Сохранить для прогулки'), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('Повторить'));
      await layout.screenshot(t, 'playlist22-eval-${size.width.toInt()}-error-retained-name');
      await t.pumpWidget(const SizedBox());
      clearArtworkFixture();
      await t.runAsync(() => fixture.dispose(c));
      await t.binding.setSurfaceSize(null);
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
  }
}
