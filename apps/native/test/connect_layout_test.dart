import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/ui/app.dart';
import 'package:glukwave/ui/volume_slider.dart';
import 'app_layout_test.dart' as fixtures;
import 'helpers/fonts.dart';

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
  for (final theme in ['light', 'dark', 'amoled']) {
    for (final size in [const Size(390, 844), const Size(1280, 900)]) {
      testWidgets(
        'Connected playback, device controls and pinned room fit $theme $size',
        (tester) async {
          final c = (await tester.runAsync(fixtures.controller))!;
          await tester.runAsync(() => c.customize({'theme': theme}));
          c.deviceId = 'phone-install';
          c.user = WaveUser({
            'id': 'connect-layout-user',
            'username': 'listener',
            'displayName': 'Alisher',
            'plan': 'beta',
          });
          c.online = c.connected = true;
          c.devices = [
            {
              'deviceId': 'pc-install',
              'surfaceId': 'pc-runtime',
              'name': 'GlukWave · Windows',
              'online': true,
              'kind': 'windows',
            },
            {
              'deviceId': c.deviceId,
              'surfaceId': c.surfaceId,
              'name': 'GlukWave · Android',
              'online': true,
              'kind': 'android',
            },
            {
              'deviceId': 'old-install',
              'name': 'GlukWave · Web',
              'online': false,
              'kind': 'web',
            },
          ];
          final tracks = [
            WaveTrack({
              'id': 'track-1',
              'title': 'На твоей волне',
              'artist': 'Твой любимый артист',
              'duration': 220,
              'playback': {'kind': 'audio'},
            }),
            WaveTrack({
              'id': 'track-2',
              'title': 'Вечерний свет',
              'artist': 'Твой любимый артист',
              'duration': 190,
              'playback': {'kind': 'audio'},
            }),
          ];
          c.tracks = tracks;
          c.playlists = [
            {
              'id': 'night',
              'name': 'Тёплый вечер',
              'trackIds': tracks.map((t) => t.id).toList(),
            },
          ];
          c.likedIds = [tracks.first.id];
          await c.receiveAccountState({
            'independent': false,
            'activeDeviceId': 'pc-install',
            'activeSurfaceId': 'pc-runtime',
            'track': tracks.first.json,
            'queueTracks': tracks.map((t) => t.json).toList(),
            'serverTime': 20000,
            'state': {
              'trackId': tracks.first.id,
              'position': 42,
              'playing': true,
              'volume': .6,
              'updatedAt': 20000,
            },
          });
          await fixtures.viewport(tester, size);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('capture'),
              child: GlukWaveApp(controller: c),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(c.audio.current, isNull);
          expect(c.audio.playing, isTrue);
          expect(
            find.byKey(const Key('desktop-listening-rail')),
            size.width >= 1240 ? findsOneWidget : findsNothing,
          );
          await fixtures.screenshot(
            tester,
            'connect-home-$theme-${size.width.toInt()}',
          );
          await tester.tap(find.byTooltip('Устройства').first);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('connect-independent')), findsOneWidget);
          expect(find.byKey(const Key('connect-play-here')), findsOneWidget);
          expect(
            find.byKey(const Key('connect-remove-old-install')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await fixtures.screenshot(
            tester,
            'connect-devices-$theme-${size.width.toInt()}',
          );
          if (size.width >= 900) {
            await tester.tap(find.text('Слушать вместе').first);
          } else {
            await tester.tap(find.byTooltip('Слушать вместе').first);
          }
          await tester.pumpAndSettle();
          await tester.tap(find.text('Создать комнату').first);
          await tester.pumpAndSettle();
          expect(find.text('Общедоступная комната'), findsOneWidget);
          expect(find.byType(SwitchListTile), findsOneWidget);
          expect(
            tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
            isFalse,
          );
          await tester.enterText(find.byType(TextField).last, 'Наш вечер');
          await tester.tap(find.byType(SwitchListTile));
          await tester.pumpAndSettle();
          expect(
            tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
            isTrue,
          );
          expect(tester.takeException(), isNull);
          await fixtures.screenshot(
            tester,
            'connect-room-create-$theme-${size.width.toInt()}',
          );
          await tester.tap(find.text('Отмена').last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          c.room = {
            'id': 'room-1',
            'name': 'Тёплый вечер с друзьями',
            'ownerId': c.user!.id,
            'members': [],
          };
          c.connected = false;
          c.render();
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('pinned-room')), findsOneWidget);
          expect(find.textContaining('Переподключение'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await fixtures.clean(tester, c);
        },
      );
    }
  }
  testWidgets(
    'A mouse wheel adjusts volume within bounds rather than scrolling the page',
    (tester) async {
      double volume = .5;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: VolumeSlider(
                  value: volume,
                  onChanged: (value) => volume = value,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(VolumeSlider)),
          scrollDelta: const Offset(0, -120),
        ),
      );
      expect(volume, .6);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(VolumeSlider)),
          scrollDelta: const Offset(0, 1200),
        ),
      );
      expect(volume, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
