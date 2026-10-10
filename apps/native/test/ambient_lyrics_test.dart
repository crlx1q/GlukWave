import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/core/lyrics.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/ui/cover_ambient.dart';
import 'package:glukwave/ui/lyrics_editor.dart';
import 'package:glukwave/ui/widgets.dart';
import 'package:glukwave/l10n/wave_localizations.dart';
import 'package:glukwave/l10n/lyrics_strings.dart';
import 'app_layout_test.dart' as f;
import 'helpers/fonts.dart';

class LyricsApi extends f.LayoutApi {
  final requests = <({String path, String method, Json data})>[];
  Completer<Json>? previewPending;
  bool failPreview = false;
  static final preview = <String, dynamic>{
    'raw': 'The evening moves slowly\nAnd the light follows home',
    'lines': [
      {'time': null, 'text': 'The evening moves slowly'},
      {'time': null, 'text': 'And the light follows home'},
    ],
    'synchronized': false,
    'source': 'genius',
    'attribution': 'Genius',
    'sourceUrl': 'https://genius.com/Glukwave-verification-lyrics',
  };
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    requests.add((path: path, method: method, data: object(data)));
    if (path.endsWith('/genius/preview')) {
      if (failPreview) {
        throw const WaveException(
          'Temporarily unavailable',
          'GENIUS_UNAVAILABLE',
          503,
        );
      }
      return previewPending?.future ?? preview;
    }
    if (path.endsWith('/genius')) return preview;
    return super.call(path, method: method, data: data, query: query);
  }
}

Future<f.LayoutController> controller() async {
  SharedPreferences.setMockInitialValues({});
  final api = LyricsApi(),
      cache = MusicCache(api),
      c = f.LayoutController(api, cache, WaveAudioHandler(api, cache));
  c.preferences = await SharedPreferences.getInstance();
  await c.restoreCustomizationScope();
  await c.customize({'reducedMotion': true, 'language': 'en'});
  c.user = WaveUser({'id': 'lyrics-qa', 'username': 'listener'});
  c.online = true;
  return c;
}

final track = WaveTrack({
  'id': 'lyrics-qa-track',
  'title': 'A quiet place',
  'artist': 'Wave verification',
  'source': 'local',
  'duration': 240,
});
Widget editor(
  f.LayoutController c, {
  String theme = 'light',
  String language = 'en',
  double scale = 1,
  bool Function()? isCurrent,
}) => RepaintBoundary(
  key: const Key('capture'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildWaveTheme(
      c.customization,
      theme == 'light' ? Brightness.light : Brightness.dark,
    ),
    locale: Locale(language),
    supportedLocales: WaveStrings.supportedLocales,
    localizationsDelegates: WaveStrings.delegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showWaveDialog(
            context: context,
            builder: (_) => LyricsEditor(
              controller: c,
              track: track,
              initialText: 'My retained draft',
              isCurrent: isCurrent ?? () => true,
              onSaved: () async {},
            ),
          ),
          child: const Text('Open editor'),
        ),
      ),
    ),
  ),
);
Future<void> openEditor(
  WidgetTester tester,
  f.LayoutController c, {
  bool Function()? isCurrent,
}) async {
  await tester.pumpWidget(editor(c, isCurrent: isCurrent));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Genius'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('genius-url')),
    'https://genius.com/Glukwave-verification-lyrics',
  );
}

