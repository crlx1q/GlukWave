import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/appearance.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/l10n/wave_localizations.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/ui/motion_icons.dart';
import 'package:glukwave/ui/physical_wave_clock.dart';
import 'package:flutter/scheduler.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/theme.dart';
import 'app_layout_test.dart' as f;
import 'audio_lifecycle_test.dart' as lifecycle;
import 'player_details_test.dart' as details;
import 'helpers/fonts.dart';

class BufferingOutput extends details.SeekOutput {
  final events = StreamController<PlaybackEvent>.broadcast(sync: true);
  ProcessingState? phase;
  @override
  ProcessingState get processingState => phase ?? super.processingState;
  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;
  void transition(ProcessingState value) {
    phase = value;
    processing.add(value);
    states.add(PlayerState(playing, value));
    events.add(PlaybackEvent(processingState: value));
  }

  @override
  Future<void> dispose() async {
    await events.close();
    await super.dispose();
  }
}

Widget shell(
  Widget child, {
  double speed = 1,
  bool reduced = false,
  bool disabled = false,
  bool tickers = true,
  String mode = 'dark',
}) => RepaintBoundary(
  key: const Key('capture'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildWaveTheme(
      WaveCustomization(
        theme: mode,
        reducedMotion: reduced,
        appearance: WaveAppearance(speed: speed),
      ),
      mode == 'light' ? Brightness.light : Brightness.dark,
    ),
    locale: const Locale('en'),
    supportedLocales: WaveStrings.supportedLocales,
    localizationsDelegates: WaveStrings.delegates,
    builder: (context, page) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: disabled),
      child: TickerMode(enabled: tickers, child: page!),
    ),
    home: Scaffold(body: Center(child: child)),
  ),
);

Widget icon({bool loading = true, bool playing = false}) => RepaintBoundary(
  key: const Key('vector-icon-capture'),
  child: SizedBox.square(
    dimension: 56,
    child: Center(
      child: IconTheme(
        data: const IconThemeData(color: Color(0xfff2b88c)),
        child: WavePlaybackIcon(playing: playing, loading: loading, size: 32),
      ),
    ),
  ),
);

