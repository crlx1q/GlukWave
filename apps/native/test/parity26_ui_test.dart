import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/ui/app.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/theme.dart';
import 'package:glukwave/l10n/wave_localizations.dart';
import 'package:glukwave/ui/parity_panels.dart';
import 'app_layout_test.dart' as f;
import 'audio_design_test.dart' as a;
import 'native19_ui_test.dart' as n;
import 'helpers/fonts.dart';
import 'helpers/artwork_fixture.dart';

class GestureAudio extends a.UiAudio {
  int commands = 0;
  GestureAudio(super.api, super.cache);
  @override
  Future<void> skipToQueueItem(int index) async { commands++; }
}
class ArtistApi extends f.LayoutApi {
  @override
  Future<Json> call(String path, {String method = 'GET', dynamic data, Json? query}) async {
    if (path == '/api/artists/original') return {'artist': {'id':'original','name':'Original artist','source':'local','artwork':''},'tracks': [{'id':'artist-track','title':'Only source facts','artist':'Original artist','source':'local','artwork':'','duration':120,'playback':{'kind':'audio','url':'/own.wav'}}], 'albums': [], 'playlists': []};
    return super.call(path, method: method, data: data, query: query);
  }
}
Future<void> mount(WidgetTester t, f.LayoutController c, Size size) async {
  await f.viewport(t, size);
  await t.pumpWidget(RepaintBoundary(key: const Key('capture'), child: GlukWaveApp(controller:c)));
  if (c.restoringLocal) { await t.pump(); await t.pump(const Duration(milliseconds: 100)); } else { await t.pumpAndSettle(); }
}
Future<void> clean(WidgetTester t, f.LayoutController c) async { clearArtworkFixture(); await f.clean(t,c); }
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('com.ryanheise.audio_session'), (_) async => null);
    await loadAppFonts();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(installArtworkFixture);
  tearDown(clearArtworkFixture);
  testWidgets('One auth form survives repeated resize and local notifications', (t) async {
    final c = (await t.runAsync(f.controller))!;
    await mount(t,c,const Size(899,900));
    await t.enterText(find.byKey(const Key('auth-email')), 'kept@example.test');
    final form = t.element(find.byType(Form));
    for(final size in [const Size(901,900),const Size(800,900),const Size(900,900),const Size(320,740),const Size(1440,900)]) {
      await f.viewport(t,size);c.render();c.render();await t.pumpAndSettle();
      expect(t.element(find.byType(Form)), same(form));
      expect(t.widget<TextFormField>(find.byKey(const Key('auth-email'))).controller!.text,'kept@example.test');
      expect(t.takeException(),isNull);
      await f.screenshot(t,'parity26-auth-${size.width.toInt()}');
    }
    await clean(t,c);
  });
  testWidgets('Saved user stays on bootstrap until coherent local restore', (t) async {
    final c = (await t.runAsync(n.fixture))!;
    c.restoringLocal = true;
    await mount(t,c,const Size(375,812));
    for(var i=0;i<12;i++){c.render();await t.pump();expect(find.byKey(const Key('native-startup')),findsOneWidget);expect(find.byType(WaveShell),findsNothing);}
    c.restoringLocal=false;c.render();await t.pumpAndSettle();
    expect(find.byType(WaveShell),findsOneWidget);
    final dynamic shell=t.state(find.byType(WaveShell));
    for(final size in [const Size(800,900),const Size(901,900),const Size(375,812)]){await f.viewport(t,size);shell.navigate(WavePage.settings);c.render();await t.pumpAndSettle();expect(t.takeException(),isNull);}
    c.online=false;c.render();await t.pumpAndSettle();expect(find.byType(WaveShell),findsOneWidget);
    c.user=null;c.render();await t.pumpAndSettle();expect(find.byKey(const Key('auth-email')),findsOneWidget);expect(t.takeException(),isNull);
    await clean(t,c);
  });
  testWidgets('Mini previews real neighbor, cancels and commits once', (t) async {
    final controller=(await t.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final api=f.LayoutApi(),cache=MusicCache(api),audio=GestureAudio(api,cache),c=f.LayoutController(api,cache,audio);
      c.preferences=await SharedPreferences.getInstance();c.loading=false;
      await c.restoreCustomizationScope();await c.customize({'reducedMotion':true,'language':'en'});
      c.tracks=List.generate(3,(i)=>WaveTrack({'id':'gesture-$i','title':'Original queue track $i','artist':'Original fixture','duration':120,'source':'local','artwork':'','playback':{'kind':'audio','url':'/own.wav'}}));
      audio.tracks=c.tracks;audio.current=c.tracks.first;return c;
    }))!;
    final audio=controller.audio as GestureAudio;
    await f.viewport(t,const Size(375,812));
    await t.pumpWidget(a.shell(controller,Align(alignment:Alignment.bottomCenter,child:MiniPlayer(controller:controller,onOpen:(){})),scale:1));await t.pumpAndSettle();
    final center=t.getCenter(find.byKey(const Key('mini-gesture')));
    final cancel=await t.startGesture(center,kind:PointerDeviceKind.touch);await cancel.moveBy(const Offset(-42,0));await t.pump();
    expect(find.byKey(const Key('mini-swipe-preview')),findsOneWidget);expect(find.text(controller.tracks[1].title),findsOneWidget);expect(audio.commands,0);
    await f.screenshot(t,'parity26-mini-preview-375');
    await cancel.cancel();await t.pumpAndSettle();expect(audio.commands,0);expect(find.byKey(const Key('mini-swipe-preview')),findsNothing);
    final commit=await t.startGesture(center,kind:PointerDeviceKind.touch);await commit.moveBy(const Offset(-110,0));await t.pump();await commit.up();await t.pumpAndSettle();expect(audio.commands,1);
    expect(t.takeException(),isNull);
    await clean(t,controller);
  });
  testWidgets('Player reveal follows gesture progress and cancel restores mini', (t) async {
    final c=(await t.runAsync(n.fixture))!;await mount(t,c,const Size(375,812));
    final dynamic shell=t.state(find.byType(WaveShell));
    final center=t.getCenter(find.byKey(const Key('mini-gesture')));
    final drag=await t.startGesture(center,kind:PointerDeviceKind.touch);await drag.moveBy(const Offset(0,-150));await t.pump();await t.pump();
    expect(shell.playerReveal.value,greaterThan(0));expect(shell.playerReveal.value,lessThan(1));expect(find.byKey(const Key('full-player')),findsOneWidget);
    await f.screenshot(t,'parity26-reveal-progress-375');
    await drag.cancel();await t.pumpAndSettle();expect(shell.playerReveal.value,0);expect(find.byKey(const Key('full-player')),findsNothing);expect(t.takeException(),isNull);
    await clean(t,c);
  });
  testWidgets('Top notice wraps, dismisses and does not create SnackBar', (t) async {
    final c=(await t.runAsync(n.fixture))!;await mount(t,c,const Size(320,740));
    c.tell('An original contextual message with enough text to wrap cleanly on the smallest supported phone.');await t.pump();await t.pump();
    expect(find.byKey(const Key('wave-top-notice')),findsOneWidget);expect(find.byType(SnackBar),findsNothing);
    final rect=t.getRect(find.byKey(const Key('wave-top-notice')));expect(rect.top,greaterThanOrEqualTo(0));expect(rect.right,lessThanOrEqualTo(320));
    await f.screenshot(t,'parity26-toast-320');await t.tap(find.descendant(of:find.byKey(const Key('wave-top-notice')),matching:find.byType(IconButton)));await t.pumpAndSettle();expect(find.byKey(const Key('wave-top-notice')),findsNothing);
    await clean(t,c);
  });
  testWidgets('Settings search opens real existing category on phone', (t) async {
    final c=(await t.runAsync(n.fixture))!;await mount(t,c,const Size(375,812));final dynamic shell=t.state(find.byType(WaveShell));shell.navigate(WavePage.settings);await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('settings-search')),'EQ');await t.pumpAndSettle();expect(find.byKey(const Key('settings-playback')),findsOneWidget);
    await t.tap(find.byKey(const Key('settings-playback')));await t.pumpAndSettle();expect(shell.settingsSection,'playback');expect(shell.settingsQuery,'');expect(t.takeException(),isNull);await f.screenshot(t,'parity26-settings-375');await clean(t,c);
  });
  testWidgets('Artist route uses local results and never overwrites global search', (t) async {
    final c=(await t.runAsync(() async {
      SharedPreferences.setMockInitialValues({});final api=ArtistApi(),cache=MusicCache(api),audio=a.UiAudio(api,cache),c=f.LayoutController(api,cache,audio);c.preferences=await SharedPreferences.getInstance();await c.restoreCustomizationScope();await c.customize({'reducedMotion':true,'language':'en'});c.loading=false;c.results=[WaveTrack({'id':'kept-search','title':'Kept search'})];return c;
    }))!;
    await f.viewport(t,const Size(375,812));await t.pumpWidget(a.shell(c,const SizedBox(),scale:1));await t.pumpAndSettle();
    final context=t.element(find.byType(Scaffold));unawaited(openArtist(context,c,{'id':'original','name':'Original artist','source':'local','artwork':''}));await t.pumpAndSettle();
    expect(find.text('Only source facts'),findsOneWidget);expect(c.results.single.id,'kept-search');expect(find.text('Original artist'),findsWidgets);expect(t.takeException(),isNull);await f.screenshot(t,'parity26-artist-375');await clean(t,c);
  });
  testWidgets('Actual lyric rows settle independently once per cue and remain still between cues', (t) async {
    final c=(await t.runAsync(a.makeController))!;
    await t.runAsync(()=>c.customize({'reducedMotion':false,'theme':'dark','appearance':{'cover3d':false}}));
    c.settings['lyrics']=true;
    final api=c.api as f.LayoutApi;
    api.lyricSynchronized=true;
    api.lyricLines=List.generate(12,(i)=>{'time':i*6,'text':'Original listening room line $i'});
    void cue(double position) { c.audio.showRemote(PlaybackSnapshot.fromJson({'trackId':c.tracks.first.id,'position':position,'playing':false}),c.tracks.first,c.tracks); }
    cue(1);
    await f.viewport(t,const Size(375,812));
    await t.pumpWidget(RepaintBoundary(key:const Key('capture'),child:MaterialApp(theme:buildWaveTheme(c.customization,Brightness.dark),locale:const Locale('en'),supportedLocales:WaveStrings.supportedLocales,localizationsDelegates:WaveStrings.delegates,home:Scaffold(body:PlayerPage(controller:c,onMore:(_){})))));
    await t.pump();await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:50)));await t.pump(const Duration(milliseconds:800));await t.tap(find.byKey(const Key('player-lyrics-toggle')));await t.pump();await t.pump(const Duration(milliseconds:800));
    cue(25);await t.pump();await t.pump();for(var frame=0;frame<8;frame++){await t.pump(const Duration(milliseconds:16));}
    final offsets=t.widgetList<Transform>(find.byKey(const Key('lyric-tile-offset'))).map((tile)=>tile.transform.storage[13]).toList();
    expect(offsets.any((value)=>value.abs()>1),isTrue,reason:'Cue change has actual row motion');
    expect(offsets.map((value)=>value.toStringAsFixed(2)).toSet().length,greaterThan(1),reason:'Rows settle independently with neighbor staggering');
    await f.screenshot(t,'parity26-lyric-tiles-moving-375');
    await t.pump(const Duration(seconds:2));
    final still=t.widgetList<Transform>(find.byKey(const Key('lyric-tile-offset'))).map((tile)=>tile.transform.storage[13]).toList();
    expect(still.every((value)=>value.abs()<.8),isTrue);
    final scrollable=t.state<ScrollableState>(find.byType(Scrollable).last),before=scrollable.position.pixels;
    await t.pump(const Duration(seconds:2));expect(scrollable.position.pixels,before,reason:'No treadmill between media cues');
    await f.screenshot(t,'parity26-lyrics-settled-375');expect(t.takeException(),isNull);await clean(t,c);
  });

}
