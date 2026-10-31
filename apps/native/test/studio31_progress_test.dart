import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/desktop_player.dart';
import 'package:glukwave/ui/playback_progress.dart';
import 'package:glukwave/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_layout_test.dart' as f;
import 'audio_design_test.dart' as a;

class SampledAudio extends a.UiAudio {
  double coarse = 10, rate = 1;
  bool moving = true, ready = true, remoteSample = false;
  final updates = StreamController<Duration>.broadcast();
  SampledAudio(super.api, super.cache);
  @override
  Duration get outputPosition =>
      Duration(milliseconds: (coarse * 1000).round());
  @override
  Duration get position => outputPosition;
  @override
  Duration? get duration => const Duration(seconds: 240);
  @override
  bool get sourceReady => ready;
  @override
  bool get playing => moving;
  @override
  bool get remote => remoteSample;
  @override
  bool get trackLoading => false;
  @override
  Stream<Duration> get positionStream => updates.stream;
  @override
  Future<void> release() async {
    await updates.close();
    await super.release();
  }
}

Future<(f.LayoutController, SampledAudio, Directory)> fixture() async {
  SharedPreferences.setMockInitialValues({});
  final api = f.LayoutApi(),
      support = await Directory.systemTemp.createTemp('studio-progress-'),
      cache = MusicCache(api, supportDirectory: () async => support),
      audio = SampledAudio(api, cache),
      c = f.LayoutController(api, cache, audio);
  c.preferences = await SharedPreferences.getInstance();
  await c.restoreCustomizationScope();
  await c.customize({
    'reducedMotion': false,
    'theme': 'dark',
    'language': 'en',
  });
  c.loading = false;
  c.online = true;
  audio.current = WaveTrack({
    'id': 'actual',
    'title': 'Quiet coast',
    'artist': 'Studio',
    'source': 'local',
    'duration': 240,
    'playback': {'kind': 'audio', 'url': '/silent.wav'},
  });
  audio.tracks = [audio.current!];
  c.tracks = audio.tracks;
  return (c, audio, support);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        ),
  );
  test(
    'Coarse source samples interpolate fractional rate, cap stale stalls, pause and seek immediately',
    () {
      for (final rate in [1.0, 1.5, 2.0]) {
        final clock = ProgressPresentationClock(),
            frame = ProgressFrame(
              position: 10000,
              duration: 240000,
              playing: true,
              rate: rate,
              horizon: 750,
              scope: 'one',
            );
        expect(clock.position(frame, 0), 10000);
        expect(clock.position(frame, 16), 10000 + 16 * rate);
        expect(clock.position(frame, 33), 10000 + 33 * rate);
        expect(clock.position(frame, 9999), 10000 + 750 * rate);
        expect(clock.moving(frame, 9999), false);
        expect(
          clock.position(
            const ProgressFrame(
              position: 100,
              duration: 240000,
              playing: false,
              scope: 'one',
            ),
            10000,
          ),
          100,
        );
        expect(
          clock.position(
            const ProgressFrame(
              position: 0,
              duration: 180000,
              playing: true,
              scope: 'two',
            ),
            10001,
          ),
          0,
        );
      }
    },
  );
  testWidgets(
    'Remote rendering bridges10second checkpoints and bounds stale offline pause and loading states',
    (t) async {
      final data = (await t.runAsync(fixture))!, c = data.$1, audio = data.$2;
      var physical = 0;
      try {
        audio.remoteSample = true;
        c.connected = true;
        void checkpoint(int seconds, int stamp) {
          audio.playbackState.add(
            PlaybackState(
              updatePosition: Duration(seconds: seconds),
              updateTime: DateTime.fromMillisecondsSinceEpoch(stamp),
              playing: audio.moving,
            ),
          );
          audio.updates.add(Duration(seconds: seconds));
        }

        checkpoint(10, 1000);
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = const Size(390, 900);
        await t.binding.setSurfaceSize(const Size(390, 900));
        await t.pumpWidget(
          MaterialApp(
            theme: buildWaveTheme(c.customization, Brightness.dark),
            home: ProgressTimeSource(
              milliseconds: () => physical,
              child: Scaffold(
                body: PlaybackProgress(
                  controller: c,
                  builder: (_, position, total) =>
                      LinearProgressIndicator(value: position / total),
                ),
              ),
            ),
          ),
        );
        await t.pump();
        double rendered() =>
            t
                .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator),
                )
                .value! *
            240000;
        expect(rendered(), 10000);
        for (final time in [6000, 9900]) {
          physical = time;
          await t.pump(const Duration(milliseconds: 16));
          expect(
            rendered(),
            10000 + time,
            reason: 'Must keep moving beyond the old5s limit',
          );
        }
        physical = 10000;
        checkpoint(20, 11000);
        await t.pump();
        await t.pump();
        expect(rendered(), 20000);
        physical = 16000;
        await t.pump(const Duration(milliseconds: 16));
        expect(rendered(), 26000);
        physical = 22001;
        await t.pump(const Duration(milliseconds: 16));
        final stale = rendered();
        expect(stale, 32000);
        physical = 26000;
        await t.pump(const Duration(milliseconds: 33));
        expect(
          rendered(),
          stale,
          reason: 'Missing checkpoints must have a finite bound',
        );
        for (final condition in [
          'pause',
          'offline',
          'disconnected',
          'loading',
          'transfer',
        ]) {
          audio.moving = condition != 'pause';
          c.online = condition != 'offline';
          c.connected = condition != 'disconnected';
          c.transportPending = condition == 'loading';
          c.transferPending = condition == 'transfer' ? 'remote-output' : null;
          checkpoint(33, 30000 + physical);
          await t.pump();
          await t.pump();
          expect(
            PlaybackProgress(
              controller: c,
              builder: (_, __, ___) => const SizedBox(),
            ).read().playing,
            false,
            reason: condition,
          );
          final frozen = rendered();
          physical += 500;
          await t.pump(const Duration(milliseconds: 33));
          expect(
            rendered(),
            frozen,
            reason: 'Remote $condition must stop presentation immediately',
          );
        }
        expect(t.takeException(), isNull);
      } finally {
        await f.clean(t, c);
        await t.runAsync(() => data.$3.delete(recursive: true));
      }
    },
  );
  testWidgets(
    'Delayed healthy decoder packets stay monotonic and a confirmed small seek resets exactly',
    (t) async {
      final data = (await t.runAsync(fixture))!, c = data.$1, audio = data.$2;
      var physical = 0;
      try {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = const Size(390, 900);
        await t.binding.setSurfaceSize(const Size(390, 900));
        await t.pumpWidget(
          MaterialApp(
            theme: buildWaveTheme(c.customization, Brightness.dark),
            home: ProgressTimeSource(
              milliseconds: () => physical,
              child: Scaffold(
                body: MiniPlayer(controller: c, onOpen: () {}),
              ),
            ),
          ),
        );
        await t.pump();
        double rendered() =>
            t
                .widget<FractionallySizedBox>(
                  find.byKey(const Key('mini-card-progress')),
                )
                .widthFactor! *
            240000;
        for (var i = 1; i <= 8; i++) {
          physical = i * 250;
          await t.pump(const Duration(milliseconds: 16));
          final before = rendered();
          audio.coarse = 10 + i * .25 - .035;
          audio.updates.add(audio.outputPosition);
          await t.pump();
          await t.pump();
          expect(
            rendered(),
            greaterThanOrEqualTo(before),
            reason:
                'A healthy35ms-late sample must not reverse rendered progress',
          );
        }
        for (final delta in [.05, -.05]) {
          audio.coarse += delta;
          audio.resetProgressPresentation();
          audio.updates.add(audio.outputPosition);
          await t.pump();
          await t.pump();
          expect(
            rendered(),
            closeTo(audio.coarse * 1000, .001),
            reason: 'Explicit small seeks must bypass packet smoothing',
          );
        }
        expect(t.takeException(), isNull);
      } finally {
        await f.clean(t, c);
        await t.runAsync(() => data.$3.delete(recursive: true));
      }
    },
  );
  testWidgets(
    'Mobile collapsed, desktop dock, compact and quick windows share fractional progress between coarse notifications',
    (t) async {
      final data = (await t.runAsync(fixture))!, c = data.$1, audio = data.$2;
      var physical = 0;
      Future<void> build(double width, Widget child) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(width, 900);
        await t.binding.setSurfaceSize(Size(width, 900));
        await t.pumpWidget(
          MaterialApp(
            theme: buildWaveTheme(c.customization, Brightness.dark),
            home: ProgressTimeSource(
              milliseconds: () => physical,
              child: Scaffold(body: child),
            ),
          ),
        );
        await t.pump();
      }

      double progress() {
        final mini = find.byKey(const Key('mini-card-progress'));
        if (mini.evaluate().isNotEmpty) {
          return t.widget<FractionallySizedBox>(mini).widthFactor! * 240000;
        }
        final indicators = find.byType(LinearProgressIndicator);
        if (indicators.evaluate().isNotEmpty) {
          return t.widget<LinearProgressIndicator>(indicators.last).value! *
              240000;
        }
        final slider = find.byType(Slider).first;
        return t.widget<Slider>(slider).value;
      }

      try {
        for (final item in [
          (390.0, MiniPlayer(controller: c, onOpen: () {})),
          (1440.0, MiniPlayer(controller: c, onOpen: () {})),
          (640.0, DesktopCompactPlayer(controller: c)),
          (640.0, DesktopCompactPlayer(controller: c, quick: true)),
        ]) {
          audio.coarse = 10;
          audio.moving = true;
          audio.ready = true;
          await build(item.$1, item.$2);
          final first = progress();
          physical += 55;
          await t.pump(const Duration(milliseconds: 16));
          final next = progress();
          expect(
            next,
            greaterThan(first + 10),
            reason:
                '${item.$2.runtimeType} must advance without a decoder notification',
          );
          expect(next, lessThan(first + 700));
          audio.moving = false;
          audio.updates.add(audio.outputPosition);
          await t.pump();
          final paused = progress();
          physical += 70;
          await t.pump(const Duration(milliseconds: 40));
          expect(progress(), paused);
          audio.coarse = 42;
          audio.updates.add(audio.outputPosition);
          await t.pump();
          await t.pump();
          expect(progress(), closeTo(42000, .001));
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        }
      } finally {
        await f.clean(t, c);
        await t.runAsync(() => data.$3.delete(recursive: true));
      }
    },
  );
  testWidgets(
    'Full player on phone and desktop uses same clock and preserves a held seek draft',
    (t) async {
      final data = (await t.runAsync(fixture))!, c = data.$1, audio = data.$2;
      var physical = 0;
      try {
        for (final width in [390.0, 1440.0]) {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = Size(width, 950);
          await t.binding.setSurfaceSize(Size(width, 950));
          audio.coarse = 10;
          audio.moving = true;
          audio.ready = true;
          await t.pumpWidget(
            MaterialApp(
              theme: buildWaveTheme(c.customization, Brightness.dark),
              home: ProgressTimeSource(
                milliseconds: () => physical,
                child: Scaffold(
                  body: PlayerPage(
                    controller: c,
                    onMore: (_) {},
                    onClose: () {},
                  ),
                ),
              ),
            ),
          );
          await t.pump();
          await t.pump(const Duration(milliseconds: 300));
          final slider = find.byKey(const Key('player-seek'));
          await t.ensureVisible(slider);
          final first = t.widget<Slider>(slider).value;
          physical += 55;
          await t.pump(const Duration(milliseconds: 16));
          expect(t.widget<Slider>(slider).value, greaterThan(first + 10));
          final drag = await t.startGesture(t.getCenter(slider));
          await drag.moveBy(const Offset(20, 0));
          await t.pump();
          final draft = t.widget<Slider>(slider).value;
          audio.coarse = 2;
          audio.updates.add(audio.outputPosition);
          await t.pump();
          expect(t.widget<Slider>(slider).value, draft);
          await drag.cancel();
          await t.pumpWidget(const SizedBox());
          expect(t.takeException(), isNull);
        }
      } finally {
        await f.clean(t, c);
        await t.runAsync(() => data.$3.delete(recursive: true));
      }
    },
  );
}
