import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/ui/album_stage.dart';
import 'package:glukwave/ui/motion_icons.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/widgets.dart';
import 'app_layout_test.dart' as f;
import 'audio_design_test.dart' as a;
import 'audio_lifecycle_test.dart' as lifecycle;
import 'helpers/fonts.dart';
import 'helpers/artwork_fixture.dart';

class SeekOutput extends lifecycle.NativeOutput {
  final positions = <Duration>[];
  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (position != null) positions.add(position);
  }

  @override
  Future<void> stop() async {
    active = false;
    ready = false;
  }
}

class DetailsPlaybackApi extends lifecycle.PlaybackApi {
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) {
    if (path.endsWith('/lyrics')) return Future.value({'lines': []});
    if (path.endsWith('/comments')) return Future.value({'comments': []});
    return super.call(path, method: method, data: data, query: query);
  }
}

Future<f.LayoutController> pendingController() async {
  SharedPreferences.setMockInitialValues({});
  final api = DetailsPlaybackApi()..pending = Completer<Json>();
  final output = SeekOutput();
  final audio = WaveAudioHandler(
    api,
    lifecycle.PlaybackCache(api),
    output: output,
  )..autoCache = false;
  final c = f.LayoutController(api, audio.cache, audio);
  c.preferences = await SharedPreferences.getInstance();
  await c.restoreCustomizationScope();
  await c.customize({'reducedMotion': true, 'language': 'en'});
  c.loading = false;
  audio.current = lifecycle.external('old', kind: 'audio');
  return c;
}

Widget liveShell(f.LayoutController c, Widget child, {String mode = 'dark'}) =>
    AnimatedBuilder(
      animation: c,
      builder: (_, _) => a.shell(c, child, mode: mode),
    );

