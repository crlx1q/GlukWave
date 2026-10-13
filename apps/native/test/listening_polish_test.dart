import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/ui/app.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/widgets.dart';
import 'package:glukwave/ui/equalizer_panel.dart';
import 'package:glukwave/ui/motion_icons.dart';
import 'package:glukwave/l10n/listening_polish_strings.dart';
import 'app_layout_test.dart' as f;
import 'audio_design_test.dart' as a;
import 'helpers/fonts.dart';

final ownTracks = List.generate(
  8,
  (i) => WaveTrack({
    'id': 'polish-own-$i',
    'title': [
      'The coast after sunset',
      'A little further',
      'Room for the evening',
    ][i % 3],
    'artist': i % 2 == 0 ? 'Wave verification' : 'Another original artist',
    'duration': 240,
    'artwork': 'https://qa.invalid/own-coast.jpg',
    'source': 'local',
    'playback': {'kind': 'audio', 'url': '/own.wav'},
  }),
);
final ownArtist = <String, dynamic>{
  'id': 'polish-own-artist',
  'name': 'Wave verification',
  'source': 'local',
  'artwork': 'https://qa.invalid/own-coast.jpg',
};
final ownPlaylist = <String, dynamic>{
  'id': 'polish-own-playlist',
  'name': 'Quiet hours',
  'description': 'An original verification collection',
  'trackIds': ownTracks.map((t) => t.id).toList(),
  'public': true,
  'coverArtworks': ['https://qa.invalid/own-coast.jpg'],
};

class PolishApi extends f.LayoutApi {
  final calls = <String>[];
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    calls.add('$method $path');
    if (path.startsWith('/api/artists')) {
      return {
        'artists': [ownArtist],
      };
    }
    if (path == '/api/search') {
      return {
        'tracks': ownTracks.map((t) => t.json).toList(),
        'artists': [ownArtist],
        'playlists': [ownPlaylist],
      };
    }
    if (path.startsWith('/api/playlists/')) {
      return {
        'playlist': ownPlaylist,
        'tracks': ownTracks.map((t) => t.json).toList(),
      };
    }
    if (path.startsWith('/api/recommendations')) {
      return {'tracks': ownTracks.map((t) => t.json).toList()};
    }
    if (path == '/api/taste') {
      return {
        'taste': {'onboardingCompleted': true},
      };
    }
    return super.call(path, method: method, data: data, query: query);
  }
}

class PolishAudio extends a.UiAudio {
  PolishAudio(super.api, super.cache);
  @override
  Duration get position => const Duration(seconds: 42);
  @override
  Duration get duration => const Duration(seconds: 240);
  @override
  Stream<Duration> get positionStream => Stream.value(position);
}

Future<f.LayoutController> polishController() async {
  SharedPreferences.setMockInitialValues({});
  final api = PolishApi();
  final cache = MusicCache(api);
  final audio = PolishAudio(api, cache);
  final c = f.LayoutController(api, cache, audio);
  c.preferences = await SharedPreferences.getInstance();
  await c.restoreCustomizationScope();
  await c.customize({
    'language': 'en',
    'reducedMotion': true,
    'fontScale': 1.25,
    'equalizer': {'enabled': true},
    'appearance': {'cover3d': false, 'radius': 32},
  });
  c.loading = false;
  c.online = true;
  c.user = WaveUser({
    'id': 'polish-owner',
    'username': 'qa_listener',
    'displayName': 'Alisher',
    'plan': 'beta',
  });
  c.tracks = ownTracks;
  c.playlists = [ownPlaylist];
  c.audio.tracks = ownTracks;
  c.audio.current = ownTracks.first;
  api.lyricSynchronized = true;
  api.lyricLines = List.generate(
    8,
    (i) => {'time': i * 20, 'text': 'An original listening line $i'},
  );
  return c;
}

