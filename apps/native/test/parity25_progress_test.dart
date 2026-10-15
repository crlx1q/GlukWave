import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/ui/playback_progress.dart';
import 'package:glukwave/ui/volume_slider.dart';
import 'app_layout_test.dart' as fixture;

void main() {
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
  });
  test('physical progress is fractional, speed aware, bounded and reanchors', () {
    for (final rate in [1.0, 1.5, 2.0]) {
      final clock = ProgressPresentationClock();
      final frame = ProgressFrame(
        position: 10000,
        duration: 240000,
        playing: true,
        rate: rate,
        stamp: 1,
        horizon: 5000,
      );
      expect(clock.position(frame, 1000), 10000);
      expect(clock.position(frame, 1016), 10000 + 16 * rate);
      // Millisecond positions advance by elapsed milliseconds * playback speed.
      expect(clock.position(frame, 2000), 10000 + 1000 * rate);
      expect(clock.position(frame, 90000), 10000 + 5000 * rate);
      expect(clock.moving(frame, 90000), false);
      expect(
        clock.position(
          const ProgressFrame(
            position: 2,
            duration: 240000,
            playing: false,
            stamp: 2,
          ),
          90001,
        ),
        2,
      );
      expect(
        clock.position(
          const ProgressFrame(
            position: 239999,
            duration: 240000,
            playing: true,
            stamp: 3,
          ),
          90001,
        ),
        239999,
      );
    }
  });
  testWidgets(
    'frame painting preserves a live draft and commits one seek on release',
    (t) async {
      final updates = StreamController<void>.broadcast();
      var authority = 20.0, commits = <double>[];
      Widget host() => MaterialApp(
        home: Scaffold(
          body: SmoothProgressBuilder(
            updates: updates.stream,
            read: () => ProgressFrame(
              position: authority,
              duration: 240,
              playing: true,
              live: true,
            ),
            builder: (_, position, total) => DraftSlider(
              value: position,
              max: total,
              scope: 'track:output:account',
              onChanged: commits.add,
            ),
          ),
        ),
      );
      await t.pumpWidget(host());
      await t.pump();
      final center = t.getCenter(find.byType(Slider));
      final gesture = await t.startGesture(center);
      await gesture.moveBy(const Offset(50, 0));
      await t.pump();
      final draft = t.widget<Slider>(find.byType(Slider)).value;
      authority = 2;
      updates.add(null);
      await t.pump();
      expect(t.widget<Slider>(find.byType(Slider)).value, draft);
      expect(commits, isEmpty);
      await gesture.up();
      await t.pump();
      expect(commits, hasLength(1));
      authority = commits.single;
      updates.add(null);
      await t.pump();
      expect(t.widget<Slider>(find.byType(Slider)).value, authority);
      await t.pumpWidget(const SizedBox());
      await updates.close();
    },
  );
  testWidgets(
    'pending new selection cannot display the prior decoder time or duration',
    (t) async {
      final c = (await t.runAsync(fixture.controller))!;
      final previous = WaveTrack({
        'id': 'previous',
        'duration': 240,
        'playback': {'kind': 'youtube'},
      });
      final next = WaveTrack({
        'id': 'selected-next',
        'duration': 180,
        'playback': {'kind': 'youtube'},
      });
      c.audio.current = previous;
      c.audio.provider
        ..track = previous
        ..position = 73
        ..duration = 240
        ..ready = true
        ..playing = true;
      Widget host() => MaterialApp(
        home: PlaybackProgress(
          controller: c,
          builder: (_, position, duration) => Column(
            children: [
              Text('${position.round()}/${duration.round()}'),
              LinearProgressIndicator(
                value: duration > 0 ? position / duration : 0,
              ),
            ],
          ),
        ),
      );
      await t.pumpWidget(host());
      expect(c.audio.outputPosition.inSeconds, 73);
      expect(
        t
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        closeTo(73 / 240, .001),
      );
      c.audio.showPendingSelection(next);
      await t.pumpWidget(host());
      expect(c.audio.current?.id, previous.id);
      expect(c.audio.outputPosition.inSeconds, 73);
      expect(find.text('0/180000'), findsOneWidget);
      expect(
        t
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0,
      );
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('0/180000'), findsOneWidget);
      final sample = t
          .widget<PlaybackProgress>(find.byType(PlaybackProgress))
          .read();
      expect(sample.playing, false);
      c.audio.current = next;
      c.audio.provider
        ..track = next
        ..position = 5
        ..duration = 180;
      c.audio.showPendingSelection(null);
      await t.pumpWidget(host());
      expect(
        t
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        closeTo(5 / 180, .001),
      );
      await fixture.clean(t, c);
    },
  );
  testWidgets(
    'paused/hidden frames stop and presentation is independent of timeDilation',
    (t) async {
      var playing = true, physicalSource = 10.0, builds = 0;
      Widget host({bool enabled = true}) => MaterialApp(
        home: TickerMode(
          enabled: enabled,
          child: SmoothProgressBuilder(
            read: () => ProgressFrame(
              position: physicalSource,
              duration: 240,
              playing: playing,
              live: true,
            ),
            builder: (_, position, __) {
              builds++;
              return Text(position.toStringAsFixed(2));
            },
          ),
        ),
      );
      timeDilation = 4;
      try {
        await t.pumpWidget(host());
        await t.pump();
        physicalSource = 10.123;
        await t.pump(const Duration(milliseconds: 16));
        expect(find.text('10.12'), findsOneWidget);
        await t.pumpWidget(host(enabled: false));
        await t.pump();
        final hiddenBuilds = builds;
        await t.pump(const Duration(seconds: 1));
        expect(builds, hiddenBuilds);
        physicalSource = 30;
        playing = false;
        await t.pumpWidget(host());
        await t.pump();
        expect(find.text('30.00'), findsOneWidget);
        final pausedBuilds = builds;
        await t.pump(const Duration(seconds: 1));
        expect(builds, pausedBuilds);
        await t.pumpWidget(const SizedBox());
      } finally {
        timeDilation = 1;
      }
    },
  );
}