Future<Uint8List> pixels(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final boundary =
          tester
                  .element(find.byKey(const Key('vector-icon-capture')))
                  .findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final value = Uint8List.fromList(bytes!.buffer.asUint8List());
      image.dispose();
      return value;
    }))!;

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
    await File('../../work/qa/playback-vector-native-proof.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'status': cases.length == 4 ? 'PASSED' : 'INCOMPLETE',
        'runId': runId,
        'boundary':
            'Actual shared playback vector and native audio lifecycle through isolated output; rasterized animation frames, accessibility, speed, reduced motion and lifecycle. No physical sound or hosted writes.',
        'cases': cases,
        'screenshots':
            Directory('../../work/qa')
                .listSync()
                .whereType<File>()
                .where(
                  (file) =>
                      file.path
                          .split(Platform.pathSeparator)
                          .last
                          .startsWith('native-playback-vector-$runId-') &&
                      file.path.endsWith('.png'),
                )
                .map((file) => file.path.split(Platform.pathSeparator).last)
                .toList()
              ..sort(),
      }),
    );
  });

  testWidgets(
    'Shared vector gently enters/exits real Play/Pause with unchanged footprint, inherited ink and semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await f.viewport(tester, const Size(320, 180));
      await tester.pumpWidget(shell(icon(loading: false)));
      await tester.pumpAndSettle();
      final playElement = tester.element(find.byType(WavePlayPauseIcon));
      final play = await pixels(tester);
      expect(find.byKey(const Key('playback-loading-indicator')), findsNothing);
      await tester.pumpWidget(shell(icon()));
      await tester.pump(const Duration(milliseconds: 110));
      final transition = await pixels(tester);
      final fades = tester.widgetList<FadeTransition>(
        find.byType(FadeTransition),
      );
      expect(
        fades.any((fade) => fade.opacity.value > 0 && fade.opacity.value < 1),
        true,
      );
      expect(transition, isNot(orderedEquals(play)));
      expect(tester.element(find.byType(WavePlayPauseIcon)), same(playElement));
      await f.screenshot(tester, 'playback-vector-$runId-entry');
      await tester.pump(const Duration(milliseconds: 220));
      final waveA = await pixels(tester);
      await f.screenshot(tester, 'playback-vector-$runId-frame-a');
      await tester.pump(const Duration(milliseconds: 420));
      final waveB = await pixels(tester);
      await f.screenshot(tester, 'playback-vector-$runId-frame-b');
      expect(waveB, isNot(orderedEquals(waveA)));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester.getSize(find.byType(WavePlaybackIcon)),
        const Size.square(32),
      );
      expect(
        tester.widget<AnimatedIcon>(find.byType(AnimatedIcon)).color,
        const Color(0xfff2b88c),
      );
      expect(find.bySemanticsLabel('Loading audio'), findsOneWidget);
      await tester.pumpWidget(shell(icon(loading: false, playing: true)));
      await tester.pump(const Duration(milliseconds: 110));
      expect(find.byKey(const Key('playback-loading-indicator')), findsNothing);
      final exit = await pixels(tester);
      await tester.pump(const Duration(milliseconds: 300));
      final pause = await pixels(tester);
      expect(exit, isNot(orderedEquals(pause)));
      expect(pause, isNot(orderedEquals(play)));
      expect(tester.element(find.byType(WavePlayPauseIcon)), same(playElement));
      expect(find.bySemanticsLabel('Loading audio'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
      semantics.dispose();
      await tester.binding.setSurfaceSize(null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      expect(tester.takeException(), isNull);
      cases.add({
        'name':
            'Real animated wave frames and gentle retained Play/Pause transitions',
        'passed': true,
      });
    },
  );

  testWidgets(
    'Reduced motion, OS motion, hidden route and paused lifecycle are static; resume restarts and disposal cleans tickers',
    (tester) async {
      await f.viewport(tester, const Size(320, 180));
      for (final state in ['reduced', 'system', 'route']) {
        await tester.pumpWidget(
          shell(
            icon(),
            reduced: state == 'reduced',
            disabled: state == 'system',
            tickers: state != 'route',
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final first = await pixels(tester);
        await tester.pump(const Duration(milliseconds: 1600));
        expect(
          await pixels(tester),
          orderedEquals(first),
          reason: '$state disables repeated frames.',
        );
        expect(tester.binding.transientCallbackCount, 0);
        if (state == 'reduced') {
          await f.screenshot(tester, 'playback-vector-$runId-reduced-static');
        }
      }
      await tester.pumpWidget(shell(icon()));
      await tester.pump(const Duration(milliseconds: 250));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final paused = await pixels(tester);
      await tester.pump(const Duration(milliseconds: 1600));
      expect(await pixels(tester), orderedEquals(paused));
      expect(tester.binding.transientCallbackCount, 0);
      // Mounting while already paused must remain static too.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(shell(icon()));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.binding.transientCallbackCount, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      final resumed = await pixels(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(await pixels(tester), isNot(orderedEquals(resumed)));
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
      await tester.binding.setSurfaceSize(null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      expect(tester.takeException(), isNull);
      cases.add({
        'name':
            'Reduced/system/route/lifecycle static fallback, hidden mount, resume and cleanup',
        'passed': true,
      });
    },
  );

  testWidgets(
    'Appearance speed leaves the physical vector cycle and geometry unchanged',
    (tester) async {
      await f.viewport(tester, const Size(320, 180));
      Future<void> frame(double speed) async {
        await tester.pumpWidget(const SizedBox());
        timeDilation = 1 / speed;
        await tester.pumpWidget(shell(icon(), speed: speed));
        await tester.pump();
        final dynamic state = tester.state(find.byType(WavePlaybackIcon));
        final clock = state.loop as PhysicalWaveClock;
        final before = clock.watch.elapsedMicroseconds;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pump();
        expect(clock.duration, const Duration(milliseconds: 1200));
        expect(
          clock.watch.elapsedMicroseconds - before,
          greaterThanOrEqualTo(140000),
        );
        expect(
          clock.value,
          closeTo((clock.watch.elapsedMicroseconds % 1200000) / 1200000, .03),
        );
        expect(
          tester.getSize(find.byType(WavePlaybackIcon)),
          const Size.square(32),
        );
      }

      try {
        for (final speed in [.5, 1.0, 2.0]) {
          await frame(speed);
        }
      } finally {
        timeDilation = 1;
      }
      expect(
        tester.getSize(find.byType(WavePlaybackIcon)),
        const Size.square(32),
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
      await tester.binding.setSurfaceSize(null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      expect(tester.takeException(), isNull);
      cases.add({
        'name':
            'Actual elapsed time proves a fixed 1200ms cycle at .5/1/2 appearance speed without size changes',
        'passed': true,
      });
    },
  );

  testWidgets(
    'Real source resolution and active buffering drive shared vector; ready/paused/error/cancel clear it',
    (tester) async {
      final c = (await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final api = details.DetailsPlaybackApi()..pending = Completer<Json>();
        final output = BufferingOutput();
        final audio = WaveAudioHandler(
          api,
          lifecycle.PlaybackCache(api),
          output: output,
        )..autoCache = false;
        final c = f.LayoutController(api, audio.cache, audio);
        c.preferences = await SharedPreferences.getInstance();
        await c.restoreCustomizationScope();
        await c.customize({
          'language': 'en',
          'reducedMotion': false,
          'appearance': {'cover3d': false},
        });
        return c;
      }))!;
      final api = c.api as details.DetailsPlaybackApi;
      final audio = c.audio;
      final output = audio.player as BufferingOutput;
      c.loading = false;
      audio.current = lifecycle.external('old', kind: 'audio');
      await f.viewport(tester, const Size(390, 850));
      await tester.pumpWidget(
        AnimatedBuilder(
          animation: c,
          builder: (_, _) => shell(PlayerPage(controller: c, onMore: (_) {})),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('playback-loading-indicator')), findsNothing);
      late Future<Object?> operation;
      Future<void> resolve(String id) async => tester.runAsync(() async {
        operation = audio
            .playTrack(lifecycle.external(id))
            .then<Object?>((_) => null, onError: (Object error) => error);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      Future<void> transition(ProcessingState state) async =>
          tester.runAsync(() async {
            output.transition(state);
            await Future<void>.delayed(const Duration(milliseconds: 20));
          });
      await resolve('resolved');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      expect(c.trackLoading, true);
      expect(
        find.byKey(const Key('playback-loading-indicator')),
        findsOneWidget,
      );
      await f.screenshot(tester, 'playback-vector-$runId-full-pending');
      api.pending!.complete({'playback': api.descriptor});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(await tester.runAsync(() => operation), isNull);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(c.trackLoading, false);
      expect(find.byKey(const Key('playback-loading-indicator')), findsNothing);
      await transition(ProcessingState.buffering);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      expect(c.trackLoading, true);
      expect(
        find.byKey(const Key('playback-loading-indicator')),
        findsOneWidget,
      );
      await f.screenshot(tester, 'playback-vector-$runId-full-buffering');
      await transition(ProcessingState.ready);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(c.trackLoading, false);
      expect(find.byKey(const Key('playback-loading-indicator')), findsNothing);
      await output.pause();
      await transition(ProcessingState.buffering);
      await tester.pump();
      expect(
        c.trackLoading,
        false,
        reason: 'Paused output is not an active buffer wait.',
      );
      await tester.runAsync(() async => api.pending = Completer<Json>());
      await resolve('failed');
      await tester.pump();
      await tester.runAsync(
        () async => api.pending!.completeError(StateError('Isolated failure')),
      );
      expect(await tester.runAsync(() => operation), isA<StateError>());
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(const Key('playback-loading-indicator')), findsNothing);
      await tester.runAsync(() async => api.pending = Completer<Json>());
      await resolve('cancelled');
      await tester.pump();
      expect(c.trackLoading, true);
      audio.cancelPendingLoad();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(const Key('playback-loading-indicator')), findsNothing);
      await tester.runAsync(
        () async => api.pending!.complete({'playback': api.descriptor}),
      );
      await tester.runAsync(() => operation);
      expect(audio.current?.id, 'resolved');
      await f.clean(tester, c);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      cases.add({
        'name':
            'Actual full player resolution, buffering, ready, pause, error and cancellation',
        'passed': true,
      });
    },
  );
}
