import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/artwork.dart';
import 'package:glukwave/ui/widgets.dart';
import 'app_layout_test.dart' show controller, clean;

const original = 'https://i1.sndcdn.com/artworks-000067273316-smsiqx-large.jpg';
const enlarged =
    'https://i1.sndcdn.com/artworks-000067273316-smsiqx-t500x500.jpg';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Large public SoundCloud artwork preserves metadata URL and query', () {
    expect(artworkForDisplay(original, large: true), enlarged);
    expect(artworkForDisplay(original, large: false), original);
    expect(
      artworkForDisplay('$original?cache=1#cover', large: true),
      '$enlarged?cache=1#cover',
    );
    expect(artworkForDisplay(enlarged, large: true), enlarged);
  });
  test('Unrelated or unsafe artwork URLs are never rewritten', () {
    for (final value in [
      '/api/assets/user-large.jpg',
      'http://i1.sndcdn.com/artworks-example-large.jpg',
      'https://i1.sndcdn.com.example.test/artworks-example-large.jpg',
      'https://example.test/artworks-example-large.jpg',
      'https://i1.sndcdn.com/avatars-example-large.jpg',
      'https://user@i1.sndcdn.com/artworks-example-large.jpg',
      'https://i1.sndcdn.com/artworks-example-t1000x1000.jpg',
      'not an image URL',
      '',
    ]) {
      expect(artworkForDisplay(value, large: true), value);
    }
  });
  testWidgets(
    'Failed high-resolution artwork retries the original then settles',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.ryanheise.audio_session'),
            (_) async => null,
          );
      final c = (await tester.runAsync(controller))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Artwork(controller: c, url: original, size: 256),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pumpAndSettle();
      final requested = tester.widgetList<Image>(find.byType(Image)).map((
        image,
      ) {
        final resized = image.image as ResizeImage;
        return (resized.imageProvider as NetworkImage).url;
      });
      expect(requested, orderedEquals([enlarged, original]));
      expect(find.byType(WaveSkeletonBlock), findsNothing);
      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
      await clean(tester, c);
    },
  );
}
