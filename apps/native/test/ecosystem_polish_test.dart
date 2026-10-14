import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/core/artwork.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/ui/volume_slider.dart';
import 'package:glukwave/ui/queue_panel.dart';
import 'package:glukwave/ui/album_stage.dart';
import 'package:glukwave/ui/connect_picker.dart';
import 'package:glukwave/ui/device_labels.dart';
import 'package:glukwave/ui/listening_presence.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/widgets.dart';
import 'package:glukwave/services/appearance_store.dart';
import 'package:glukwave/ui/appearance_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_layout_test.dart' as f;
import 'audio_design_test.dart' as a;
import 'player_details_test.dart' as details;
import 'audio_lifecycle_test.dart' as lifecycle;
import 'helpers/fonts.dart';

class PendingApi extends f.LayoutApi {
  final handoff = Completer<Json>();
  int handoffs = 0;
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    if (path == '/api/devices/command') {
      handoffs++;
      return handoff.future;
    }
    return super.call(path, method: method, data: data, query: query);
  }
}

class SettingsApi extends f.LayoutApi {
  final patches = <Json>[];
  int revision = 0;
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    if (path == '/api/settings' && method == 'PATCH') {
      patches.add(object(data));
      return {'settings': object(data), 'revision': ++revision};
    }
    return super.call(path, method: method, data: data, query: query);
  }
}

class QueueController extends f.LayoutController {
  final List<String> starts = [];
  final List<Json> commands = [];
  QueueController(super.api, super.cache, super.audio);
  @override
  Future<void> play(
    WaveTrack target, {
    List<WaveTrack>? list,
    bool preserveWave = false,
  }) async {
    starts.add(target.id);
  }

