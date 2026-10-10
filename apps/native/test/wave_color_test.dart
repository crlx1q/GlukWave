import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/appearance.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/ui/silk_wave.dart';
import 'package:glukwave/ui/wave_colors.dart';
import 'package:glukwave/ui/theme.dart';
import 'package:glukwave/ui/home_widget_previews.dart';
import 'package:glukwave/l10n/home_widget_strings.dart';
import 'helpers/fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  final runId = DateTime.now().millisecondsSinceEpoch;
  test(
    'Native eight colour batches match real web palette in six colour/theme combinations',
    () async {
      final entries =
          jsonDecode(
                await File(
                  'test/fixtures/silk-colors-parity.json',
                ).readAsString(),
              )
              as List;
      for (final entry in entries) {
        final palette = SilkPalette.from(
          hexColor(entry['tint']),
          hexColor(entry['background']),
        );
        for (var i = 0; i < 8; i++) {
          final c = palette.atDepth((i + .5) / 8),
              expected = entry['bands'][i] as List;
          for (final component in [
            (c.r, expected[0]),
            (c.g, expected[1]),
            (c.b, expected[2]),
          ]) {
            expect(
              component.$1,
              closeTo(component.$2, 1 / 255),
              reason: '${entry['theme']} ${entry['tint']} band$i',
            );
          }
        }
      }
    },
  );
  test(
    'Actual native folded renderer stays transparent outside field; colour does not move geometry; inputs move field',
    () async {
      Future<ui.Image> render(
        Color accent, {
        double phase = 13,
        double energy = 0,
        Offset pointer = const Offset(.5, .5),
        double active = 0,
        Offset velocity = Offset.zero,
      }) async {
        final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
        drawSilkWave(
          canvas,
          const Size(390, 270),
          phase,
          energy,
          accent,
          pointer,
          active,
          background: Colors.black,
          velocity: velocity,
        );
        final picture = recorder.endRecording(),
            image = await picture.toImage(390, 270);
        picture.dispose();
        return image;
      }

      Future<List<int>> alpha(ui.Image image) async {
        final rgba = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        return [
          for (var i = 3; i < rgba.lengthInBytes; i += 4) rgba.getUint8(i),
        ];
      }

      final copper = await render(const Color(0xffd98c58)),
          blue = await render(const Color(0xff579fea));
      final original = await alpha(copper), other = await alpha(blue);
      expect(
        original,
        other,
        reason: 'Colour iteration preserves every point/alpha/edge',
      );
      expect(original.take(390 * 40).every((a) => a == 0), isTrue);
      expect(original.where((a) => a > 0).length, greaterThan(3000));
      for (final image in [
        await render(const Color(0xffd98c58), phase: 14),
        await render(const Color(0xffd98c58), energy: .7),
        await render(
          const Color(0xffd98c58),
          pointer: const Offset(.3, .52),
          active: 1,
          velocity: const Offset(.6, -.2),
        ),
      ]) {
        expect(await alpha(image), isNot(equals(original)));
        image.dispose();
      }
      final bytes = (await copper.toByteData(format: ui.ImageByteFormat.png))!;
      await File(
        '../../work/qa/wave-native-$runId-copper.png',
      ).writeAsBytes(bytes.buffer.asUint8List());
      copper.dispose();
      blue.dispose();
    },
  );
  test(
    'Actual native field screenshots cover light dark AMOLED, both accents and widths',
    () async {
      final shots = <Map<String, dynamic>>[];
      for (final theme in {
        'light': const Color(0xffefede3),
        'dark': const Color(0xff141517),
        'amoled': Colors.black,
      }.entries) {
        for (final accent in {
          'copper': const Color(0xffd98c58),
          'blue': const Color(0xff579fea),
        }.entries) {
          for (final width in [390, 900]) {
            final recorder = ui.PictureRecorder(),
                canvas = Canvas(recorder),
                size = Size(width.toDouble(), 270);
            canvas.drawRect(Offset.zero & size, Paint()..color = theme.value);
            drawSilkWave(
              canvas,
              size,
              13,
              0,
              accent.value,
              const Offset(.5, .5),
              0,
              background: theme.value,
            );
            final picture = recorder.endRecording(),
                image = await picture.toImage(width, 270),
                png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
            final file =
                '../../work/qa/wave-native-$runId-${theme.key}-${accent.key}-$width.png';
            await File(file).writeAsBytes(png.buffer.asUint8List());
            image.dispose();
            picture.dispose();
            shots.add({
              'theme': theme.key,
              'accent': accent.key,
              'width': width,
              'file': file,
            });
          }
        }
      }
      await File('../../work/qa/wave-color-native-proof.json').writeAsString(
        jsonEncode({
          'passed': true,
          'scope':
              'Actual native renderer, fixed original field inputs, no physical device checks',
          'screenshots': shots,
        }),
      );
    },
  );
  testWidgets(
    'Widget previews use actual metadata, responsive controls, all states and six locales125 without overflow',
    (tester) async {
      final track = WaveTrack({
        'id': 'qa',
        'title': 'A distant evening — original verification recording',
        'artist': 'Wave verification collective',
      });
      for (final theme in ['light', 'dark', 'amoled']) {
        for (final width in [180.0, 320.0]) {
          for (final large in [false, true]) {
            for (final locale in ['en', 'ru', 'kk', 'uk', 'de', 'es']) {
              final index = [
                'en',
                'ru',
                'kk',
                'uk',
                'de',
                'es',
              ].indexOf(locale);
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = const Size(480, 700);
              await tester.binding.setSurfaceSize(const Size(480, 700));
              final customization = const WaveCustomization().merge({
                'theme': theme,
                'appearance': {
                  theme: {'accent': '#d98c58'},
                },
              });
              final labels = HomeWidgetPreviewLabels(
                text: (key) => homeWidgetStrings[key]?[index] ?? key,
              );
              await tester.pumpWidget(
                MaterialApp(
                  theme: buildWaveTheme(
                    customization,
                    theme == 'light' ? Brightness.light : Brightness.dark,
                  ),
                  home: Scaffold(
                    body: MediaQuery(
                      data: const MediaQueryData(
                        textScaler: TextScaler.linear(1.25),
                      ),
                      child: Center(
                        child: RepaintBoundary(
                          key: const Key('widget-preview'),
                          child: SizedBox(
                            width: width,
                            child: HomeWidgetPreviewPanel(
                              large: large,
                              track: track,
                              artwork: Image.asset(
                                'assets/forest.jpg',
                                fit: BoxFit.cover,
                              ),
                              playing: false,
                              loading: true,
                              labels: labels,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: '$theme $width $large $locale',
              );
              expect(find.text(track.title), findsOneWidget);
              expect(find.text('GLUKWAVE'), findsNothing);
              expect(
                find.text(homeWidgetStrings['loading']![index]),
                large ? findsOneWidget : findsNothing,
              );
              expect(
                tester.getSize(find.byType(HomeWidgetPreviewPanel)).height,
                large ? 200 : 80,
              );
              if (locale == 'en' && width == 320) {
                await tester.runAsync(() async {
                  final boundary = tester.renderObject<RenderRepaintBoundary>(
                        find.byKey(const Key('widget-preview')),
                      ),
                      image = await boundary.toImage(pixelRatio: 2);
                  final png = (await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  ))!;
                  await File(
                    '../../work/qa/widget-preview-$runId-$theme-${large ? 'wave' : 'player'}.png',
                  ).writeAsBytes(png.buffer.asUint8List());
                  image.dispose();
                });
              }
            }
          }
        }
      }
      final labels = HomeWidgetPreviewLabels(
        text: (key) => homeWidgetStrings[key]![0],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: HomeWidgetPreviewPanel(
                  large: true,
                  height: 220,
                  track: track,
                  labels: labels,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('GLUKWAVE'), findsOneWidget);
      expect(tester.getSize(find.byType(HomeWidgetPreviewPanel)).height, 220);
      for (final signedIn in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            home: HomeWidgetPreviewPanel(
              large: true,
              signedIn: signedIn,
              labels: labels,
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          find.text(labels.text(signedIn ? 'empty' : 'signedOut')),
          findsOneWidget,
        );
      }
      await tester.pumpWidget(const SizedBox());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.binding.setSurfaceSize(null);
    },
  );
}
