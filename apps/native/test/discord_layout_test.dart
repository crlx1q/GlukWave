import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/discord.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/l10n/discord_strings.dart';
import 'package:glukwave/l10n/wave_localizations.dart';
import 'package:glukwave/ui/discord_panel.dart';
import 'package:glukwave/ui/widgets.dart';
import 'discord_test.dart';
import 'app_layout_test.dart' as fixtures;
import 'helpers/fonts.dart';

// Real image widgets use local existing application assets in this isolated
// test. This is not a production catalogue or Discord identity.
class _ImageClient implements HttpClient {
  final List<int> bytes;
  _ImageClient(this.bytes);
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _ImageRequest(bytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ImageRequest implements HttpClientRequest {
  final List<int> bytes;
  _ImageRequest(this.bytes);
  @override
  HttpHeaders get headers => _ImageHeaders();
  @override
  Future<HttpClientResponse> close() async => _ImageResponse(bytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ImageHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  final List<int> bytes;
  _ImageResponse(this.bytes);
  @override
  int get statusCode => 200;
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
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget panel(
  DiscordController c, {
  String language = 'en',
  String theme = 'light',
  double scale = 1,
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
      ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
      child: child!,
    ),
    home: Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 810),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: DiscordPanel(controller: c),
          ),
        ),
      ),
    ),
  ),
);

Future<void> clean(WidgetTester tester, DiscordController c) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() => closeDiscordController(c));
  await tester.binding.setSurfaceSize(null);
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
  debugNetworkImageHttpClientProvider = null;
}

