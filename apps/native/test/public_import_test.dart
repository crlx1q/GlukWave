import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/ui/app.dart';
import 'package:glukwave/ui/provider_import.dart';
import 'audio_design_test.dart' as audio;
import 'app_layout_test.dart' as base;
import 'native19_ui_test.dart' as fixture;
import 'helpers/fonts.dart';
import 'helpers/artwork_fixture.dart';

class PublicImportApi extends fixture.Native19Api {
  final calls = <Json>[], imports = <Json>[];
  bool rejectFirst = true;
  Completer<Json>? delayedSearch;
  String source(String provider) => switch (provider) {
    'spotify' => 'https://open.spotify.com/playlist/public-quiet',
    'soundcloud' => 'https://soundcloud.com/wave/sets/quiet',
    'yandex' => 'https://music.yandex.ru/users/wave/playlists/1',
    _ => 'https://www.youtube.com/playlist?list=public-quiet',
  };
  Json collection(String provider) => {
    'id': 'public-quiet',
    'name': 'Тихий берег',
    'trackCount': 0,
    'sourceUrl': source(provider),
    'artwork': 'https://qa.invalid/coast.jpg',
  };
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    calls.add({'path': path, 'method': method, 'body': data});
    final body = object(data),
        provider = body['provider']?.toString() ?? 'spotify';
    if (path == '/api/public-import/search') {
      if (body['query'] == 'slow') {
        delayedSearch = Completer<Json>();
        return delayedSearch!.future;
      }
      if (body['query'] == 'fail') {
        throw StateError('Temporary public lookup outage');
      }
      if (body['query'] == 'empty') return {'playlists': []};
      if (body['query'] == 'likes') {
        return {
          'playlists': [],
          'liked': {
            ...collection(provider),
            'kind': 'likes',
            'id': 'public-likes-fixture',
            'name': 'Любимые Spotify',
          },
        };
      }
      return {
        'playlists': [collection(provider)],
        'partial': true,
        'warnings': ['PUBLIC_COLLECTIONS_PARTIAL', 'PUBLIC_FUTURE_CODE'],
      };
    }
    if (path == '/api/public-import/tracks') {
      return {
        'tracks': [
          for (final suffix
              in body['cursor'] == null ? ['one'] : ['one', 'two'])
            {
              'id': '$provider:$suffix',
              'sourceId': 'raw-$suffix',
              'source': provider,
              'title': suffix == 'one' ? 'Первые лучи' : 'Тихий берег — трек',
              'artist': 'Wave artist',
              'artwork': 'https://qa.invalid/coast.jpg',
              'duration': 240,
            },
        ],
        'nextCursor': body['cursor'] == null ? 'page2' : null,
        'total': 2,
        'partial': true,
        'warnings': ['PUBLIC_SOURCE_PARTIAL', 'PUBLIC_UNAVAILABLE_TRACKS'],
      };
    }
    if (path.endsWith('/import')) {
      imports.add(body);
      if (rejectFirst) {
        rejectFirst = false;
        throw StateError('Temporary import outage');
      }
      return {
        'playlist': null,
        'imported': 1,
        'deduplicated': 1,
        'destination': body['destination'],
        'partial': true,
        'warnings': ['PUBLIC_SOURCE_PARTIAL'],
        'tasteSeeded': true,
      };
    }
    return super.call(path, method: method, data: data, query: query);
  }
}

class PublicController extends fixture.Native19Controller {
  int libraryReads = 0, broadRefreshes = 0;
  PublicController(super.api, super.cache, super.audio);
  @override
  Future<void> refreshLibrary() async {
    libraryReads++;
    await super.refreshLibrary();
  }

  @override
  Future<void> refresh() async {
    broadRefreshes++;
  }

  void switchAccount() {
    user = WaveUser({
      'id': 'second',
      'username': 'second',
      'displayName': 'Second',
      'plan': 'beta',
      'role': 'user',
    });
    notifyListeners();
  }
}

