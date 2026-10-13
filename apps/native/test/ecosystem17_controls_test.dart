import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/controller.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/services/appearance_store.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/connect_picker.dart';
import 'package:glukwave/ui/room_directory.dart';
import 'package:glukwave/ui/volume_slider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_lifecycle_test.dart' as lifecycle;
import 'audio_design_test.dart' as a;
import 'app_layout_test.dart' as f;
import 'helpers/fonts.dart';
import 'helpers/artwork_fixture.dart';

class ControlOutput extends lifecycle.NativeOutput {
  final gains = <double>[];
  @override
  Future<void> setVolume(double value) async {
    gains.add(value);
  }
}

class DelayedControl extends WaveController {
  final sent = <Json>[], flights = <Completer<Json>>[];
  DelayedControl(super.api, super.cache, super.audio);
  @override
  Future<Json> emitAck(String event, Json data) {
    if (event != 'room:command') return Future.value({'room': room});
    sent.add(data);
    final pending = Completer<Json>();
    flights.add(pending);
    return pending.future;
  }
}

class DirectoryApi extends f.LayoutApi {
  final queries = <Json>[];
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    if (path == '/api/rooms') {
      queries.add(query ?? {});
      final offset = (query?['offset'] as num?)?.toInt() ?? 0,
          moderation = (query?['moderationOffset'] as num?)?.toInt() ?? 0;
      List<Json> items(String kind, int offset) => [
        for (var i = offset; i < (offset + 40).clamp(0, 41); i++)
          {
            'id': '$kind-$i',
            'name': 'Room $i',
            'visibility': kind == 'public' ? 'public' : 'private',
          },
      ];
      return {
        'rooms': [],
        'publicRooms': items('public', offset),
        'nextPublicOffset': offset == 0 ? 40 : null,
        'moderationRooms': items('private', moderation),
        'nextModerationOffset': moderation == 0 ? 40 : null,
      };
    }
    return super.call(path, method: method, data: data, query: query);
  }
}

Future<DelayedControl> pending() async {
  SharedPreferences.setMockInitialValues({});
  final api = f.LayoutApi(),
      cache = MusicCache(api),
      out = ControlOutput()..ready = true;
  final audio = WaveAudioHandler(api, cache, output: out)..autoCache = false;
  final c = DelayedControl(api, cache, audio);
  c.preferences = await SharedPreferences.getInstance();
  c.user = WaveUser({
    'id': 'self',
    'username': 'Wave owner',
    'role': 'user',
    'plan': 'beta',
  });
  c.deviceId = 'self-device';
  c.room = {
    'id': 'private-room',
    'ownerId': 'self',
    'type': 'room',
    'state': {'trackId': 'owned', 'playing': false, 'revision': 1},
  };
  c.connect = {'activeDeviceId': c.deviceId, 'activeSurfaceId': c.surfaceId};
  audio.current = lifecycle.external('owned', kind: 'audio');
  c.tracks = [audio.current!];
  audio.tracks = [audio.current!];
  return c;
}

