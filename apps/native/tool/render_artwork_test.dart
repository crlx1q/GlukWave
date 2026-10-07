// Optional evidence renderer. Supply an unmodified, externally obtained cover
// in work/qa; neither its pixels nor its track are bundled in the application.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/ui/app.dart';
import 'package:glukwave/ui/widgets.dart';
import '../test/helpers/fonts.dart';
import '../test/app_layout_test.dart'
    show controller, viewport, screenshot, clean;

const artworkUrl =
    'https://i1.sndcdn.com/artworks-000067273316-smsiqx-large.jpg';

Future<void> seedArtwork(int width, List<int> encoded) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(encoded));
  final frame = await codec.getNextFrame();
  final key = await ResizeImage(
    NetworkImage(
      width >= 96
          ? artworkUrl.replaceFirst('-large.', '-t500x500.')
          : artworkUrl,
    ),
    width: width,
  ).obtainKey(ImageConfiguration.empty);
  PaintingBinding.instance.imageCache.putIfAbsent(
    key,
    () => OneFrameImageStreamCompleter(
      Future.value(ImageInfo(image: frame.image)),
    ),
  );
  codec.dispose();
}

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
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'External SoundCloud metadata keeps its real cover and official playback at $width',
      (tester) async {
        final c = (await tester.runAsync(controller))!;
        await tester.runAsync(() async {
          await c.customize({'language': 'en'});
          final bytes = await File(
            '../../work/qa/forss-flickermood-artwork-500.jpg',
          ).readAsBytes();
          for (final target in [64, 256, 258, 324]) {
            await seedArtwork(target, bytes);
          }
        });
        c.user = WaveUser({'id': 'qa-view-only', 'username': 'QA listener'});
        c.online = true;
        final track = WaveTrack({
          'id': 'soundcloud-soundcloud:tracks:293',
          'title': 'Flickermood',
          'artist': 'Forss',
          'duration': 213.886,
          'source': 'soundcloud',
          'artwork': artworkUrl,
          'sourceUrl': 'https://soundcloud.com/forss/flickermood',
          'playback': {'kind': 'external', 'offline': false},
        });
        c.tracks = [track];
        c.history = [
          {'track': track.json},
        ];
        c.render();
        await viewport(tester, Size(width, 900));
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('capture'),
            child: GlukWaveApp(controller: c),
          ),
        );
        await tester.pumpAndSettle();
        final row = find.byType(TrackRow).first;
        await tester.ensureVisible(row);
        final menu = find.descendant(
          of: row,
          matching: find.byIcon(Icons.more_horiz_rounded),
        );
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open track and comments'));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const Key('full-player'))).size,
          Size(width, 900),
        );
        expect(find.text('Flickermood'), findsWidgets);
        expect(find.text('Forss'), findsWidgets);
        expect(find.text('Listen on SoundCloud'), findsOneWidget);
        expect(c.audio.current, isNull);
        expect(track.offline, isFalse);
        final mainCover = find.descendant(
          of: find.byKey(const Key('album-3d')),
          matching: find.byWidgetPredicate(
            (widget) => widget is Artwork && widget.size > 100,
          ),
        );
        expect(mainCover, findsOneWidget);
        final decodedCover = find.descendant(
          of: mainCover,
          matching: find.byType(RawImage),
        );
        expect(decodedCover, findsOneWidget);
        final pixels = tester.widget<RawImage>(decodedCover).image;
        expect(pixels, isNotNull);
        expect(pixels!.width, 500);
        expect(pixels.height, 500);
        expect(find.byType(WaveSkeletonBlock), findsNothing);
        expect(tester.takeException(), isNull);
        await screenshot(tester, 'v6-real-external-artwork-${width.toInt()}');
        await clean(tester, c);
      },
    );
  }
}
