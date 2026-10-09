import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/api.dart';
import 'package:glukwave/core/appearance.dart';
import 'package:glukwave/core/equalizer.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/core/parity.dart';
import 'package:glukwave/services/windows_dsp.dart';
import 'package:glukwave/services/windows_equalizer.dart';
import 'package:glukwave/services/appearance_store.dart';
import 'package:glukwave/ui/parity_panels.dart';
import 'package:glukwave/ui/widgets.dart';
import 'package:glukwave/l10n/wave_localizations.dart';
import 'helpers/parity_fixture.dart';
import 'app_layout_test.dart' show clean;

class DelayedParity extends WaveApi {
  final response = Completer<Json>();
  DelayedParity() : super('http://127.0.0.1:4000');
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) => response.future;
}

class DspOutput implements WindowsDspOutput {
  @override
  final String sourceUri;
  final writes = <(String, String)>[];
  DspOutput(this.sourceUri);
  @override
  Future<void> applyEqualizer(
    bool enabled,
    double preamp,
    List<double> bands,
  ) => writeWindowsEqualizer(
    (key, value) async {
      writes.add((key, value));
    },
    enabled,
    preamp,
    bands,
  );
  @override
  Future<void> release() async {}
}

class PlanRejected extends ParityApi {
  @override
  Future<Json> call(
    String path, {
    String method = 'GET',
    dynamic data,
    Json? query,
  }) async {
    throw const WaveException('Beta or Unbound required', 'PLAN_LIMIT', 403);
  }
}