Future<void> close(WaveController c) async {
  c.dispose();
  await c.audio.release();
  c.api.dio.close(force: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final runId = DateTime.now().millisecondsSinceEpoch, cases = <Json>[];
  void done(String name) => cases.add({'name': name, 'passed': true});
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
  tearDown(clearArtworkFixture);
  tearDownAll(() async {
    clearArtworkFixture();
    await File('../../work/qa/ecosystem17-native-proof.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'passed': cases.length == 13,
        'runId': runId,
        'cases': cases,
        'screenshots': Directory('../../work/qa')
            .listSync()
            .whereType<File>()
            .where(
              (file) =>
                  file.path.contains('native-ecosystem17-$runId-') &&
                  file.path.endsWith('.png'),
            )
            .map((file) => file.path.split(Platform.pathSeparator).last)
            .toList(),
        'boundary':
            'Actual Flutter widgets/controller and native audio API, isolated delayed network fixtures. No hosted accounts or physical devices.',
      }),
    );
  });
  test(
    'Local volume preview touches native gain immediately with no storage or transport',
    () async {
      final c = await pending(), output = c.audio.player as ControlOutput;
      var persisted = 0;
      c.audio.onVolumeChanged = (_) async {
        persisted++;
      };
      c.previewVolume(.2);
      c.previewVolume(.4);
      c.previewVolume(.7);
      await Future<void>.delayed(Duration.zero);
      expect(output.gains.last, .7);
      expect(c.audio.volume, .7);
      expect(c.sent, isEmpty);
      expect(persisted, 0);
      await c.transport('volume', {'volume': .7});
      expect(persisted, 1);
      expect(c.audio.volume, .7);
      await close(c);
      done(
        'real local volume draft, no transport or persistence, final single write',
      );
    },
  );
  test(
    'Latest optimistic room shuffle survives an earlier failed command',
    () async {
      final c = await pending();
      final one = c.transport('shuffle', {'enabled': true});
      final observed = expectLater(one, throwsA(isA<WaveException>()));
      await Future<void>.delayed(Duration.zero);
      expect(c.audio.shuffle, isTrue);
      final two = c.transport('shuffle', {'enabled': false});
      await Future<void>.delayed(Duration.zero);
      expect(c.audio.shuffle, isFalse);
      expect(c.sent.length, 1);
      c.flights[0].completeError(const WaveException('Denied'));
      await observed;
      await Future<void>.delayed(Duration.zero);
      expect(c.sent.length, 2);
      expect(c.audio.shuffle, isFalse);
      c.flights[1].complete({'ok': true});
      await two;
      expect(c.audio.shuffle, isFalse);
      await close(c);
      done('serialized optimistic modes with stale failure guard');
    },
  );
  test(
    'Repeat failure rolls back, admin controls any room and ordinary jam pause remains individual',
    () async {
      final c = await pending();
      final repeat = c.transport('repeat', {'repeat': 'one'});
      final observed = expectLater(repeat, throwsA(isA<WaveException>()));
      await Future<void>.delayed(Duration.zero);
      expect(c.audio.repeat, AudioServiceRepeatMode.one);
      c.flights.single.completeError(const WaveException('Denied'));
      await observed;
      expect(c.audio.repeat, AudioServiceRepeatMode.none);
      c.room!['ownerId'] = 'other';
      c.room!['members'] = [
        {'userId': 'self', 'canControl': false},
      ];
      expect(c.canControl, isFalse);
      c.room!['type'] = 'jam';
      expect(c.jamListener, isTrue);
      c.user = WaveUser({'id': 'self', 'role': 'admin'});
      expect(c.canControl, isTrue);
      expect(c.canManageRoom, isTrue);
      expect(c.jamListener, isFalse);
      c.user = WaveUser({'id': 'self', 'role': 'user'});
      expect(c.canControl, isFalse);
      await close(c);
      done('rollback and fresh role permissions with guest-only jam pause');
    },
  );
  test(
    'Changing output clears unfinished volume preview without committing it',
    () async {
      final c = await pending();
      c.previewVolume(.1);
      await c.receiveAccountState({
        'independent': false,
        'activeDeviceId': 'remote',
        'activeSurfaceId': 'remote-surface',
        'roomId': 'private-room',
        'track': c.audio.current!.json,
        'queueTracks': [c.audio.current!.json],
        'state': {
          'trackId': 'owned',
          'volume': .8,
          'playing': false,
          'queue': ['owned'],
          'revision': 2,
        },
      });
      expect(c.audio.volume, .8);
      expect(c.sent, isEmpty);
      await close(c);
      done('output scope changes discard unfinished preview');
    },
  );
  test(
    'Room pause is immediate and stale playing snapshot cannot restart pending pause',
    () async {
      final c = await pending(), output = c.audio.player as ControlOutput;
      output.active = true;
      final action = c.transport('pause');
      final observed = expectLater(action, throwsA(isA<WaveException>()));
      await Future<void>.delayed(Duration.zero);
      expect(c.audio.playing, isFalse);
      expect(output.active, isFalse);
      await c.receiveRoomState({
        'roomId': 'private-room',
        'state': {
          'trackId': 'owned',
          'playing': true,
          'position': 0,
          'queue': ['owned'],
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
          'revision': 2,
        },
      }, force: true);
      expect(c.audio.playing, isFalse);
      expect(output.active, isFalse);
      c.flights.single.completeError(const WaveException('Denied'));
      await observed;
      expect(output.active, isTrue);
      expect(c.audio.playing, isTrue);
      await close(c);
      done('actual immediate local pause, stale snapshot mask and rollback');
    },
  );
  test(
    'Held color writes preview only and persists final presentation once',
    () async {
      SharedPreferences.setMockInitialValues({});
      final api = f.LayoutApi(), prefs = await SharedPreferences.getInstance();
      final store = AppearanceStore(api, prefs);
      await store.selectScope('held');
      final hold = store.beginEdit();
      for (var i = 0; i < 20; i++) {
        await store.change({
          'appearance': {
            'dark': {'accent': '#${(0x803a50 + i).toRadixString(16)}'},
          },
        });
      }
      expect(prefs.getString('appearance:held'), isNull);
      store.endEdit(hold);
      await store.flushLocalWrites();
      expect(prefs.getString('appearance:held'), isNotNull);
      expect(store.current.appearance.dark.accent, '#803a63');
      store.dispose();
      api.dio.close(force: true);
      done('held color previews avoid disk serialization until release');
    },
  );
  test(
    'Directories page beyond forty and refreshing loaded cards preserves independent admin pagination',
    () async {
      final api = DirectoryApi()..token = 'isolated',
          cache = MusicCache(api),
          audio = WaveAudioHandler(api, cache),
          c = WaveController(api, cache, audio);
      c.user = WaveUser({'id': 'self', 'role': 'admin'});
      c.online = true;
      await c.refreshRoomDirectory();
      expect(c.publicRooms.length, 40);
      expect(c.moderationRooms.length, 40);
      await c.refreshRoomDirectory(morePublic: true);
      expect(c.publicRooms.length, 41);
      expect(c.nextModerationRoomOffset, 40);
      await c.refreshRoomDirectory(moreModeration: true);
      expect(c.moderationRooms.length, 41);
      expect(c.publicRooms.length, 41);
      await c.refreshRoomDirectory();
      expect(c.publicRooms.length, 41);
      expect(c.moderationRooms.length, 41);
      expect(api.queries.length, 5);
      c.user = WaveUser({'id': 'self', 'role': 'user'});
      await c.refreshRoomDirectory();
      expect(c.moderationRooms, isEmpty);
      expect(c.nextModerationRoomOffset, isNull);
      await close(c);
      done('bounded public/admin pagination and refreshed loaded pages');
    },
  );
  for (final size in [const Size(375, 812), const Size(1440, 900)]) {
    testWidgets('Ordinary fullscreen fits fixed cover and transport $size', (
      tester,
    ) async {
      final c = (await tester.runAsync(f.controller))!;
      await tester.runAsync(
        () => c.customize({
          'language': 'ru',
          'appearance': {'cover3d': true},
        }),
      );
      await tester.runAsync(installArtworkFixture);
      c.online = true;
      const art = 'https://wave-fixture.invalid/coast.jpg';
      final track = WaveTrack({
        'id': 'owned-art',
        'title': 'На твоей волне',
        'artist': 'GlukWave',
        'artwork': art,
        'duration': 180,
        'source': 'local',
        'playback': {'kind': 'audio'},
      });
      c.audio.current = track;
      c.audio.tracks = [track];
      await f.viewport(tester, size);
      await tester.pumpWidget(
        a.shell(
          c,
          PlayerPage(controller: c, initialTrack: track, onMore: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .any((image) => image.image != null),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byKey(const Key('player-content-scroll')),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
        reason:
            'Fullscreen artwork and transport fit the viewport without an outer scroll.',
      );
      final play = tester.getRect(find.byKey(const Key('player-play')));
      expect(play.bottom, lessThan(size.height));
      expect(find.byKey(const Key('player-cover-options')), findsNothing);
      await f.screenshot(
        tester,
        'ecosystem17-$runId-player-${size.width.toInt()}',
      );
      await f.clean(tester, c);
      clearArtworkFixture();
      done('fixed cover viewport ${size.width.toInt()}');
    });
  }
  testWidgets(
    'Compact Connect contains real active controls and opens at its measured anchor',
    (tester) async {
      final c = (await tester.runAsync(f.controller))!;
      final track = lifecycle.external('owned', kind: 'audio');
      c.deviceId = 'native';
      c.connect = {'activeDeviceId': 'native', 'activeSurfaceId': c.surfaceId};
      c.audio.current = track;
      c.audio.tracks = [track];
      c.devices = [
        {
          'id': 'native',
          'name': 'GlukWave Windows',
          'kind': 'windows',
          'online': true,
        },
      ];
      await f.viewport(tester, const Size(390, 812));
      await tester.pumpWidget(
        a.shell(
          c,
          Scaffold(
            body: Builder(
              builder: (context) => Align(
                alignment: Alignment.bottomRight,
                child: TextButton(
                  onPressed: () => showConnectPicker(
                    context,
                    c,
                    anchor: const Rect.fromLTWH(320, 735, 42, 42),
                  ),
                  child: const Text('Connect'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('connect-active-player')), findsOneWidget);
      expect(find.byKey(const Key('connect-seek')), findsOneWidget);
      expect(find.byKey(const Key('connect-next')), findsOneWidget);
      final rect = tester.getRect(
        find.byKey(const Key('connect-quick-picker')),
      );
      expect(rect.bottom, lessThan(735));
      expect(rect.top, greaterThan(10));
      await f.screenshot(tester, 'ecosystem17-$runId-connect-390');
      await f.clean(tester, c);
      done('anchored Connect active track and complete controls');
    },
  );
  testWidgets(
    'My rooms includes highlighted active non-owned room and informative discovery',
    (tester) async {
      final c = (await tester.runAsync(f.controller))!;
      c.user = WaveUser({'id': 'self', 'plan': 'beta'});
      c.room = {
        'id': 'joined',
        'name': 'Ночная волна',
        'ownerId': 'friend',
        'visibility': 'public',
        'members': [],
        'state': {'playing': true},
      };
      c.publicRooms = [
        {
          'id': 'open',
          'name': 'Открытая волна',
          'visibility': 'public',
          'memberCount': 13,
          'onlineCount': 5,
          'listeningCount': 3,
          'members': [
            {'displayName': 'Listener', 'online': true, 'playing': true},
          ],
          'currentTrack': {
            'id': 'owned',
            'title': 'Вечер',
            'artist': 'Wave collective',
            'duration': 180,
          },
          'state': {'playing': true},
        },
      ];
      await f.viewport(tester, const Size(390, 812));
      await tester.pumpWidget(
        a.shell(
          c,
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: RoomDirectory(controller: c),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('current-room-highlight')), findsOneWidget);
      expect(find.text('+10'), findsOneWidget);
      expect(find.textContaining('3 listening'), findsOneWidget);
      expect(find.textContaining('5 online'), findsOneWidget);
      await f.screenshot(tester, 'ecosystem17-$runId-rooms-390');
      await f.clean(tester, c);
      done('non-owned current room in My rooms and truthful public counts');
    },
  );
  testWidgets('Native volume drag previews actual gain but only commits once', (
    tester,
  ) async {
    var previews = 0, commits = 0;
    double last = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VolumeSlider(
            value: .3,
            onPreview: (value) {
              previews++;
              last = value;
            },
            onChanged: (_) => commits++,
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    await gesture.moveBy(const Offset(45, 0));
    await tester.pump(const Duration(seconds: 1));
    expect(previews, greaterThan(0));
    expect(last, greaterThan(.3));
    expect(commits, 0);
    await gesture.up();
    await tester.pump();
    expect(commits, 1);
    await tester.pumpWidget(const SizedBox());
    done('held native slider local draft and one release commit');
  });
  testWidgets(
    'Wheel gain keeps draft while parent receives immediate preview then commits once',
    (tester) async {
      double value = .5;
      var commits = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => VolumeSlider(
                value: value,
                onPreview: (next) => setState(() => value = next),
                onChanged: (_) => commits++,
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        tester.binding.handlePointerEvent(
          PointerScrollEvent(
            position: tester.getCenter(find.byType(Slider)),
            scrollDelta: const Offset(0, -30),
          ),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(value, greaterThan(.5));
      expect(commits, 0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(commits, 1);
      await tester.pumpWidget(const SizedBox());
      done('wheel preview parent rebuild does not cancel final commit');
    },
  );
}
