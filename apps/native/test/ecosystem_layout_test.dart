import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/ui/app.dart';
import 'helpers/fonts.dart';
import 'app_layout_test.dart' as fixtures;

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
        'Real device controls and session security compose at $size in $theme',
        (tester) async {
          final c = (await tester.runAsync(fixtures.controller))!;
          await tester.runAsync(() => c.customize({'theme': theme}));
          c.deviceId = 'native-install';
          c.user = WaveUser({
            'id': 'qa-user',
            'username': 'listener',
            'displayName': 'Alisher',
            'plan': 'beta',
          });
          c.online = c.connected = true;
          c.devices = [
            {
              'deviceId': 'browser',
              'surfaceId': 'browser-tab',
              'name': 'GlukWave · Chrome',
              'kind': 'web',
              'online': true,
              'sessions': 2,
              'surfaceCount': 3,
            },
            {
              'deviceId': c.deviceId,
              'surfaceId': c.surfaceId,
              'name': 'GlukWave · Windows',
              'kind': 'windows',
              'online': true,
              'sessions': 1,
              'surfaceCount': 1,
            },
            {
              'deviceId': 'phone',
              'name': 'GlukWave · Android',
              'kind': 'android',
              'online': false,
              'sessions': 1,
              'surfaceCount': 0,
            },
          ];
          final track = WaveTrack({
            'id': 'qa-track',
            'title': 'С тобой на одной волне',
            'artist': 'Твой любимый артист',
            'duration': 220,
            'playback': {'kind': 'audio'},
          });
          c.tracks = [track];
          c.sessions = [
            {
              'id': 'current',
              'current': true,
              'deviceName': 'GlukWave · Windows',
              'kind': 'windows',
              'online': true,
              'lastActiveAt': 1791507600000,
            },
            {
              'id': 'browser-session',
              'current': false,
              'deviceName': 'GlukWave · Chrome',
              'kind': 'web',
              'online': true,
              'lastActiveAt': 1791507590000,
            },
            {
              'id': 'phone-session',
              'current': false,
              'deviceName': 'GlukWave · Android',
              'kind': 'android',
              'online': false,
              'lastActiveAt': 1791421000000,
            },
          ];
          await c.receiveAccountState({
            'independent': false,
            'activeDeviceId': 'browser',
            'activeSurfaceId': 'browser-tab',
            'track': track.json,
            'queueTracks': [track.json],
            'state': {
              'trackId': track.id,
              'playing': true,
              'position': 42,
              'updatedAt': 20000,
            },
            'serverTime': 20000,
          });
          await fixtures.viewport(tester, size);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('capture'),
              child: GlukWaveApp(controller: c),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Устройства').first);
          await tester.pumpAndSettle();
          expect(find.textContaining('Веб · браузер'), findsOneWidget);
          expect(find.textContaining('Приложение Windows'), findsOneWidget);
          expect(find.textContaining('Приложение Android'), findsOneWidget);
          expect(c.audio.outputPlaying, isFalse);
          expect(tester.takeException(), isNull);
          await fixtures.screenshot(
            tester,
            'ecosystem-devices-$theme-${size.width.toInt()}',
          );
          await tester.tap(find.byKey(const Key('profile-link')));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Настройки').last);
          await tester.tap(find.text('Настройки').last);
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const Key('settings-security')),
          );
          await tester.tap(find.byKey(const Key('settings-security')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('session-revoke-current')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('sessions-revoke-others')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await fixtures.screenshot(
            tester,
            'ecosystem-sessions-$theme-${size.width.toInt()}',
          );
          await tester.tap(
            find.byKey(const Key('session-revoke-browser-session')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          await tester.tap(find.text('Отмена').last);
          await tester.pumpAndSettle();
          expect(
            c.sessions.length,
            3,
            reason: 'Cancelling a confirmation leaves the session untouched.',
          );
          await tester.ensureVisible(
            find.byKey(const Key('settings-playback')),
          );
          await tester.tap(find.byKey(const Key('settings-playback')));
          await tester.pumpAndSettle();
          await Scrollable.ensureVisible(
            tester.element(find.byKey(const Key('equalizer-band-0'))),
            alignment: .65,
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('equalizer-band-0')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await fixtures.screenshot(
            tester,
            'ecosystem-equalizer-$theme-${size.width.toInt()}',
          );
          c.room = {
            'id': 'qa-room',
            'name': 'Наш тёплый вечер',
            'ownerId': c.user!.id,
            'inviteCode': '24381',
            'state': {
              'trackId': track.id,
              'queue': [track.id],
              'position': 42,
              'playing': false,
              'updatedAt': 20000,
              'revision': 4,
            },
            'members': [
              {
                'userId': c.user!.id,
                'displayName': 'Alisher',
                'online': true,
                'canControl': true,
                'devices': [
                  {
                    'kind': 'web',
                    'name': 'GlukWave · Chrome',
                    'outputActive': true,
                    'playing': true,
                  },
                  {
                    'kind': 'windows',
                    'name': 'GlukWave · Windows',
                    'outputActive': false,
                    'playing': false,
                  },
                ],
              },
            ],
          };
          await c.receiveAccountState({
            'independent': false,
            'activeDeviceId': 'browser',
            'activeSurfaceId': 'browser-tab',
            'roomId': 'qa-room',
            'track': track.json,
            'queueTracks': [track.json],
            'state': {
              'trackId': track.id,
              'queue': [track.id],
              'playing': true,
              'position': 42,
              'updatedAt': 20000,
              'revision': 30,
            },
            'serverTime': 20000,
          });
          c.render();
          await tester.pumpAndSettle();
          if (size.width >= 900) {
            await tester.tap(find.text('Слушать вместе').first);
          } else {
            await tester.tap(find.byTooltip('Слушать вместе').first);
          }
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('pinned-room')), findsOneWidget);
          expect(c.audio.outputPlaying, isFalse);
          expect(tester.takeException(), isNull);
          await fixtures.screenshot(
            tester,
            'ecosystem-room-$theme-${size.width.toInt()}',
          );
          await Scrollable.ensureVisible(
            tester.element(find.textContaining('Приложение Windows').last),
            alignment: .45,
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('Веб · браузер'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await fixtures.screenshot(
            tester,
            'ecosystem-room-members-$theme-${size.width.toInt()}',
          );
          await fixtures.clean(tester, c);
        },
      );
    }
  }
}