Future<void> waitForArtwork(WidgetTester tester) async {
  for (
    var frame = 0;
    frame < 80 && find.byType(WaveSkeletonBlock).evaluate().isNotEmpty;
    frame++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  expect(
    find.byType(WaveSkeletonBlock),
    findsNothing,
    reason: 'Screenshot proof waits for actual local fixture image frames.',
  );
}

Future<void> precacheFixtureImages(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: SizedBox(key: Key('image-precache'))),
  );
  final context = tester.element(find.byKey(const Key('image-precache')));
  await tester.runAsync(() async {
    for (final address in [
      'https://isolated.test/qa-avatar.jpg',
      'https://isolated.test/qa-cover.jpg',
    ]) {
      for (final width in [64, 68, 104]) {
        await precacheImage(
          ResizeImage(NetworkImage(address), width: width),
          context,
        );
      }
    }
    await precacheImage(
      const ResizeImage(AssetImage('assets/logo.png'), width: 96),
      context,
    );
  });
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
  for (final theme in ['light', 'dark', 'amoled']) {
    for (final size in [const Size(390, 844), const Size(1280, 1000)]) {
      testWidgets(
        'Discord actual panel composes at $size in $theme with artwork and live state',
        (tester) async {
          final c = (await tester.runAsync(discordController))!;
          await tester.runAsync(c.restoreCustomizationScope);
          await tester.runAsync(
            () => c.customize({
              'theme': theme,
              'language': 'ru',
              'reducedMotion': true,
            }),
          );
          final bytes = (await rootBundle.load(
            'assets/forest.jpg',
          )).buffer.asUint8List();
          debugNetworkImageHttpClientProvider = () => _ImageClient(bytes);
          await precacheFixtureImages(tester);
          final data = discordFixture();
          data['identity'] = {
            ...object(data['identity']),
            'avatarUrl': 'https://isolated.test/qa-avatar.jpg',
          };
          data['activity'] = {
            ...object(data['activity']),
            'cover': 'https://isolated.test/qa-cover.jpg',
          };
          c.discordConnection = DiscordConnection(data);
          await fixtures.viewport(tester, size);
          await tester.pumpWidget(panel(c, language: 'ru', theme: theme));
          await waitForArtwork(tester);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('discord-enabled')), findsOneWidget);
          expect(find.byKey(const Key('discord-allow-join')), findsOneWidget);
          expect(find.text('Сейчас в Discord'), findsOneWidget);
          expect(find.text('@quiet_listener'), findsOneWidget);
          expect(find.text('GlukWave · Windows'), findsOneWidget);
          await fixtures.screenshot(
            tester,
            'discord-$theme-${size.width.toInt()}',
          );
          await tester.ensureVisible(
            find.byKey(const Key('discord-open-track')),
          );
          await tester.tap(find.byKey(const Key('discord-open-track')));
          expect(c.opened.last, 'https://wave.gluk.tech/app/?track=qa-track');
          await tester.ensureVisible(find.byKey(const Key('discord-listen')));
          await tester.tap(find.byKey(const Key('discord-listen')));
          expect(c.opened.last, 'https://wave.gluk.tech/app/?listen=qa-host');
          await clean(tester, c);
        },
      );
    }
  }
  testWidgets(
    'Server Free lock has upgrade and no enabled connect or sharing controls',
    (tester) async {
      final c = (await tester.runAsync(discordController))!;
      c.user = WaveUser({'id': 'qa-user', 'username': 'qa', 'plan': 'free'});
      c.discordConnection = DiscordConnection(
        discordFixture(eligible: false, status: 'locked'),
      );
      await tester.pumpWidget(panel(c));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('discord-upgrade')), findsOneWidget);
      expect(find.byKey(const Key('discord-connect')), findsNothing);
      expect(find.byKey(const Key('discord-enabled')), findsNothing);
      expect(find.byKey(const Key('discord-preview')), findsNothing);
      expect(find.text('A quiet place'), findsNothing);
      expect(find.text('Unbound'), findsNothing);
      c.user = WaveUser({'id': 'qa-user', 'username': 'qa', 'plan': 'beta'});
      c.receiveDiscordState(discordFixture(eligible: false, status: 'locked'));
      await tester.pumpAndSettle();
      expect(
        find.text('Beta'),
        findsNothing,
        reason: 'Server lock overrides a stale paid profile.',
      );
      await clean(tester, c);
    },
  );
  testWidgets(
    'Disconnected, reconnect, unavailable, error and empty states are real and scoped',
    (tester) async {
      final c = (await tester.runAsync(discordController))!;
      c.discordConnection = DiscordConnection({
        ...discordFixture(status: 'disconnected'),
        'connected': false,
        'identity': null,
        'activity': null,
      });
      await tester.pumpWidget(panel(c));
      await tester.pumpAndSettle();
      expect(find.text('Your next track belongs here'), findsOneWidget);
      expect(find.text('A quiet place'), findsNothing);
      await tester.tap(find.byKey(const Key('discord-connect')));
      await tester.pumpAndSettle();
      expect(
        c.opened.single,
        startsWith('https://discord.com/oauth2/authorize'),
      );
      c.receiveDiscordState({
        ...discordFixture(status: 'reconnect_required'),
        'needsReconnect': true,
      });
      await tester.pumpAndSettle();
      expect(find.text('Reconnect account'), findsOneWidget);
      expect(find.text('Live on Discord'), findsNothing);
      c.receiveDiscordState({
        ...discordFixture(status: 'unavailable'),
        'connected': false,
        'configured': false,
        'activity': null,
      });
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('discord-connect')),
      );
      expect(button.onPressed, isNull);
      c.receiveDiscordState(discordFixture());
      (c.api as DiscordApi).fail = true;
      await tester.runAsync(c.refreshDiscord);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('discord-error')), findsOneWidget);
      expect(find.textContaining('Private provider failure'), findsNothing);
      await clean(tester, c);
    },
  );
  testWidgets(
    'Disable and join privacy persist through server; unlink requires confirmation',
    (tester) async {
      final c = (await tester.runAsync(discordController))!,
          api = c.api as DiscordApi;
      c.discordConnection = DiscordConnection(api.state);
      await tester.pumpWidget(panel(c));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('discord-enabled')));
      await tester.tap(find.byKey(const Key('discord-enabled')));
      await tester.pumpAndSettle();
      expect(api.requests.last.data, {'enabled': false});
      await tester.ensureVisible(find.byKey(const Key('discord-allow-join')));
      await tester.tap(find.byKey(const Key('discord-allow-join')));
      await tester.pumpAndSettle();
      expect(api.requests.last.data, {'allowJoin': false});
      await tester.ensureVisible(find.byKey(const Key('discord-unlink')));
      await tester.tap(find.byKey(const Key('discord-unlink')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.requests.any((r) => r.method == 'DELETE'), isFalse);
      await clean(tester, c);
    },
  );
  for (final language in ['en', 'ru', 'kk', 'uk', 'de', 'es']) {
    testWidgets(
      'Narrow Discord panel remains readable in $language with 125 percent text',
      (tester) async {
        final c = (await tester.runAsync(discordController))!;
        final data = discordFixture();
        if (language == 'de') {
          final bytes = (await rootBundle.load(
            'assets/forest.jpg',
          )).buffer.asUint8List();
          debugNetworkImageHttpClientProvider = () => _ImageClient(bytes);
          await precacheFixtureImages(tester);
          data['identity'] = {
            ...object(data['identity']),
            'avatarUrl': 'https://isolated.test/qa-avatar.jpg',
          };
          data['activity'] = {
            ...object(data['activity']),
            'cover': 'https://isolated.test/qa-cover.jpg',
          };
        }
        c.discordConnection = DiscordConnection(data);
        await fixtures.viewport(tester, const Size(320, 900));
        await tester.pumpWidget(
          panel(
            c,
            language: language,
            theme: language == 'de' ? 'dark' : 'light',
            scale: 1.25,
          ),
        );
        if (language == 'de') await waitForArtwork(tester);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('discord-open-track')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(discordLabel(language, 'Join')), findsOneWidget);
        if (language == 'de') {
          await tester.ensureVisible(
            find.text(discordLabel(language, 'Rendering')),
          );
          await tester.pumpAndSettle();
          await fixtures.screenshot(tester, 'discord-dark-de-320-125');
        }
        await clean(tester, c);
      },
    );
  }
}