Widget page(Widget child) => MaterialApp(
  theme: waveTheme,
  localizationsDelegates: WaveStrings.delegates,
  supportedLocales: WaveStrings.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: child,
    ),
  ),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
  });
  test(
    'Windows native property bridge applies finite DSP only to the selected music output and clears it on disable',
    () async {
      final backend = WaveWindowsAudio(),
          music = DspOutput('file:///music.wav'),
          rain = DspOutput('file:///rain.wav');
      backend.players.addAll({'music': music, 'rain': rain});
      await backend.apply(equalizerPresets['warm']!, music.sourceUri);
      expect(music.writes.first.$1, 'af');
      expect(music.writes.first.$2, startsWith('format=format=floatp,lavfi=['));
      expect(music.writes.first.$2, isNot(contains('volume=')));
      expect(music.writes.first.$2, contains('equalizer=f=16000'));
      expect(music.writes.last.$1, 'volume');
      expect(double.parse(music.writes.last.$2), closeTo(70.7946, .0001));
      expect(rain.writes, isEmpty);
      await backend.apply(const WaveEqualizer(), music.sourceUri);
      expect(music.writes[music.writes.length - 3], ('af', ''));
      expect(music.writes.last, ('volume', '100.0000'));
      await expectLater(
        backend.apply(const WaveEqualizer(), 'file:///missing.wav'),
        throwsStateError,
      );
      await expectLater(
        writeWindowsEqualizer(
          (_, _) async => throw StateError('native failure'),
          true,
          0,
          const [],
        ),
        throwsStateError,
      );
      expect(
        windowsEqualizerFilter(true, double.nan, [double.infinity]),
        isNot(contains('NaN')),
      );
    },
  );
  test(
    'Rejected native DSP clears the filter and restores requested volume',
    () async {
      final writes = <(String, String)>[];
      await expectLater(
        writeWindowsEqualizer(
          (key, value) async {
            writes.add((key, value));
            if (key == 'af' && value.isNotEmpty) {
              throw StateError('filter unavailable');
            }
          },
          true,
          -3,
          [3],
          volume: .7,
        ),
        throwsStateError,
      );
      expect(writes.skip(1), [('af', ''), ('volume', '70.0000')]);
      expect(windowsEqualizerGain(true, double.infinity), 1);
      expect(windowsEqualizerGain(true, 99), closeTo(3.9810717, .0000001));
    },
  );
  test(
    'Taste persists catalogue selections and explicit skip completes with zero artists',
    () async {
      final api = ParityApi();
      final state = WaveParity(api);
      await state.load();
      expect(state.preference['onboardingCompleted'], isFalse);
      await state.saveTaste({
        'artists': [qaArtist],
        'onboardingStep': 2,
      });
      expect(objects(state.preference['artists']).single['id'], 'qa-artist');
      await state.saveTaste({
        'artists': [],
        'onboardingCompleted': true,
        'onboardingStep': 3,
      });
      expect(state.preference['artists'], isEmpty);
      expect(state.preference['onboardingCompleted'], isTrue);
      state.dispose();
      api.dio.close();
    },
  );
  test(
    'A late taste response cannot populate a different account scope',
    () async {
      final api = DelayedParity()..token = 'account-a';
      final state = WaveParity(api), pending = state.load();
      api.token = 'account-b';
      api.response.complete({
        'taste': {
          'artists': [qaArtist],
        },
      });
      await pending;
      expect(state.taste, isEmpty);
      state.dispose();
      api.dio.close();
    },
  );
  test(
    'Typography remains bounded and free accessibility edits do not require detailed customization',
    () {
      expect(const WaveCustomization().merge({'fontScale': 9}).fontScale, 1.25);
      expect(const WaveCustomization().merge({'fontScale': .1}).fontScale, .85);
      expect(
        const WaveCustomization().merge({'fontFamily': 'unknown'}).fontFamily,
        'manrope',
      );
      expect(
        requiresAdvancedAppearance({'fontScale': 1.25, 'reducedMotion': true}),
        isFalse,
      );
      expect(
        requiresAdvancedAppearance({
          'appearance': {
            'light': {'accent': '#aabbcc'},
          },
        }),
        isFalse,
      );
      expect(
        requiresAdvancedAppearance({
          'appearance': {'radius': 28},
        }),
        isTrue,
      );
    },
  );
  test(
    'Plan rejection restores authoritative appearance and does not queue an endless retry',
    () async {
      final c = await parityController(),
          api = PlanRejected()..token = 'qa-session';
      final store = AppearanceStore(api, c.preferences);
      await store.selectScope('qa-scope');
      await store.change({
        'appearance': {'radius': 35},
      });
      await store.flush();
      expect(store.current.appearance.radius, 24);
      expect(store.pending, isFalse);
      expect(store.lastError, 'Beta or Unbound required');
      store.dispose();
      api.dio.close();
      c.dispose();
      await c.audio.release();
      c.api.dio.close();
    },
  );
  testWidgets(
    'Jam listener toggles its own pause using the REST endpoint without host transport permissions',
    (tester) async {
      final c = (await tester.runAsync(parityController))!,
          api = c.api as ParityApi;
      c.room = {
        'id': 'qa-jam',
        'ownerId': 'qa-friend',
        'type': 'jam',
        'members': [],
        'state': {},
      };
      expect(c.canControl, isFalse);
      expect(c.canTogglePlayback, isTrue);
      await tester.runAsync(() => c.transport('pause'));
      expect(api.requests.where((r) => r.path.endsWith('/pause')).single.data, {
        'paused': true,
      });
      expect(c.connect['jamPaused'], isTrue);
      await clean(tester, c);
    },
  );
  testWidgets(
    'Playlist visibility uses PATCH and verifies the returned public state',
    (tester) async {
      final c = (await tester.runAsync(parityController))!,
          api = c.api as ParityApi;
      Json? changed;
      await tester.pumpWidget(
        page(
          PlaylistPublishing(
            controller: c,
            playlist: c.playlists.first,
            onChanged: (value) => changed = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('playlist-public')));
      await tester.pumpAndSettle();
      expect(api.requests.where((r) => r.method == 'PATCH').single.data, {
        'public': true,
      });
      expect(changed?['public'], isTrue);
      await clean(tester, c);
    },
  );
  testWidgets(
    'Privacy switch sends only its accepted boolean and reloads authoritative server state',
    (tester) async {
      final c = (await tester.runAsync(parityController))!,
          api = c.api as ParityApi;
      await tester.pumpWidget(page(PrivacyPanel(controller: c)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacy-showActivity')));
      await tester.pumpAndSettle();
      expect(api.requests.where((r) => r.method == 'PATCH').single.data, {
        'showActivity': true,
      });
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('privacy-showActivity')),
            )
            .value,
        isTrue,
      );
      await clean(tester, c);
    },
  );
  testWidgets(
    'Friend request accept/decline use real request identifiers and explicit boolean',
    (tester) async {
      final c = (await tester.runAsync(parityController))!,
          api = c.api as ParityApi;
      await tester.pumpWidget(page(FriendsPage(controller: c, onRoom: () {})));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Accept'));
      await tester.tap(find.byTooltip('Accept'));
      await tester.pumpAndSettle();
      expect(
        api.requests.where((r) => r.method == 'PUT').single.path,
        '/api/friends/requests/qa-request',
      );
      expect(api.requests.where((r) => r.method == 'PUT').single.data, {
        'accept': true,
      });
      await clean(tester, c);
    },
  );
  testWidgets(
    'Failed account deletion retains private account state and displays an error',
    (tester) async {
      final c = (await tester.runAsync(parityController))!,
          api = c.api as ParityApi;
      api.fail = true;
      await tester.pumpWidget(page(AccountForm(controller: c, kind: 'delete')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('account-current-password')),
        'test-current-password',
      );
      await tester.enterText(
        find.byKey(const Key('account-new-value')),
        'qa_owner',
      );
      await tester.tap(find.byKey(const Key('account-submit')));
      await tester.pumpAndSettle();
      expect(c.user?.id, 'qa-owner');
      expect(c.tracks, isNotEmpty);
      expect(find.text('Unavailable in isolated QA'), findsOneWidget);
      expect(api.requests.single.method, 'DELETE');
      await clean(tester, c);
    },
  );
  testWidgets(
    'Unavailable optional endpoint remains an honest error with retry and no counters',
    (tester) async {
      final c = (await tester.runAsync(parityController))!;
      (c.api as ParityApi).fail = true;
      await tester.pumpWidget(page(ListeningStats(controller: c)));
      await tester.pumpAndSettle();
      expect(find.text('Currently unavailable'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      await clean(tester, c);
    },
  );
  testWidgets(
    'Admin release form is visible only for configured owner rights',
    (tester) async {
      final c = (await tester.runAsync(parityController))!;
      await tester.pumpWidget(page(AdminParity(controller: c)));
      await tester.pumpAndSettle();
      expect(find.byType(ReleaseForm), findsNothing);
      (c.api as ParityApi).owner = true;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page(AdminParity(controller: c)));
      await tester.pumpAndSettle();
      expect(find.byType(ReleaseForm), findsOneWidget);
      await clean(tester, c);
    },
  );
}
