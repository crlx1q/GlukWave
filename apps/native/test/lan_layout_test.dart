import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/ui/lan_panel.dart';
import 'package:glukwave/ui/widgets.dart';
import 'package:glukwave/l10n/wave_localizations.dart';
import 'app_layout_test.dart' as f;
import 'helpers/fonts.dart';

class LanUiController extends f.LayoutController {
  LanUiController(super.api, super.cache, super.audio);
  bool enabled = true, active = true;
  String? invite = 'glukwave://lan?data=dGVzdC1maXh0dXJl';
  final actions = <String>[];
  String? testError;
  final peers = <Json>[
    {
      'id': 'pc',
      'name': 'GlukWave · Windows',
      'kind': 'windows',
      'online': true,
      'trusted': true,
      'isActive': true,
    },
    {
      'id': 'phone',
      'name': 'GlukWave · Android',
      'kind': 'android',
      'online': false,
      'trusted': true,
      'isActive': false,
    },
  ];
  @override
  bool get lanEnabled => enabled;
  @override
  bool get lanActive => active;
  @override
  bool get lanHosting => true;
  @override
  String? get lanInvite => invite;
  @override
  String? get lanError => testError;
  @override
  String? get lanHostName => 'GlukWave · Windows';
  @override
  List<Json> get lanPeers => peers;
  @override
  bool get controllingRemote => false;
  @override
  Future<void> setLanEnabled(bool value) async {
    enabled = value;
    actions.add('enable:$value');
    render();
  }

  @override
  Future<String> createLanInvite() async {
    actions.add('invite');
    render();
    return invite!;
  }

  @override
  Future<void> connectLan(String value) async {
    actions.add('connect:$value');
    render();
  }

  @override
  Future<void> disconnectLan() async {
    active = false;
    actions.add('disconnect');
    render();
  }

  @override
  Future<void> removeLanPeer(String id) async {
    peers.removeWhere((p) => p['id'] == id);
    actions.add('revoke:$id');
    render();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final language in ['en', 'ru', 'kk', 'uk', 'de', 'es']) {
    testWidgets(
      'LAN invitation, QR and trusted peers fit320 at125 percent $language',
      (tester) async {
        final api = f.LayoutApi(),
            cache = MusicCache(api),
            c = LanUiController(api, cache, WaveAudioHandler(api, cache));
        c.preferences = await SharedPreferences.getInstance();
        await c.restoreCustomizationScope();
        await c.customize({'reducedMotion': true, 'language': language});
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 900);
        await tester.binding.setSurfaceSize(const Size(320, 900));
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: WaveStrings.supportedLocales,
            localizationsDelegates: WaveStrings.delegates,
            theme: buildWaveTheme(c.customization, Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.25)),
              child: RepaintBoundary(key: const Key('capture'), child: child!),
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: AnimatedBuilder(
                  animation: c,
                  builder: (_, _) => LanPanel(
                    controller: c,
                    scanQr: () async {
                      c.actions.add('scan');
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('lan-qr')), findsOneWidget);
        if (language == 'ru') await f.screenshot(tester, 'lan-ru320');
        expect(find.text('GlukWave · Windows'), findsWidgets);
        await tester.ensureVisible(find.byKey(const Key('lan-invitation')));
        await tester.enterText(
          find.byKey(const Key('lan-invitation')),
          'glukwave://lan?data=local-test',
        );
        await tester.tap(find.byKey(const Key('lan-connect')));
        await tester.pumpAndSettle();
        expect(c.actions, contains('connect:glukwave://lan?data=local-test'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.binding.setSurfaceSize(null);
      },
    );
  }
  testWidgets(
    'LAN trust removal confirms and disconnect affects local mode only',
    (tester) async {
      final api = f.LayoutApi(),
          cache = MusicCache(api),
          c = LanUiController(api, cache, WaveAudioHandler(api, cache));
      c.preferences = await SharedPreferences.getInstance();
      await c.restoreCustomizationScope();
      await c.customize({'reducedMotion': true});
      WaveStrings.current = const WaveStrings('en');
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWaveTheme(c.customization, Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnimatedBuilder(
                animation: c,
                builder: (_, _) => LanPanel(controller: c),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('lan-revoke-phone')));
      await tester.tap(find.byKey(const Key('lan-revoke-phone')));
      await tester.pumpAndSettle();
      expect(c.actions, isNot(contains('revoke:phone')));
      await tester.tap(find.widgetWithText(FilledButton, 'Remove trust'));
      await tester.pumpAndSettle();
      expect(c.actions, contains('revoke:phone'));
      await tester.ensureVisible(find.byKey(const Key('lan-disconnect')));
      await tester.tap(find.byKey(const Key('lan-disconnect')));
      await tester.pumpAndSettle();
      expect(c.actions, contains('disconnect'));
      expect(c.enabled, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