// Only the original shipped coast image is returned. This does not contact a
// service or invent a production album; it exercises the actual image widget.
class _ImageClient implements HttpClient {
  final Uint8List bytes;
  _ImageClient(this.bytes);
  @override
  bool autoUncompress = true;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _ImageRequest(bytes);
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageRequest implements HttpClientRequest {
  final Uint8List bytes;
  _ImageRequest(this.bytes);
  @override
  final headers = _Headers();
  @override
  Future<HttpClientResponse> close() async => _ImageResponse(bytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  final Uint8List bytes;
  _ImageResponse(this.bytes);
  @override
  int get statusCode => HttpStatus.ok;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final runId = DateTime.now().millisecondsSinceEpoch, proofs = <Json>[];
  late Uint8List artworkBytes;
  setUp(() {
    debugNetworkImageHttpClientProvider = () => _ImageClient(artworkBytes);
    addTearDown(() => debugNetworkImageHttpClientProvider = null);
  });
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
    artworkBytes = await File('assets/coast.jpg').readAsBytes();
  });
  tearDownAll(() async {
    debugNetworkImageHttpClientProvider = null;
    await File(
      '../../work/qa/listening-polish-native-proof.json',
    ).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'status': proofs.length == 15 ? 'PASSED' : 'INCOMPLETE',
        'runId': runId,
        'boundary':
            'Actual Flutter widgets/controller and local shipped coast artwork; no physical audio, account, LAN or installation.',
        'cases': proofs,
        'screenshots': [
          for (final p in proofs) ...List<String>.from(p['screenshots'] ?? []),
        ],
      }),
    );
  });
  for (final theme in ['dark', 'amoled', 'light']) {
    for (final width in [1440.0, 1100.0, 390.0, 320.0]) {
      testWidgets(
        'Listening polish shell and typed discovery $theme $width at125%',
        (tester) async {
          final c = (await tester.runAsync(polishController))!;
          await tester.runAsync(() => c.customize({'theme': theme}));
          await f.viewport(tester, Size(width, 950));
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('capture'),
              child: GlukWaveApp(controller: c),
            ),
          );
          await settleArtwork(tester);
          expect(tester.takeException(), isNull);
          if (width >= 900 && width < 1180) {
            expect(
              find.byKey(const Key('desktop-navigation-rail')),
              findsOneWidget,
            );
          } else if (width < 800) {
            final progress = tester.widget<FractionallySizedBox>(
              find.byKey(const Key('mini-card-progress')),
            );
            expect(progress.widthFactor, closeTo(42 / 240, .001));
            expect(
              find.descendant(
                of: find.byType(MiniPlayer),
                matching: find.byType(Slider),
              ),
              findsNothing,
            );
            expect(find.byKey(const Key('source-attribution')), findsNothing);
          }
          final home = 'listening-polish-$runId-$theme-${width.toInt()}-home';
          await f.screenshot(tester, home);
          await tester.tap(find.byKey(const Key('nav-search')));
          await settleArtwork(tester);
          expect(
            find.byKey(const Key('browse-category-Ambient')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('search-source-menu')), findsOneWidget);
          await tester.enterText(find.byType(TextField), 'Wave verification');
          await tester.pump(const Duration(milliseconds: 450));
          await settleArtwork(tester);
          expect(
            find.byKey(const Key('browse-category-Ambient')),
            findsNothing,
          );
          expect(
            find.byKey(const Key('search-artist-polish-own-artist')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('search-playlist-polish-own-playlist')),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const Key('search-type-artists')));
          await settleArtwork(tester);
          expect(find.byType(TrackRow), findsNothing);
          await tester.tap(find.byKey(const Key('search-type-all')));
          await settleArtwork(tester);
          final discovery =
              'listening-polish-$runId-$theme-${width.toInt()}-search';
          await f.screenshot(tester, discovery);
          expect(tester.takeException(), isNull);
          proofs.add({
            'name': '$theme $width actualshell/discovery',
            'passed': true,
            'screenshots': ['native-$home.png', 'native-$discovery.png'],
          });
          debugNetworkImageHttpClientProvider = null;
          await f.clean(tester, c);
        },
      );
    }
  }
  testWidgets(
    'Compact synchronized lyrics show two separate rows; cover menu closes on selection/Escape',
    (tester) async {
      final c = (await tester.runAsync(polishController))!;
      c.settings['lyricsUnderCover'] = true;
      c.settings['lyrics'] = true;
      await f.viewport(tester, const Size(390, 1100));
      await tester.pumpWidget(
        a.shell(c, PlayerPage(controller: c, onMore: (_) {})),
      );
      await settleArtwork(tester);
      expect(find.byKey(const Key('mini-lyric-2')), findsOneWidget);
      expect(find.byKey(const Key('mini-lyric-3')), findsOneWidget);
      expect(find.byKey(const Key('mini-lyric-4')), findsNothing);
      final current = tester.getRect(find.byKey(const Key('mini-lyric-2'))),
          next = tester.getRect(find.byKey(const Key('mini-lyric-3')));
      expect(next.top, greaterThanOrEqualTo(current.bottom));
      final centered = 'listening-polish-$runId-dark-390-player';
      await f.screenshot(tester, centered);
      await tester.tap(find.byKey(const Key('player-more')));
      await settleArtwork(tester);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is PopupMenuItem<String> && widget.value == 'cover',
        ),
      );
      await settleArtwork(tester);
      expect(find.text('VINYL'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleArtwork(tester);
      expect(find.text('VINYL'), findsNothing);
      await tester.tap(find.byKey(const Key('player-more')));
      await settleArtwork(tester);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is PopupMenuItem<String> && widget.value == 'cover',
        ),
      );
      await settleArtwork(tester);
      await tester.tap(find.text('CD'));
      await settleArtwork(tester);
      expect(c.customization.appearance.coverKind, 'cd');
      expect(c.customization.appearance.cover3d, true);
      expect(find.text('CD'), findsNothing);
      expect(tester.takeException(), isNull);
      final name = 'listening-polish-$runId-mini-lyrics';
      await f.screenshot(tester, name);
      proofs.add({
        'name': 'Two block lyrics and dismissible cover options',
        'passed': true,
        'screenshots': ['native-$centered.png', 'native-$name.png'],
      });
      debugNetworkImageHttpClientProvider = null;
      await f.clean(tester, c);
    },
  );
  testWidgets(
    'Preset pointer focus has no ring; keyboard focus uses a quiet background',
    (tester) async {
      final c = (await tester.runAsync(polishController))!;
      await f.viewport(tester, const Size(390, 850));
      await tester.pumpWidget(
        a.shell(
          c,
          Center(
            child: SizedBox(
              width: 370,
              child: CompactEqualizerPanel(controller: c, onClose: () {}),
            ),
          ),
        ),
      );
      await settleArtwork(tester);
      await tester.tap(find.byKey(const Key('compact-eq-presets')));
      await settleArtwork(tester);
      final option = find.byKey(const Key('compact-eq-preset-flat'));
      final button = tester.widget<MenuItemButton>(option);
      expect(
        button.style!.side!.resolve({WidgetState.focused}),
        BorderSide.none,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await settleArtwork(tester);
      final keyboardButton = tester.widget<MenuItemButton>(
        find.byKey(const Key('compact-eq-preset-warm')),
      );
      expect(
        keyboardButton.style!.side!.resolve({WidgetState.focused}),
        BorderSide.none,
      );
      expect(
        keyboardButton.style!.backgroundColor!.resolve({WidgetState.focused}),
        isNot(Colors.transparent),
      );
      expect(tester.takeException(), isNull);
      proofs.add({
        'name': 'Pointer quiet and real keyboard menu focus',
        'passed': true,
      });
      debugNetworkImageHttpClientProvider = null;
      await f.clean(tester, c);
    },
  );
  test(
    'Six language new labels and custom primary outline icons are present',
    () {
      expect(
        listeningPolishStrings.values.every(
          (v) => v.length == 6 && v.every((x) => x.isNotEmpty),
        ),
        true,
      );
      for (final icon in [
        Icons.home_outlined,
        Icons.search_rounded,
        Icons.library_music_outlined,
        Icons.lyrics_outlined,
        Icons.queue_music_rounded,
      ]) {
        expect(WaveControlIcon.supported, contains(icon));
      }
      proofs.add({
        'name': 'Six language and native custom icon coverage',
        'passed': true,
      });
    },
  );
}

Future<void> settleArtwork(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}
