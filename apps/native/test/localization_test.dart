import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/appearance.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/l10n/catalogs.dart';
import 'package:glukwave/l10n/wave_localizations.dart';
import 'package:glukwave/services/appearance_store.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/ui/app.dart';
import 'helpers/fonts.dart';
import 'app_layout_test.dart'
    show LayoutApi, LayoutController, viewport, screenshot, clean;

class LanguageApi extends LayoutApi {
  Completer<Json>? localeResponse;
  final requestedLocales = <String>[];
  bool fail = false;
  final patches = <Json>[];
  int revision = 10;
  @override
  Future<Json> localeMetadata(String browserLanguage) {
    requestedLocales.add(browserLanguage);
    return localeResponse?.future ??
        Future.error(const WaveException('offline'));
  }

  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    if (path == '/api/settings' && method == 'PATCH') {
      patches.add(object(data));
      if (fail) throw const WaveException('offline');
      return {'settings': object(data), 'revision': ++revision};
    }
    return super.call(path, method: method, data: data, query: query);
  }
}

Future<LayoutController> languageController({bool reset = true}) async {
  if (reset) SharedPreferences.setMockInitialValues({});
  final api = LanguageApi(), cache = MusicCache(api);
  final c = LayoutController(api, cache, WaveAudioHandler(api, cache));
  c.preferences = await SharedPreferences.getInstance();
  await c.restoreCustomizationScope();
  await c.customize({'reducedMotion': true});
  c.loading = false;
  return c;
}

