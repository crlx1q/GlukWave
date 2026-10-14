import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/services/audio.dart';
import 'package:glukwave/services/cache.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/album_stage.dart';
import 'package:glukwave/ui/connect_picker.dart';
import 'package:glukwave/ui/desktop_player.dart';
import 'package:glukwave/ui/mini_lyrics.dart';
import 'package:glukwave/ui/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_layout_test.dart' as base;
import 'audio_design_test.dart' as a;
import 'audio_lifecycle_test.dart' as l;
import 'helpers/fonts.dart';
import 'helpers/artwork_fixture.dart';

class EvalAudio extends WaveAudioHandler {
  EvalAudio(super.api, super.cache, {required bool phone})
      : super(hardwareVolume: phone, output: l.NativeOutput());
}
class EvalController extends base.LayoutController {
  EvalController(super.api, super.cache, super.audio);
  bool network = false;
  List<Json> peers = [];
  @override bool get lanEnabled => network;
  @override List<Json> get lanPeers => peers;
}
Future<EvalController> controller(bool phone) async {
  SharedPreferences.setMockInitialValues({});
  final api = base.LayoutApi(), cache = MusicCache(api);
  final c = EvalController(api, cache, EvalAudio(api, cache, phone: phone));
  c.preferences = await SharedPreferences.getInstance();
  await c.restoreCustomizationScope();
  await c.customize({'language':'ru','reducedMotion':true});
  c.loading=false;c.online=true;c.deviceId='local';
  c.tracks=List.generate(3, (i)=>WaveTrack({'id':'evaluate-$i','title':['Марсель — Был Өмірде','Ветер над морем','Пока город спит'][i],'artist':['Алихан Ғарышқан','Другой исполнитель','Другой голос'][i],'source':'soundcloud','artwork':'https://isolated.invalid/$i.jpg','duration':225,'playback':{'kind':'audio','url':'/own.wav'}}));
  c.audio.tracks=c.tracks;c.audio.current=c.tracks.first;
  c.connect={'independent':true,'activeDeviceId':'remote','activeDeviceName':'Chrome · Windows'};
  c.settings['lyrics']=true;c.settings['lyricsUnderCover']=true;
  api.lyricSynchronized=true;
  api.lyricLines=[{'time':0,'text':'Жұлдыздар жарқырайды,'},{'time':20,'text':'Толқындай сарқырайды'},{'time':40,'text':'Hidden third line'}];
  return c;
}
Future<void> settle(WidgetTester t) async {await t.pump();await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:40)));await t.pumpAndSettle();}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {await loadAppFonts();await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('com.ryanheise.audio_session'),(_)async=>null);});
  for(final item in [(1440.0,900.0,1.0,false,true),(1440.0,900.0,1.25,false,true),(900.0,595.0,1.25,false,true),(768.0,900.0,1.0,false,true),(390.0,844.0,1.0,true,true),(320.0,568.0,1.25,true,false)]){
    testWidgets('Independent evaluator player ${item.$1} ${item.$2} ${item.$3} cover3d ${item.$5}',(t)async{
      await installArtworkFixture();final c=(await t.runAsync(()=>controller(item.$4)))!;
      await t.runAsync(()=>c.customize({'appearance':{'cover3d':item.$5}}));
      await base.viewport(t,Size(item.$1,item.$2));
      await t.pumpWidget(a.shell(c,PlayerPage(controller:c,onMore:(_){}),scale:item.$3));await settle(t);
      expect(t.takeException(),isNull);expect(find.byKey(const Key('mini-lyrics-frame')),findsOneWidget);expect(find.text('Hidden third line'),findsNothing);
      expect(t.getRect(find.byKey(const Key('mini-lyrics-frame'))).bottom,lessThanOrEqualTo(t.getRect(find.byKey(const Key('player-seek'))).top));
      if(item.$1>=1200){expect(find.byKey(const Key('player-wide-layout')),findsOneWidget);final play=t.getRect(find.byKey(const Key('player-play')));expect(play.top,greaterThan(0));expect(play.bottom,lessThan(item.$2));expect(t.widget<AlbumStage>(find.byType(AlbumStage)).size,302);}
      if(item.$4){expect(c.audio.hardwareVolume,isTrue);expect(find.byKey(const Key('player-volume')),findsNothing);}
      await base.screenshot(t,'parity23-evaluator-${item.$1.toInt()}-${item.$2.toInt()}-${item.$3}-initial');
      await t.ensureVisible(find.byKey(const Key('player-play')));await t.pumpAndSettle();expect(t.getRect(find.byKey(const Key('player-play'))).bottom,lessThanOrEqualTo(item.$2));
      await base.screenshot(t,'parity23-evaluator-${item.$1.toInt()}-${item.$2.toInt()}-${item.$3}-controls');
      c.settings['lyricsUnderCover']=false;c.render();await t.pump();expect(find.byKey(const Key('mini-lyrics-frame')),findsNothing);
      await base.clean(t,c);clearArtworkFixture();
    });
  }
  testWidgets('Evaluator cloud directory still shows distinct tracks and separate LAN with refresh',(t)async{
    await installArtworkFixture();final c=(await t.runAsync(()=>controller(true)))!;c.network=true;
    c.devices=[{'id':'local','name':'GlukWave · Android','online':true,'track':c.tracks[0].json,'state':{'trackId':c.tracks[0].id,'playing':true}},{'id':'remote','name':'Chrome · Windows','online':true,'track':c.tracks[1].json,'state':{'trackId':c.tracks[1].id,'playing':true}}];
    c.peers=[{'id':'lan-peer','name':'Nearby laptop','online':true,'track':c.tracks[2].json,'state':{'trackId':c.tracks[2].id,'playing':true}}];
    await base.viewport(t,const Size(390,844));
    await t.pumpWidget(a.shell(c,Builder(builder:(context)=>TextButton(key:const Key('eval-open'),onPressed:()=>showConnectPicker(context,c),child:const Text('Open'))),scale:1));await settle(t);await t.tap(find.byKey(const Key('eval-open')));await settle(t);
    for(final title in c.tracks.map((x)=>x.title)){expect(find.text(title),findsOneWidget);}
    expect(find.byKey(const Key('connect-lan-section')),findsOneWidget);expect(find.text('Chrome · Windows'),findsOneWidget);
    c.render();await t.pump();for(final title in c.tracks.map((x)=>x.title)){expect(find.text(title),findsOneWidget);}
    await base.screenshot(t,'parity23-evaluator-cloud-lan-directory');expect(t.takeException(),isNull);
    await base.clean(t,c);clearArtworkFixture();
  });
  testWidgets('Evaluator preview adoption refreshes metadata and compact lyrics remain above seek',(t)async{
    await installArtworkFixture();final c=(await t.runAsync(()=>controller(false)))!;final initial=c.tracks[1];
    await base.viewport(t,const Size(1440,900));await t.pumpWidget(a.shell(c,PlayerPage(controller:c,initialTrack:initial,onMore:(_){}),scale:1));await settle(t);
    expect(find.text(initial.title),findsWidgets);c.audio.current=c.tracks[2];c.render();await t.pump();expect(find.text(initial.title),findsWidgets);
    c.audio.current=initial;c.render();await t.pump();c.audio.current=c.tracks[2];c.render();await settle(t);expect(find.text(initial.title),findsNothing);expect(find.text(c.tracks[2].title),findsWidgets);await base.screenshot(t,'parity23-evaluator-preview-next');
    await t.pumpWidget(const SizedBox());await base.viewport(t,const Size(410,172));await t.pumpWidget(a.shell(c,DesktopCompactPlayer(controller:c),scale:1));await settle(t);expect(find.byType(MiniLyrics),findsOneWidget);expect(find.text('Жұлдыздар жарқырайды,'),findsOneWidget);await base.screenshot(t,'parity23-evaluator-compact-lyrics');expect(t.takeException(),isNull);
    await base.clean(t,c);clearArtworkFixture();
  });
}