Future<PublicController> makeFixture(double scale) async {
  SharedPreferences.setMockInitialValues({});
  final api = PublicImportApi(),
      cache = MusicCache(api),
      out = audio.UiAudio(api, cache),
      c = PublicController(api, cache, out);
  c.preferences = await SharedPreferences.getInstance();
  await c.restoreCustomizationScope();
  await c.customize({
    'language': 'ru',
    'theme': 'dark',
    'reducedMotion': true,
    'fontScale': scale,
  });
  c.user = WaveUser({
    'id': 'public-import',
    'username': 'wave',
    'displayName': 'Алишер',
    'plan': 'beta',
    'role': 'user',
  });
  c.loading = false;
  c.online = true;
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
  });
  setUp(installArtworkFixture);
  tearDown(clearArtworkFixture);
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 70)),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> open(
    WidgetTester tester,
    PublicController c,
    String provider,
    Size size,
  ) async {
    await base.viewport(tester, size);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('capture'),
        child: GlukWaveApp(controller: c),
      ),
    );
    await settle(tester);
    unawaited(
      showProviderImport(
        tester.element(find.byType(Scaffold).first),
        c,
        provider,
      ),
    );
    await settle(tester);
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('provider-import-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  for (final config in [
    ('spotify', 320.0, 568.0, 1.25),
    ('soundcloud', 375.0, 812.0, 1.0),
    ('yandex', 375.0, 812.0, 1.0),
    ('youtube', 1280.0, 800.0, 1.0),
  ]) {
    testWidgets(
      'Public ${config.$1} import selects normalized paged IDs and retries one intent at ${config.$2}',
      (tester) async {
        final c = (await tester.runAsync(() => makeFixture(config.$4)))!,
            api = c.api as PublicImportApi;
        await open(tester, c, config.$1, Size(config.$2, config.$3));
        expect(
          api.calls.where(
            (call) => call['path'].toString().contains('/integrations/'),
          ),
          isEmpty,
        );
        await tester.enterText(
          find.byKey(const Key('public-import-query')),
          '@wave',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('public-import-find')));
        await settle(tester);
        expect(find.textContaining('PUBLIC_'), findsNothing);
        await reveal(tester, find.text('Открытая подборка'));
        expect(find.text('Открытая подборка'), findsOneWidget);
        await reveal(tester, find.text('Тихий берег'));
        await tester.tap(find.text('Тихий берег'));
        await settle(tester);
        await reveal(tester, find.text('Показать ещё треки'));
        await tester.tap(find.text('Показать ещё треки'));
        await settle(tester);
        await reveal(tester, find.byKey(const Key('import-all')));
        await tester.tap(find.byKey(const Key('import-all')));
        await tester.pump();
        await reveal(tester, find.byKey(Key('import-track-${config.$1}:one')));
        await tester.tap(find.byKey(Key('import-track-${config.$1}:one')));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await base.screenshot(
          tester,
          'public-import-${config.$1}-${config.$2.toInt()}-selection',
        );
        await reveal(tester, find.text('Перенести в Wave'));
        await tester.tap(find.text('Перенести в Wave'));
        await settle(tester);
        await reveal(tester, find.text('Повторить'));
        await tester.tap(find.text('Повторить'));
        await settle(tester);
        expect(api.imports.length, 2);
        expect(api.imports.first['requestId'], api.imports.last['requestId']);
        expect(api.imports.last['publicSourceUrl'], api.source(config.$1));
        expect(api.imports.last['name'], 'Тихий берег');
        expect(api.imports.last['trackIds'], ['${config.$1}:two']);
        expect(c.libraryReads, 1);
        expect(c.broadRefreshes, 0);
        expect(find.text('Музыка уже в Gluk Wave'), findsOneWidget);
        expect(find.textContaining('PUBLIC_'), findsNothing);
        expect(tester.takeException(), isNull);
        await base.screenshot(
          tester,
          'public-import-${config.$1}-${config.$2.toInt()}-result',
        );
        await base.clean(tester, c);
        clearArtworkFixture();
      },
    );
  }
  testWidgets(
    'Public import paging preserves deselection while selecting only newly seen normalized IDs',
    (tester) async {
      final c = (await tester.runAsync(() => makeFixture(1)))!,
          api = c.api as PublicImportApi;
      api.rejectFirst = false;
      await open(tester, c, 'spotify', const Size(375, 812));
      await tester.enterText(
        find.byKey(const Key('public-import-query')),
        '@wave',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('public-import-find')));
      await settle(tester);
      await reveal(tester, find.text('Тихий берег'));
      await tester.tap(find.text('Тихий берег'));
      await settle(tester);
      await reveal(tester, find.byKey(const Key('import-all')));
      await tester.tap(find.byKey(const Key('import-all')));
      await tester.pump();
      await reveal(tester, find.byKey(const Key('import-track-spotify:one')));
      await tester.tap(find.byKey(const Key('import-track-spotify:one')));
      await tester.pump();
      await reveal(tester, find.text('Показать ещё треки'));
      await tester.tap(find.text('Показать ещё треки'));
      await settle(tester);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('import-track-spotify:one')),
            )
            .value,
        isFalse,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('import-track-spotify:two')),
            )
            .value,
        isTrue,
      );
      await base.screenshot(tester, 'public-import-overlap-selection');
      await reveal(tester, find.text('Перенести в Wave'));
      await tester.tap(find.text('Перенести в Wave'));
      await settle(tester);
      expect(api.imports.single['trackIds'], ['spotify:two']);
      expect(tester.takeException(), isNull);
      await base.clean(tester, c);
      clearArtworkFixture();
    },
  );
  testWidgets(
    'Public likes kind defaults to likes destination with exposed count',
    (tester) async {
      final c = (await tester.runAsync(() => makeFixture(1)))!,
          api = c.api as PublicImportApi;
      api.rejectFirst = false;
      await open(tester, c, 'spotify', const Size(375, 812));
      await tester.enterText(
        find.byKey(const Key('public-import-query')),
        'likes',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('public-import-find')));
      await settle(tester);
      await reveal(tester, find.text('Любимые Spotify'));
      await tester.tap(find.text('Любимые Spotify'));
      await settle(tester);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'В любимые'))
            .selected,
        isTrue,
      );
      expect(find.textContaining('Выбрано: 2'), findsOneWidget);
      await reveal(tester, find.text('Перенести в Wave'));
      await tester.tap(find.text('Перенести в Wave'));
      await settle(tester);
      expect(api.imports.single['destination'], 'likes');
      expect(api.imports.single.containsKey('name'), isFalse);
      await base.clean(tester, c);
      clearArtworkFixture();
    },
  );
  testWidgets(
    'Public import empty, retry, stale query, account switch and keyboard remain safe',
    (tester) async {
      final c = (await tester.runAsync(() => makeFixture(1.25)))!,
          api = c.api as PublicImportApi;
      await open(tester, c, 'spotify', const Size(320, 568));
      Future<void> search(String value) async {
        await reveal(tester, find.byKey(const Key('public-import-query')));
        await tester.enterText(
          find.byKey(const Key('public-import-query')),
          value,
        );
        await tester.pump();
        await reveal(tester, find.byKey(const Key('public-import-find')));
        await tester.tap(find.byKey(const Key('public-import-find')));
        await settle(tester);
      }

      await search('empty');
      await reveal(tester, find.text('Открытые подборки не найдены'));
      expect(find.text('Открытые подборки не найдены'), findsOneWidget);
      await search('fail');
      await reveal(tester, find.text('Повторить'));
      await tester.tap(find.text('Повторить'));
      await settle(tester);
      expect(
        api.calls
            .where(
              (call) =>
                  call['path'] == '/api/public-import/search' &&
                  object(call['body'])['query'] == 'fail',
            )
            .length,
        2,
      );
      await search('slow');
      await reveal(tester, find.byKey(const Key('public-import-query')));
      await tester.enterText(
        find.byKey(const Key('public-import-query')),
        'new query',
      );
      api.delayedSearch!.complete({
        'playlists': [api.collection('spotify')],
      });
      await settle(tester);
      expect(find.text('Тихий берег'), findsNothing);
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await tester.pump();
      await reveal(tester, find.byKey(const Key('public-import-find')));
      expect(tester.takeException(), isNull);
      await base.screenshot(tester, 'public-import-320-keyboard');
      tester.view.resetViewInsets();
      c.switchAccount();
      await settle(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('public-import-query')))
            .controller!
            .text,
        isEmpty,
      );
      await tester.tap(find.byKey(const Key('import-close')));
      await settle(tester);
      expect(find.byType(ProviderImport), findsNothing);
      await base.clean(tester, c);
      clearArtworkFixture();
    },
  );
}