  @override
  Future<Json> emitAck(String event, Json data) async {
    commands.add({'event': event, ...data});
    return {'ok': true};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final runId = DateTime.now().millisecondsSinceEpoch;
  final cases = <Json>[];
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
  tearDownAll(() async {
    await File(
      '../../work/qa/ecosystem-polish-native-proof.json',
    ).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'status': cases.length == 18 ? 'PASSED' : 'INCOMPLETE',
        'runId': runId,
        'cases': cases,
        'screenshots': Directory('../../work/qa')
            .listSync()
            .whereType<File>()
            .where(
              (file) =>
                  file.path.contains('native-ecosystem-polish-$runId-') &&
                  file.path.endsWith('.png'),
            )
            .map((file) => file.path.split(Platform.pathSeparator).last)
            .toList(),
        'boundary':
            'Actual Flutter widgets/controller, isolated network and audio output. No physical installations or production accounts.',
      }),
    );
  });
  void done(String name) => cases.add({'name': name, 'passed': true});
  testWidgets(
    'Appearance holds real pointer and color focus until final commit',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = SettingsApi()..token = 'isolated';
      final store = AppearanceStore(api, await SharedPreferences.getInstance());
      await store.selectScope(
        'test',
        fallback: {'reducedMotion': true, 'language': 'en'},
      );
      await f.viewport(tester, const Size(390, 850));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppearancePanel(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      final range = find.byKey(const Key('radius-slider'));
      await tester.ensureVisible(range);
      await tester.pumpAndSettle();
      final old = store.current.appearance.radius;
      final gesture = await tester.startGesture(tester.getCenter(range));
      await gesture.moveBy(const Offset(70, 0));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.runAsync(store.flushLocalWrites);
      expect(store.current.appearance.radius, isNot(old));
      expect(
        api.patches,
        isEmpty,
        reason: 'A held pause exceeds the old debounce yet stays local.',
      );
      await store.flush();
      expect(
        api.patches,
        isEmpty,
        reason: 'Remote/lifecycle flushes also respect the active edit.',
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(api.patches, hasLength(1));
      expect(
        object(api.patches.single['appearance'])['radius'],
        store.current.appearance.radius,
      );
      final color = find.descendant(
        of: find.byKey(const ValueKey('accent-editor-light')),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(color);
      await tester.enterText(color, '#556677');
      await tester.pump(const Duration(milliseconds: 900));
      await tester.runAsync(store.flushLocalWrites);
      expect(store.current.appearance.light.accent, '#556677');
      expect(api.patches, hasLength(1));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(api.patches, hasLength(2));
      expect(store.pending, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      api.dio.close(force: true);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.binding.setSurfaceSize(null);
      done(
        'Actual appearance range held >550ms and valid color focus: live local preview, one final PATCH each',
      );
    },
  );
  test(
    'Removing current queue item lets actual completed event advance to first remainder',
    () async {
      final api = lifecycle.PlaybackApi();
      final output = lifecycle.NativeOutput();
      final audio = WaveAudioHandler(
        api,
        lifecycle.PlaybackCache(api),
        output: output,
      )..autoCache = false;
      final first = lifecycle.external('first', kind: 'audio'),
          next = lifecycle.external('next', kind: 'audio'),
          last = lifecycle.external('last', kind: 'audio');
      for (final mode in [
        AudioServiceRepeatMode.none,
        AudioServiceRepeatMode.one,
      ]) {
        await audio.playTrack(first, list: [first, next, last]);
        await audio.setRepeatMode(mode);
        await audio.setShuffleMode(AudioServiceShuffleMode.all);
        audio.replaceQueue([next, last]);
        expect(audio.current?.id, 'first');
        expect(output.active, true);
        final started = Completer<void>();
        final subscription = audio.mediaItem.listen((item) {
          if (item?.id == 'next' && !started.isCompleted) started.complete();
        });
        output.processing.add(ProcessingState.completed);
        await started.future.timeout(const Duration(seconds: 2));
        await Future<void>.delayed(Duration.zero);
        expect(audio.current?.id, 'next');
        await subscription.cancel();
      }
      await audio.playTrack(first, list: [first]);
      audio.replaceQueue([]);
      final loads = output.loaded.length;
      expect(
        output.active,
        true,
        reason:
            'Removing the final queued item must not interrupt the current audio.',
      );
      final paused = output.states.stream.firstWhere((state) => !state.playing);
      output.processing.add(ProcessingState.completed);
      await paused.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      expect(output.active, false);
      expect(audio.current?.id, first.id);
      expect(
        output.loaded.length,
        loads,
        reason: 'An empty queue does not reload/repeat the removed track.',
      );
      await audio.release();
      api.dio.close(force: true);
      done(
        'Real native completion after current removal advances to first remainder or pauses when empty, even with repeat-one/shuffle',
      );
    },
  );
  test(
    'Transfer single flight retains old output and clears on success',
    () async {
      final api = PendingApi(), cache = MusicCache(PendingApi());
      final audio = WaveAudioHandler(api, cache),
          c = f.LayoutController(api, cache, audio);
      c.deviceId = 'phone';
      c.connect = {'activeDeviceId': 'old'};
      final one = c.transfer('pc'),
          two = c.transfer('pc'),
          three = c.transfer('other');
      expect(identical(one, two), true);
      expect(identical(one, three), true);
      expect(c.transferPending, 'pc');
      expect(c.activeDeviceId, 'old');
      expect(api.handoffs, 1);
      api.handoff.complete({});
      await one;
      expect(c.transferPending, null);
      expect(c.pendingDeviceActions, isEmpty);
      c.dispose();
      await audio.release();
      api.dio.close(force: true);
      cache.api.dio.close(force: true);
      done('One cloud handoff for repeated taps; no output before ACK');
    },
  );
  test(
    'Failed transfer releases pending and preserves previous selection',
    () async {
      final api = PendingApi(), cache = MusicCache(PendingApi());
      final audio = WaveAudioHandler(api, cache),
          c = f.LayoutController(api, cache, audio);
      c.connect = {'activeDeviceId': 'old'};
      final task = c.transfer('new');
      api.handoff.completeError(const WaveException('isolated offline'));
      await expectLater(task, throwsA(isA<WaveException>()));
      expect(c.activeDeviceId, 'old');
      expect(c.transferPending, null);
      c.dispose();
      await audio.release();
      api.dio.close(force: true);
      cache.api.dio.close(force: true);
      done('Failed handoff clears spinner and preserves confirmed output');
    },
  );
  test('Room queue and modes use authoritative commands and permissions', () async {
    final base = await a.makeController();
    final c = QueueController(base.api, base.cache, base.audio);
    c.user = WaveUser({'id': 'owner'});
    c.room = {'id': 'room', 'ownerId': 'owner', 'members': []};
    c.connect = {'activeDeviceId': 'pc'};
    c.tracks = base.tracks;
    await c.audio.setShuffleMode(AudioServiceShuffleMode.all);
    await c.audio.setRepeatMode(AudioServiceRepeatMode.one);
    await c.setQueue(base.tracks.reversed.toList());
    expect(c.commands.map((v) => v['command']), ['shuffle', 'repeat', 'queue']);
    expect(c.commands[0]['enabled'], true);
    expect(c.commands[1]['repeat'], 'one');
    expect(c.commands[2]['queue'], ['own-2', 'own-1', 'own-0']);
    expect(
      c.audio.shuffle,
      true,
      reason:
          'Mode presentation responds immediately; the server command still owns the shared timeline',
    );
    c.room!['ownerId'] = 'other';
    await expectLater(
      c.audio.setShuffleMode(AudioServiceShuffleMode.all),
      throwsA(isA<WaveException>()),
    );
    await expectLater(c.removeQueue('own-0'), throwsA(isA<WaveException>()));
    expect(c.commands.length, 3);
    c.dispose();
    base.dispose();
    await base.audio.release();
    base.api.dio.close(force: true);
    done(
      'Shared queue/shuffle/repeat server commands and listener permission guard',
    );
  });
  test(
    'Snapshots and remote state retain modes without clobbering legacy state',
    () async {
      final c = await a.makeController();
      final state = PlaybackSnapshot.fromJson({
        'shuffle': true,
        'repeat': 'one',
        'queue': ['own-0'],
      });
      c.audio.showRemote(state, c.tracks.first, c.tracks);
      expect(c.audio.shuffle, true);
      expect(c.audio.repeat, AudioServiceRepeatMode.one);
      expect(state.toJson()['shuffle'], true);
      c.audio.applyPlaybackModes(const PlaybackSnapshot());
      expect(c.audio.shuffle, true);
      c.dispose();
      await c.audio.release();
      c.api.dio.close(force: true);
      done('Connect/room/LAN snapshots preserve shuffle and repeat');
    },
  );
  test(
    'Queue edits preserve active playback identity and support add/remove/reorder',
    () async {
      final c = await a.makeController();
      final playing = c.audio.current;
      await c.moveQueue(2, 0);
      expect(c.audio.viewTracks.map((t) => t.id), ['own-2', 'own-0', 'own-1']);
      await c.removeQueue('own-1');
      expect(c.audio.current, same(playing));
      await c.addQueue(c.tracks.firstWhere((t) => t.id == 'own-1'));
      expect(c.audio.viewTracks.map((t) => t.id), ['own-2', 'own-0', 'own-1']);
      c.dispose();
      await c.audio.release();
      c.api.dio.close(force: true);
      done(
        'Local queue mutations preserve current audio and explicit ordering',
      );
    },
  );
  test(
    'Mini thumbnail URLs lower resolution while full cover remains large',
    () {
      expect(
        artworkForDisplay(
          'https://i1.sndcdn.com/artworks-example-t500x500.png?x=1',
          large: false,
        ),
        'https://i1.sndcdn.com/artworks-example-large.jpg?x=1',
      );
      expect(
        artworkForDisplay(
          'https://i.ytimg.com/vi/12345678901/maxresdefault.jpg',
          large: false,
        ),
        'https://i.ytimg.com/vi/12345678901/mqdefault.jpg',
      );
      expect(
        artworkForDisplay(
          'https://i.ytimg.com.evil/vi/12345678901/maxresdefault.jpg',
          large: false,
        ),
        'https://i.ytimg.com.evil/vi/12345678901/maxresdefault.jpg',
      );
      done('Trusted provider miniature image URLs with original fallback');
    },
  );
  testWidgets(
    'Long slider drag sends zero intermediate requests and one final commit',
    (tester) async {
      final values = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: DraftSlider(value: .2, onChanged: values.add, scope: 'pc'),
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byType(Slider));
      final drag = await tester.startGesture(
        Offset(rect.left + 50, rect.center.dy),
      );
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await drag.moveBy(const Offset(15, 0));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(values, isEmpty);
      await drag.up();
      await tester.pump();
      expect(values.length, 1);
      expect(values.single, greaterThan(.6));
      await tester.pump(const Duration(seconds: 1));
      expect(values.length, 1);
      done('Actual long drag commits exactly one command on release');
    },
  );
  testWidgets(
    'Wheel settles once and changing scope cancels an unfinished command',
    (tester) async {
      final values = <double>[];
      Widget shell(String scope) => MaterialApp(
        home: Scaffold(
          body: VolumeSlider(value: .4, onChanged: values.add, scope: scope),
        ),
      );
      await tester.pumpWidget(shell('pc'));
      final center = tester.getCenter(find.byType(Slider));
      for (var i = 0; i < 8; i++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: center,
            scrollDelta: const Offset(0, -20),
          ),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(values, isEmpty);
      await tester.pump(const Duration(milliseconds: 300));
      expect(values.length, 1);
      expect(values.single, greaterThan(.5));
      values.clear();
      await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: const Offset(0, -20)),
      );
      await tester.pumpWidget(shell('phone'));
      await tester.pump(const Duration(seconds: 1));
      expect(values, isEmpty);
      done('Wheel emits once after quiet interval; old output draft discarded');
    },
  );
  testWidgets(
    'Queue artwork is playable, removal collapses lower rows and add uses real catalog',
    (tester) async {
      final base = (await tester.runAsync(a.makeController))!;
      final c = QueueController(base.api, base.cache, base.audio);
      c.tracks = List.of(base.tracks);
      await f.viewport(tester, const Size(390, 850));
      await tester.pumpWidget(
        a.shell(
          c,
          SingleChildScrollView(
            child: QueuePanel(controller: c, onMore: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('queue-cover-own-1')));
      await tester.pumpAndSettle();
      expect(c.starts, ['own-1']);
      final before = tester
          .getTopLeft(find.byKey(const Key('queue-cover-own-2')))
          .dy;
      await c.removeQueue('own-1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));
      final after = tester
          .getTopLeft(find.byKey(const Key('queue-cover-own-2')))
          .dy;
      expect(after, lessThan(before));
      expect(find.byKey(const Key('queue-cover-own-1')), findsNothing);
      await tester.tap(find.byKey(const Key('queue-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('enqueue-own-1')));
      await tester.pumpAndSettle();
      expect(c.audio.viewTracks.any((t) => t.id == 'own-1'), true);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await f.screenshot(tester, 'ecosystem-polish-$runId-queue-390');
      expect(tester.takeException(), isNull);
      c.dispose();
      await f.clean(tester, base);
      done('Actual queue cover tap, settling removal and real catalog add');
    },
  );
  testWidgets('Queue keyboard alternative moves and listeners cannot edit', (
    tester,
  ) async {
    final c = (await tester.runAsync(a.makeController))!;
    await f.viewport(tester, const Size(390, 850));
    await tester.pumpWidget(
      a.shell(c, QueuePanel(controller: c, onMore: (_) {})),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('queue-actions-own-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move up'));
    await tester.pumpAndSettle();
    expect(c.audio.viewTracks.map((t) => t.id), ['own-0', 'own-2', 'own-1']);
    c.user = WaveUser({'id': 'listener'});
    c.room = {'id': 'room', 'ownerId': 'other'};
    c.render();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextButton>(find.byKey(const Key('queue-add'))).onPressed,
      isNull,
    );
    await f.clean(tester, c);
    expect(tester.takeException(), isNull);
    done('Accessible reorder menu and room listener disabled editing');
  });
  testWidgets(
    'Room avatars show three plus remainder from real playing devices',
    (tester) async {
      final c = (await tester.runAsync(a.makeController))!;
      c.room = {
        'id': 'room',
        'members': List.generate(
          13,
          (i) => {
            'displayName': 'Listener $i',
            'online': true,
            'devices': [
              {'outputActive': true, 'playing': i < 12, 'online': true},
            ],
          },
        ),
      };
      await tester.pumpWidget(a.shell(c, ListeningPresence(controller: c)));
      await tester.pumpAndSettle();
      expect(find.byType(Artwork), findsNWidgets(3));
      expect(find.text('+9'), findsOneWidget);
      expect(
        memberListening({
          'online': true,
          'devices': [
            {'outputActive': false, 'playing': true},
          ],
        }),
        false,
      );
      await f.screenshot(tester, 'ecosystem-polish-$runId-presence');
      await f.clean(tester, c);
      done('Playing/online distinction and three-avatar +N group');
    },
  );
  testWidgets(
    'Connect picker shows Chrome mark, actual output and one pending handoff',
    (tester) async {
      final c = (await tester.runAsync(a.makeController))!;
      c.devices = [
        {
          'id': 'pc',
          'name': 'Chrome · Windows',
          'kind': 'web',
          'online': true,
          'track': c.tracks.first.json,
          'state': {'trackId': c.tracks.first.id, 'playing': true},
        },
        {
          'id': 'phone',
          'name': 'GlukWave · Android',
          'kind': 'android',
          'online': true,
        },
      ];
      c.connect = {'activeDeviceId': 'pc'};
      await f.viewport(tester, const Size(390, 850));
      await tester.pumpWidget(
        a.shell(
          c,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showConnectPicker(context, c),
              child: const Text('Connect'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('connect-quick-picker')), findsOneWidget);
      expect(find.byIcon(Icons.language_rounded), findsNothing);
      expect(find.text(c.tracks.first.title), findsOneWidget);
      expect(
        find.byType(ListeningWave),
        findsOneWidget,
        reason:
            'The selected output exposes its track once; the picker does not duplicate transport',
      );
      await f.screenshot(tester, 'ecosystem-polish-$runId-connect-390');
      expect(tester.takeException(), isNull);
      await f.clean(tester, c);
      done(
        'Actual compact Connect picker with named Chrome mark and playing waveform',
      );
    },
  );
  testWidgets(
    'Cover has scene headroom without dynamic scale or height-based shrink',
    (tester) async {
      final c = (await tester.runAsync(a.makeController))!;
      await tester.runAsync(
        () => c.customize({
          'appearance': {'cover3d': true},
        }),
      );
      await f.viewport(tester, const Size(390, 650));
      await tester.pumpWidget(
        a.shell(c, PlayerPage(controller: c, onMore: (_) {})),
      );
      await tester.pumpAndSettle();
      final stage = find.byKey(const Key('album-stage-bounds')),
          transform = find.byKey(const Key('album-3d-transform'));
      final before = tester.getSize(stage);
      final coverBefore = tester.getSize(
        find
            .descendant(
              of: find.byType(AlbumStage),
              matching: find.byType(Artwork),
            )
            .first,
      );
      final target = tester.getCenter(stage);
      final gesture = await tester.startGesture(target);
      await tester.pump(const Duration(milliseconds: 550));
      await gesture.moveBy(const Offset(60, 40));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getSize(stage), before);
      expect(
        tester.getSize(
          find
              .descendant(
                of: find.byType(AlbumStage),
                matching: find.byType(Artwork),
              )
              .first,
        ),
        coverBefore,
      );
      expect(
        tester.widget<Transform>(transform).transform.entry(0, 0),
        greaterThan(.7),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      await f.screenshot(tester, 'ecosystem-polish-$runId-cover-390-short');
      expect(tester.takeException(), isNull);
      await f.clean(tester, c);
      done(
        'Intended cover size and generous fixed scene with short-window scrolling',
      );
    },
  );
  testWidgets(
    'Pending selection is immediate and error resets transport before source ACK',
    (tester) async {
      final c = (await tester.runAsync(details.pendingController))!;
      final api = c.api as details.DetailsPlaybackApi;
      await f.viewport(tester, const Size(390, 850));
      await tester.pumpWidget(
        details.liveShell(c, PlayerPage(controller: c, onMore: (_) {})),
      );
      await tester.pumpAndSettle();
      late Future<Object?> task;
      await tester.runAsync(() async {
        task = c
            .play(lifecycle.external('new'))
            .then<Object?>((_) => null, onError: (Object e) => e);
      });
      await tester.pump();
      expect(c.transportPending, true);
      expect(c.audio.viewCurrent?.id, 'new');
      expect(c.canSeek, false);
      expect(
        find.byKey(const Key('playback-loading-indicator')),
        findsOneWidget,
      );
      api.pending!.completeError(
        const WaveException('isolated source failure'),
      );
      expect(await tester.runAsync(() => task), isA<WaveException>());
      await tester.pumpAndSettle();
      expect(c.transportPending, false);
      expect(c.trackLoading, false);
      expect(c.audio.viewCurrent?.id, 'old');
      expect(tester.takeException(), isNull);
      await f.clean(tester, c);
      done(
        'Immediate actual pending source and failure rollback without stale spinner',
      );
    },
  );
  testWidgets('Actual long-press queue drag moves the stored queue', (
    tester,
  ) async {
    final c = (await tester.runAsync(a.makeController))!;
    await f.viewport(tester, const Size(390, 850));
    await tester.pumpWidget(
      a.shell(c, QueuePanel(controller: c, onMore: (_) {})),
    );
    await tester.pumpAndSettle();
    final handle = find.byType(ReorderableDelayedDragStartListener).at(2);
    final first = tester.getCenter(find.byKey(const Key('queue-cover-own-0')));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, -70));
    await tester.pump(const Duration(milliseconds: 250));
    await gesture.moveTo(Offset(tester.getCenter(handle).dx, first.dy - 40));
    await tester.pump(const Duration(milliseconds: 350));
    await f.screenshot(tester, 'ecosystem-polish-$runId-drag-active');
    await gesture.up();
    await tester.pumpAndSettle();
    expect(c.audio.viewTracks.map((track) => track.id).toList(), [
      'own-0',
      'own-2',
      'own-1',
    ]);
    expect(tester.takeException(), isNull);
    await f.clean(tester, c);
    done('Actual touch/mouse long-press reorder persists queue order');
  });
  testWidgets('Tiny waveform animates only while playing and visible', (
    tester,
  ) async {
    final c = (await tester.runAsync(a.makeController))!;
    await tester.runAsync(() => c.customize({'reducedMotion': false}));
    Widget shell(bool playing, bool visible) => RepaintBoundary(
      key: const Key('capture'),
      child: MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(disableAnimations: false),
            child: TickerMode(
              enabled: visible,
              child: ListeningWave(playing: playing, size: 40),
            ),
          ),
        ),
      ),
    );
    Future<String> pixels() async => (await tester.runAsync(() async {
      final boundary =
          tester.element(find.byKey(const Key('capture'))).findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData();
      image.dispose();
      return base64Encode(data!.buffer.asUint8List());
    }))!;
    await tester.pumpWidget(shell(true, true));
    await tester.pump(const Duration(milliseconds: 100));
    final before = await pixels();
    await tester.pump(const Duration(milliseconds: 400));
    expect(await pixels(), isNot(before));
    await tester.pumpWidget(shell(false, true));
    await tester.pump(const Duration(milliseconds: 100));
    final paused = await pixels();
    await tester.pump(const Duration(milliseconds: 500));
    expect(await pixels(), paused);
    await tester.pumpWidget(shell(true, false));
    await tester.pump(const Duration(milliseconds: 100));
    final hidden = await pixels();
    await tester.pump(const Duration(milliseconds: 500));
    expect(await pixels(), hidden);
    expect(tester.takeException(), isNull);
    await f.clean(tester, c);
    done(
      'Actual wave pixels move during play and remain static paused/offscreen',
    );
  });
}