String draft(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('lyrics-draft')))
    .controller!
    .text;
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
  test(
    'Genius URL validation matches HTTPS page, blocks lookalikes and escapes',
    () {
      expect(
        geniusLyricsUrl(' https://genius.com/Artist-song-lyrics?ref=x#about '),
        'https://genius.com/Artist-song-lyrics',
      );
      expect(
        geniusLyricsUrl('https://www.genius.com/Mr.-song-lyrics'),
        'https://www.genius.com/Mr.-song-lyrics',
      );
      for (final value in [
        'http://genius.com/song-lyrics',
        'https://genius.com.evil.test/song-lyrics',
        'https://person:secret@genius.com/song-lyrics',
        'https://genius.com:444/song-lyrics',
        'https://genius.com/artists/someone',
        'https://genius.com/a%2fb-lyrics',
        'https://genius.com/a%00b-lyrics',
      ]) {
        expect(geniusLyricsUrl(value), isNull, reason: value);
      }
    },
  );
  test('Genius labels are available in all six supported languages', () {
    for (final language in languageNames.keys) {
      for (final key in [
        'lyrics.geniusUrl',
        'lyrics.geniusHelp',
        'lyrics.geniusPreview',
        'lyrics.file',
        'lyrics.scopeChanged',
      ]) {
        expect(lyricsLabel(language, key), isNot(key));
      }
    }
  });
  testWidgets(
    'Preview leaves server unchanged, unchanged explicit save retains Genius source',
    (tester) async {
      final c = (await tester.runAsync(controller))!, api = c.api as LyricsApi;
      await f.viewport(tester, const Size(390, 844));
      await openEditor(tester, c);
      await tester.tap(find.byKey(const Key('genius-preview')));
      await tester.pumpAndSettle();
      expect(draft(tester), LyricsApi.preview['raw']);
      expect(api.requests.where((r) => r.method != 'GET').map((r) => r.path), [
        '/api/tracks/lyrics-qa-track/lyrics/genius/preview',
      ]);
      await tester.ensureVisible(find.byKey(const Key('lyrics-save')));
      await tester.tap(find.byKey(const Key('lyrics-save')));
      await tester.pumpAndSettle();
      expect(
        api.requests.last.path,
        '/api/tracks/lyrics-qa-track/lyrics/genius',
      );
      expect(tester.takeException(), isNull);
      await f.clean(tester, c);
    },
  );
  testWidgets(
    'Edited Genius lyrics save user text, failure and invalid links preserve draft',
    (tester) async {
      final c = (await tester.runAsync(controller))!, api = c.api as LyricsApi;
      await f.viewport(tester, const Size(390, 844));
      await openEditor(tester, c);
      api.failPreview = true;
      await tester.tap(find.byKey(const Key('genius-preview')));
      await tester.pumpAndSettle();
      expect(draft(tester), 'My retained draft');
      await tester.enterText(
        find.byKey(const Key('genius-url')),
        'https://genius.com.evil.test/song-lyrics',
      );
      await tester.tap(find.byKey(const Key('genius-preview')));
      await tester.pumpAndSettle();
      expect(draft(tester), 'My retained draft');
      api.failPreview = false;
      await tester.enterText(
        find.byKey(const Key('genius-url')),
        'https://genius.com/Glukwave-verification-lyrics',
      );
      await tester.tap(find.byKey(const Key('genius-preview')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('lyrics-draft')),
        '[00:02.00]My own timing',
      );
      await tester.tap(find.byKey(const Key('lyrics-save')));
      await tester.pumpAndSettle();
      expect(api.requests.last.method, 'PUT');
      expect(api.requests.last.data, {'text': '[00:02.00]My own timing'});
      expect(tester.takeException(), isNull);
      await f.clean(tester, c);
    },
  );
  testWidgets('Changed account and dismissed editor ignore a late preview', (
    tester,
  ) async {
    final c = (await tester.runAsync(controller))!, api = c.api as LyricsApi;
    var valid = true;
    await f.viewport(tester, const Size(390, 844));
    await openEditor(tester, c, isCurrent: () => valid);
    api.previewPending = Completer<Json>();
    await tester.tap(find.byKey(const Key('genius-preview')));
    await tester.pump();
    valid = false;
    c.render();
    await tester.pump();
    api.previewPending!.complete(LyricsApi.preview);
    await tester.pump();
    expect(draft(tester), 'My retained draft');
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('lyrics-save')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(LyricsEditor), findsNothing);
    expect(tester.takeException(), isNull);
    await f.clean(tester, c);
  });
  testWidgets(
    'Cover light freezes on pause, hidden lifecycle, TickerMode and reduced motion',
    (tester) async {
      final c = (await tester.runAsync(controller))!;
      await tester.runAsync(() => c.customize({'reducedMotion': false}));
      Widget ambient({
        bool playing = true,
        bool ticker = true,
        bool reduced = false,
      }) => MaterialApp(
        theme: buildWaveTheme(c.customization, Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: TickerMode(
            enabled: ticker,
            child: SizedBox(
              width: 390,
              height: 844,
              child: CoverAmbient(
                controller: c,
                artwork: '/qa-cover.jpg',
                playing: playing,
              ),
            ),
          ),
        ),
      );
      String matrix() => tester
          .widget<Transform>(find.byKey(const Key('cover-ambient-transform')))
          .transform
          .storage
          .toString();
      await tester.pumpWidget(ambient());
      await tester.pump(const Duration(seconds: 1));
      final moving = matrix();
      await tester.pump(const Duration(seconds: 1));
      expect(matrix(), isNot(moving));
      await tester.pumpWidget(ambient(playing: false));
      final paused = matrix();
      await tester.pump(const Duration(seconds: 1));
      expect(matrix(), paused);
      await tester.pumpWidget(ambient());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      final hidden = matrix();
      await tester.pump(const Duration(seconds: 1));
      expect(matrix(), hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(matrix(), isNot(hidden));
      await tester.pumpWidget(ambient(ticker: false));
      final noTick = matrix();
      await tester.pump(const Duration(seconds: 1));
      expect(matrix(), noTick);
      await tester.pumpWidget(ambient(reduced: true));
      final still = matrix();
      await tester.pump(const Duration(seconds: 1));
      expect(matrix(), still);
      expect(tester.takeException(), isNull);
      await f.clean(tester, c);
    },
  );
  testWidgets('Genius editor narrow phone at 125 percent text scale', (
    tester,
  ) async {
    final c = (await tester.runAsync(controller))!;
    await f.viewport(tester, const Size(320, 1000));
    await tester.pumpWidget(editor(c, scale: 1.25));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Genius'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('genius-url')),
      'https://genius.com/Glukwave-verification-lyrics',
    );
    await tester.tap(find.byKey(const Key('genius-preview')));
    await tester.pumpAndSettle();
    await f.screenshot(tester, 'genius-light-320-125');
    expect(tester.takeException(), isNull);
    await f.clean(tester, c);
  });
  for (final size in [390.0, 1280.0]) {
    for (final mode in ['light', 'dark', 'amoled']) {
      testWidgets('Genius editor $mode at $size', (tester) async {
        final c = (await tester.runAsync(controller))!;
        await tester.runAsync(() => c.customize({'theme': mode}));
        await f.viewport(tester, Size(size, 1000));
        await tester.pumpWidget(editor(c, theme: mode));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open editor'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Genius'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('genius-url')),
          'https://genius.com/Glukwave-verification-lyrics',
        );
        await tester.tap(find.byKey(const Key('genius-preview')));
        await tester.pumpAndSettle();
        await f.screenshot(tester, 'genius-$mode-${size.toInt()}');
        expect(tester.takeException(), isNull);
        await f.clean(tester, c);
      });
    }
  }
}