void expectWholeLabel(WidgetTester tester, Finder label) {
  final paragraph = tester.renderObject<RenderParagraph>(label);
  final text = paragraph.text.toPlainText();
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  expect(boxes, isNotEmpty, reason: 'Label should have text boxes: $text');
  final firstTop = boxes.first.top;
  final firstHeight = boxes.first.bottom - boxes.first.top;
  final sameLine = boxes.every(
    (b) =>
        (b.top - firstTop).abs() < (firstHeight > 0 ? firstHeight * 0.5 : 10),
  );
  expect(
    sameLine,
    isTrue,
    reason: 'Complete navigation label must occupy one line: $text',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> inventory;
  String keyFor(String text) => inventory.entries
      .firstWhere((entry) => object(entry.value)['ru'] == text)
      .key;
  String copy(String text, String language) =>
      WaveStrings(language).text(keyFor(text));
  setUpAll(() async {
    inventory = object(
      jsonDecode(await File('tool/catalog_source.json').readAsString()),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
    await loadAppFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final locale in WaveStrings.supportedLocales) {
      await const WaveStringsDelegate().load(locale);
    }
  });

  test(
    'All six offline catalogs have identical complete keys and interpolation parameters',
    () {
      final keys = waveCatalogs['en']!.keys.toSet();
      expect(keys.length, greaterThanOrEqualTo(515));
      final placeholders = RegExp(r'\{\w+\}');
      for (final language in languageNames.keys) {
        final catalog = waveCatalogs[language]!;
        expect(catalog.keys.toSet(), keys, reason: language);
        for (final key in keys) {
          expect(catalog[key]!.trim(), isNotEmpty, reason: '$language/$key');
          expect(
            placeholders.allMatches(catalog[key]!).map((m) => m[0]).toSet(),
            placeholders
                .allMatches(waveCatalogs['en']![key]!)
                .map((m) => m[0])
                .toSet(),
            reason: '$language/$key',
          );
        }
      }
      for (final entry in inventory.entries) {
        expect(keys, contains(entry.key), reason: object(entry.value)['ru']);
      }
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        for (final match in RegExp(
          r"wt\('([^']+)'",
        ).allMatches(file.readAsStringSync())) {
          expect(keys, contains(match[1]), reason: file.path);
        }
      }
    },
  );

  test(
    'English fallback, regional locales, plural forms and localized numbers/dates are real',
    () {
      expect(supportedLanguage('de-AT'), 'de');
      expect(supportedLanguage('kk_KZ'), 'kk');
      expect(supportedLanguage('fr'), 'en');
      expect(const WaveStrings('fr').text('language.title'), 'Language');
      expect(const WaveCustomization().language, 'auto');
      expect(
        const WaveCustomization().merge({'language': 'fr'}).language,
        'auto',
      );
      expect(const WaveStrings('en').plural('count.tracks', 1), '1 track');
      expect(const WaveStrings('en').plural('count.tracks', 2), '2 tracks');
      expect(const WaveStrings('ru').plural('count.tracks', 1), '1 трек');
      expect(const WaveStrings('ru').plural('count.tracks', 2), '2 трека');
      expect(const WaveStrings('ru').plural('count.tracks', 11), '11 треков');
      expect(const WaveStrings('ru').plural('count.tracks', 21), '21 трек');
      expect(const WaveStrings('uk').plural('count.tracks', 22), '22 треки');
      expect(const WaveStrings('kk').plural('count.tracks', 2), '2 трек');
      expect(
        const WaveStrings('de').number(1234.5, decimalDigits: 1),
        '1.234,5',
      );
      expect(
        const WaveStrings('en').number(1234.5, decimalDigits: 1),
        '1,234.5',
      );
      expect(
        const WaveStrings('de').date(DateTime(2026, 10, 7)),
        contains('Oktober'),
      );
      expect(
        const WaveStrings('es').date(DateTime(2026, 10, 7)),
        contains('octubre'),
      );
      expect(
        const WaveStrings(
          'en',
        ).text(keyFor('Удалить «{p0}»?'), {'p0': 'Вальс №2'}),
        'Delete “Вальс №2”?',
      );
    },
  );

  test(
    'Language persists for guests and account offline edits stay sparse across stale revisions',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final api = LanguageApi(), guest = AppearanceStore(api, preferences);
      await guest.selectScope(null);
      await guest.change({'language': 'kk'});
      expect(guest.pending, isFalse);
      final restored = AppearanceStore(api, preferences);
      await restored.selectScope(null);
      expect(restored.current.language, 'kk');
      api.token = 'account-one';
      await restored.selectScope('account-one', fallback: {'language': 'de'});
      api.fail = true;
      await restored.change({'language': 'es'});
      await restored.flush();
      expect(api.patches.single, {'language': 'es'});
      expect(restored.pending, isTrue);
      await restored.receiveRemote({'language': 'en'}, revision: 9);
      expect(restored.current.language, 'es');
      final offlineRestart = AppearanceStore(api, preferences);
      await offlineRestart.selectScope('account-one');
      expect(offlineRestart.current.language, 'es');
      expect(offlineRestart.pending, isTrue);
      api.fail = false;
      await offlineRestart.flush();
      expect(offlineRestart.current.language, 'es');
      expect(offlineRestart.pending, isFalse);
      expect(api.patches.last, {'language': 'es'});
      await offlineRestart.receiveRemote({'language': 'ru'}, revision: 1);
      expect(offlineRestart.current.language, 'es');
      api.token = 'account-two';
      await offlineRestart.selectScope(
        'account-two',
        fallback: {'language': 'uk'},
      );
      expect(offlineRestart.current.language, 'uk');
      await offlineRestart.selectScope(null);
      expect(offlineRestart.current.language, 'kk');
      guest.dispose();
      restored.dispose();
      offlineRestart.dispose();
      api.dio.close(force: true);
    },
  );

  testWidgets(
    'Late region results cannot replace manual choices or another account scope',
    (tester) async {
      tester.binding.platformDispatcher.localeTestValue = const Locale(
        'de',
        'DE',
      );
      final c = (await tester.runAsync(languageController))!;
      final api = c.api as LanguageApi;
      expect(c.resolvedLanguage, 'de');
      api.localeResponse = Completer<Json>();
      final lookup = c.resolveAutomaticLanguage();
      await tester.runAsync(() => c.customize({'language': 'es'}));
      api.localeResponse!.complete({'language': 'kk', 'source': 'ip'});
      await lookup;
      expect(c.resolvedLanguage, 'es');
      expect(api.headers['Accept-Language'], 'es');
      api.localeResponse = Completer<Json>();
      await tester.runAsync(() => c.customize({'language': 'auto'}));
      final scopeLookup = c.resolveAutomaticLanguage();
      api.token = 'new-account';
      c.user = WaveUser({'id': 'new-account', 'username': 'listener'});
      await tester.runAsync(() async {
        await c.restoreCustomizationScope();
        await c.customize({'language': 'uk'});
      });
      api.localeResponse!.complete({'language': 'ru', 'source': 'browser'});
      await scopeLookup;
      expect(c.resolvedLanguage, 'uk');
      expect(api.headers['Accept-Language'], 'uk');
      expect(api.requestedLocales.toSet(), {'de'});
      await clean(tester, c);
      tester.binding.platformDispatcher.clearLocaleTestValue();
    },
  );

  testWidgets(
    'The actual guest language picker changes Flutter locale and persists offline',
    (tester) async {
      final c = (await tester.runAsync(languageController))!;
      await viewport(tester, const Size(390, 900));
      await tester.pumpWidget(GlukWaveApp(controller: c));
      await tester.pumpAndSettle();
      final appearance = find.byKey(const Key('open-appearance'));
      await tester.ensureVisible(appearance);
      await tester.tap(appearance);
      await tester.pumpAndSettle();
      for (final language in languageNames.entries) {
        final picker = find.byKey(const Key('language-selector'));
        await tester.ensureVisible(picker);
        await tester.tap(picker);
        await tester.pumpAndSettle();
        await tester.runAsync(() => tester.tap(find.text(language.value).last));
        await tester.pumpAndSettle();
        expect(c.customization.language, language.key);
        expect(c.api.headers['Accept-Language'], language.key);
        expect(
          find.text(WaveStrings(language.key).text('language.title')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
      final saved = tester.runAsync(
        () => c.appearanceStore!.flushLocalWrites().timeout(
          const Duration(seconds: 5),
        ),
      );
      await tester.pump();
      await saved;
      final restored = AppearanceStore(c.api, c.preferences);
      await tester.runAsync(() => restored.selectScope(null));
      expect(restored.current.language, 'es');
      expect(restored.pending, isFalse);
      restored.dispose();
      await clean(tester, c);
    },
  );

  for (final language in languageNames.keys) {
    for (final width
        in language == 'en' || language == 'de'
            ? [320.0, 390.0, 1280.0]
            : [320.0, 390.0]) {
      testWidgets(
        'Actual $language auth, home, settings and player at width $width preserve music titles',
        (tester) async {
          final c = (await tester.runAsync(languageController))!;
          await tester.runAsync(() => c.customize({'language': language}));
          await viewport(tester, Size(width, 900));
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('capture'),
              child: GlukWaveApp(controller: c),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(copy('Рады тебя слышать', language)),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          if (width == 390) await screenshot(tester, 'language-auth-$language');
          c.user = WaveUser({
            'id': 'language-fixture',
            'username': 'Слушатель',
          });
          await tester.runAsync(() async {
            await c.restoreCustomizationScope();
            await c.customize({'language': language, 'reducedMotion': true});
          });
          final track = WaveTrack({
            'id': 'language-track',
            'title': 'Вальс №2',
            'artist': 'Автор без перевода',
            'duration': 4800,
            'playback': {'kind': 'audio'},
          });
          c.tracks = [track];
          c.audio.tracks = [
            track,
            WaveTrack({
              'id': 'language-queue-next',
              'title': 'Следующая запись',
              'artist': 'Автор без перевода',
              'duration': 181,
              'playback': {'kind': 'audio'},
            }),
          ];
          c.audio.current = track;
          c.audio.mediaItem.add(c.audio.item(track));
          c.render();
          await tester.pumpAndSettle();
          expect(find.text('Вальс №2'), findsWidgets);
          expect(find.text(copy('Главная', language)), findsWidgets);
          expectWholeLabel(
            tester,
            find.text(WaveStrings(language).text('native.90e8504b03')),
          );
          await screenshot(tester, 'language-home-$language-${width.toInt()}');
          if (width < 900) {
            await tester.tap(find.byKey(const Key('mobile-menu')));
            await tester.pumpAndSettle();
            await tester.tap(find.text(copy('Настройки', language)).last);
          } else {
            await tester.tap(find.text(copy('Настройки', language)).first);
          }
          await tester.pumpAndSettle();
          expect(
            find.textContaining(copy('В твоём ритме', language)),
            findsOneWidget,
          );
          await screenshot(
            tester,
            'language-settings-$language-${width.toInt()}',
          );
          await tester.tap(find.byKey(const Key('mini-gesture')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('full-player')), findsOneWidget);
          expect(find.text(copy('Трек', language)), findsWidgets);
          expect(find.text('Вальс №2'), findsWidgets);
          expect(find.text('Автор без перевода'), findsWidgets);
          expect(find.text('1:20:00'), findsWidgets);
          for (var i = 0; i < 4; i++) {
            final label = find.byKey(Key('player-tab-label-$i'));
            expectWholeLabel(tester, label);
            final target = find.ancestor(
              of: label,
              matching: find.byType(InkWell),
            );
            expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
          }
          await screenshot(
            tester,
            'language-player-$language-${width.toInt()}',
          );
          if (width == 320 && (language == 'de' || language == 'uk')) {
            final before = c.audio.current!.id;
            final strip = find.byKey(const Key('player-tabs-scroll'));
            expect(strip, findsOneWidget);
            await tester.drag(strip, const Offset(-160, 0));
            await tester.pumpAndSettle();
            expect(c.audio.current!.id, before);
            final index = language == 'de' ? 2 : 3;
            final label = find.byKey(Key('player-tab-label-$index'));
            await tester.ensureVisible(label);
            await tester.tap(label);
            await tester.pumpAndSettle();
            expectWholeLabel(tester, label);
            await screenshot(
              tester,
              'language-player-$language-320-selected-tab',
            );
          }
          expect(tester.takeException(), isNull);
          await clean(tester, c);
        },
      );
    }
  }
}