void expectContained(WidgetTester tester) {
  final stage = tester.getRect(find.byKey(const Key('album-stage-bounds')));
  final surface = tester.getRect(find.byKey(const Key('player-cover-gesture')));
  expect(stage.center.dx, closeTo(surface.center.dx, .1));
  final all = find.descendant(
    of: find.byType(AlbumStage),
    matching: find.byType(Artwork),
  );
  for (final element in all.evaluate()) {
    final box = element.findRenderObject()! as RenderBox;
    final rect = Offset.zero & box.size;
    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      final point = box.localToGlobal(corner);
      expect(point.dx, inInclusiveRange(stage.left - .1, stage.right + .1));
      expect(point.dy, inInclusiveRange(stage.top - .1, stage.bottom + .1));
    }
  }
  expect(stage.left, greaterThanOrEqualTo(0));
  expect(stage.right, lessThanOrEqualTo(tester.view.physicalSize.width));
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
    clearArtworkFixture();
    await File('../../work/qa/player-details-native-proof.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'status': cases.length == 18 ? 'PASSED' : 'INCOMPLETE',
        'runId': runId,
        'boundary':
            'Actual native widgets, live controller settings and real audio source lifecycle with isolated native output. No physical installation, owner data or hosted writes.',
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
                          .startsWith('native-player-details-$runId-') &&
                      file.path.endsWith('.png'),
                )
                .map((file) => file.path.split(Platform.pathSeparator).last)
                .toList()
              ..sort(),
      }),
    );
  });
  for (final mode in ['dark', 'amoled', 'light']) {
    testWidgets(
      'Live EQ outer, chart, speed and preset radius; quiet keyboard focus $mode',
      (tester) async {
        final c = (await tester.runAsync(a.makeController))!;
        await f.viewport(tester, const Size(390, 850));
        await tester.pumpWidget(
          liveShell(
            c,
            MiniPlayer(controller: c, onOpen: () {}),
            mode: mode,
          ),
        );
        await tester.pumpAndSettle();
        // Open from a real route; changing settings keeps that same popup open.
        final context = tester.element(find.byType(MiniPlayer));
        unawaited(showPlayerEqualizer(context, c));
        await tester.pumpAndSettle();
        for (final radius in [8.0, 24.0, 38.0]) {
          await tester.runAsync(
            () => c.customize({
              'appearance': {'radius': radius},
            }),
          );
          await tester.pumpAndSettle();
          final popup = tester.widget<Material>(
            find.byKey(const Key('player-eq-popover')),
          );
          final shape = popup.shape! as RoundedRectangleBorder;
          expect(
            shape.borderRadius.resolve(TextDirection.ltr).topLeft.x,
            closeTo(radius, .01),
          );
          for (final key in ['compact-eq-chart', 'compact-eq-speed-surface']) {
            final container = tester.widget<Container>(find.byKey(Key(key)));
            final decoration = container.decoration! as BoxDecoration;
            expect(
              decoration.borderRadius!.resolve(TextDirection.ltr).topLeft.x,
              closeTo(radius * .75, .01),
            );
            if (key == 'compact-eq-chart') {
              expect(container.clipBehavior, Clip.antiAlias);
            }
          }
          final preset = tester.widget<OutlinedButton>(
            find.byKey(const Key('compact-eq-presets')),
          );
          final presetShape =
              preset.style!.shape!.resolve({})! as RoundedRectangleBorder;
          expect(
            presetShape.borderRadius.resolve(TextDirection.ltr).topLeft.x,
            closeTo(radius * .75, .01),
          );
          expect(
            preset.style!.side!.resolve({WidgetState.focused})!.color,
            waveVisuals(
              tester.element(find.byKey(const Key('compact-eq-presets'))),
            ).line,
          );
          await f.screenshot(
            tester,
            'player-details-$runId-$mode-eq-${radius.toInt()}',
          );
        }
        await tester.tap(find.byKey(const Key('compact-eq-presets')));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        final item = tester.widget<MenuItemButton>(
          find.byKey(const Key('compact-eq-preset-warm')),
        );
        expect(
          item.style!.side!.resolve({WidgetState.focused}),
          BorderSide.none,
        );
        expect(
          item.style!.backgroundColor!.resolve({WidgetState.focused}),
          isNot(Colors.transparent),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        cases.add({
          'name': '$mode live radius 8/24/38 and quiet focus',
          'passed': true,
        });
        await f.clean(tester, c);
      },
    );
    for (final viewport in [
      const Size(1440, 950),
      const Size(1440, 600),
      const Size(390, 700),
      const Size(320, 568),
    ]) {
      testWidgets('Entire native cover at125% $mode $viewport flat/3D/extreme tilt', (
        tester,
      ) async {
        await tester.runAsync(installArtworkFixture);
        try {
          final c = (await tester.runAsync(a.makeController))!;
          c.tracks = [
            for (final track in c.tracks)
              WaveTrack({
                ...track.json,
                'artwork': 'https://fixture.invalid/coast.jpg',
              }),
          ];
          c.audio.current = c.tracks.first;
          c.audio.tracks = c.tracks;
          await f.viewport(tester, viewport);
          await tester.pumpWidget(
            liveShell(
              c,
              PlayerPage(controller: c, onMore: (_) {}),
              mode: mode,
            ),
          );
          for (final threeD in [false, true]) {
            await tester.runAsync(
              () => c.customize({
                'appearance': {'cover3d': threeD},
              }),
            );
            await tester.pumpAndSettle();
            await tester.ensureVisible(
              find.byKey(const Key('album-stage-bounds')),
            );
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 35)),
            );
            await tester.pumpAndSettle();
            expectContained(tester);
            final sleeve = tester.widget<Container>(
              find.byKey(const Key('album-front-sleeve')),
            );
            expect((sleeve.decoration! as BoxDecoration).color!.a, 1);
            expect(
              tester
                  .widgetList<RawImage>(
                    find.descendant(
                      of: find.byType(AlbumStage),
                      matching: find.byType(RawImage),
                    ),
                  )
                  .any((image) => image.image != null),
              true,
              reason:
                  'Full captures contain decoded project artwork, not a placeholder.',
            );
            if (threeD) {
              final gesture = await tester.startGesture(
                tester.getCenter(find.byKey(const Key('album-3d'))),
              );
              await tester.pump(const Duration(milliseconds: 650));
              await gesture.moveBy(const Offset(450, -350));
              await tester.pump();
              expectContained(tester);
              await gesture.up();
              await tester.pumpAndSettle();
            }
            await f.screenshot(
              tester,
              'player-details-$runId-$mode-${viewport.width.toInt()}-${viewport.height.toInt()}-${threeD ? '3d' : 'flat'}-top',
            );
            final originalSize = tester.getSize(
              find.byKey(const Key('album-stage-bounds')),
            );
            await tester.drag(
              find.byKey(const Key('player-content-scroll')),
              const Offset(0, -650),
            );
            await tester.pumpAndSettle();
            final controls = tester.getRect(
              find.byKey(const Key('player-equalizer')),
            );
            expect(controls.top, greaterThanOrEqualTo(0));
            expect(controls.bottom, lessThanOrEqualTo(viewport.height));
            expect(
              tester.getSize(find.byKey(const Key('album-stage-bounds'))),
              originalSize,
            );
            await tester.tap(find.byKey(const Key('player-equalizer')));
            await tester.pumpAndSettle();
            expect(find.byKey(const Key('player-eq-popover')), findsOneWidget);
            await tester.tapAt(const Offset(5, 5));
            await tester.pumpAndSettle();
            await f.screenshot(
              tester,
              'player-details-$runId-$mode-${viewport.width.toInt()}-${viewport.height.toInt()}-${threeD ? '3d' : 'flat'}-controls',
            );
          }
          expect(tester.takeException(), isNull);
          cases.add({
            'name': '$mode $viewport entire flat/3D art and touch tilt',
            'passed': true,
          });
          await f.clean(tester, c);
        } finally {
          clearArtworkFixture();
        }
      });
    }
  }
  testWidgets(
    'Persisted compact EQ highlight survives closing and toggles off with DSP',
    (tester) async {
      final c = (await tester.runAsync(a.makeController))!;
      await f.viewport(tester, const Size(1280, 850));
      await tester.pumpWidget(
        liveShell(c, MiniPlayer(controller: c, onOpen: () {})),
      );
      await tester.pumpAndSettle();
      IconButton eq() =>
          tester.widget<IconButton>(find.byKey(const Key('mini-equalizer')));
      expect(eq().isSelected, true);
      await tester.tap(find.byKey(const Key('mini-equalizer')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-eq-popover')), findsNothing);
      expect(eq().isSelected, true);
      await tester.runAsync(
        () => c.customize({
          'equalizer': {'enabled': false},
        }),
      );
      await tester.pumpAndSettle();
      expect(eq().isSelected, false);
      expect(tester.takeException(), isNull);
      cases.add({
        'name': 'Persisted compact DSP highlight independent of popup',
        'passed': true,
      });
      await f.clean(tester, c);
    },
  );
  testWidgets(
    'Lyrics and queue use same active icon treatment and respect motion off',
    (tester) async {
      final c = (await tester.runAsync(a.makeController))!;
      await f.viewport(tester, const Size(1280, 850));
      await tester.pumpWidget(
        liveShell(c, PlayerPage(controller: c, onMore: (_) {})),
      );
      await tester.pumpAndSettle();
      for (final key in ['player-lyrics-toggle', 'player-queue-toggle']) {
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        final icon = tester.widget<WaveViewIcon>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(WaveViewIcon),
          ),
        );
        expect(icon.active, true);
        final rotation = tester.widget<AnimatedRotation>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(AnimatedRotation),
          ),
        );
        expect(
          rotation.turns,
          0,
          reason: 'Reduced-motion preferences suppress the tilt.',
        );
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      cases.add({
        'name': 'Lyrics/queue active treatment with motion disabled',
        'passed': true,
      });
      await f.clean(tester, c);
    },
  );
  testWidgets(
    'Real resolving success/error/cancel resets loading; user seeks blocked, internal sync preserved',
    (tester) async {
      final c = (await tester.runAsync(pendingController))!;
      final api = c.api as DetailsPlaybackApi,
          audio = c.audio,
          output = audio.player as SeekOutput;
      await f.viewport(tester, const Size(390, 850));
      await tester.pumpWidget(
        liveShell(c, PlayerPage(controller: c, onMore: (_) {})),
      );
      await tester.pumpAndSettle();
      late Future<Object?> operation;
      Future<void> resolve(String id) async {
        await tester.runAsync(() async {
          operation = audio
              .playTrack(lifecycle.external(id))
              .then<Object?>((_) => null, onError: (Object error) => error);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
      }

      await resolve('new');
      await tester.pumpAndSettle();
      expect(audio.trackLoading, true);
      expect(
        tester.widget<Slider>(find.byKey(const Key('player-seek'))).onChanged,
        isNull,
      );
      expect(
        find.byKey(const Key('playback-loading-indicator')),
        findsOneWidget,
      );
      await audio.seek(const Duration(seconds: 22));
      await c.transport('seek', {'position': 23});
      expect(output.positions, isEmpty);
      await audio.localCommand('seek', {'position': 24});
      expect(output.positions, [const Duration(seconds: 24)]);
      await f.screenshot(tester, 'player-details-$runId-loading');
      api.pending!.complete({'playback': api.descriptor});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(await tester.runAsync(() => operation), isNull);
      await tester.pumpAndSettle();
      expect(audio.trackLoading, false);
      expect(find.byKey(const Key('playback-loading-indicator')), findsNothing);
      expect(
        tester.widget<Slider>(find.byKey(const Key('player-seek'))).onChanged,
        isNotNull,
      );
      await tester.runAsync(() async => api.pending = Completer<Json>());
      await resolve('failure');
      await tester.pump();
      api.pending!.completeError(WaveException('Isolated unavailable source'));
      expect(await tester.runAsync(() => operation), isA<WaveException>());
      await tester.pumpAndSettle();
      expect(audio.trackLoading, false);
      await tester.runAsync(() async => api.pending = Completer<Json>());
      await resolve('cancelled');
      await tester.pumpAndSettle();
      expect(audio.trackLoading, true);
      audio.cancelPendingLoad();
      await tester.pumpAndSettle();
      expect(audio.trackLoading, false);
      expect(find.byKey(const Key('playback-loading-indicator')), findsNothing);
      api.pending!.complete({'playback': api.descriptor});
      await tester.runAsync(() => operation);
      expect(audio.current?.id, 'new');
      expect(tester.takeException(), isNull);
      await f.clean(tester, c);
      cases.add({
        'name':
            'Real source lifecycle, guarded user seek and unblocked internal sync',
        'passed': true,
      });
    },
  );
}
