import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glukwave/core/models.dart';
import 'package:glukwave/ui/album_stage.dart';
import 'package:glukwave/ui/player.dart';
import 'package:glukwave/ui/scrolling_label.dart';
import 'audio_design_test.dart' as audio;
import 'app_layout_test.dart' as base;
import 'helpers/fonts.dart';
import 'helpers/cover22_evaluator_artwork_fixture.dart';

void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 setUpAll(()async{
  await loadAppFonts();
  await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('com.ryanheise.audio_session'),(_)async=>null);
 });
 testWidgets('Evaluator actual painted circle extreme corner probe',(t)async{
  await installArtworkFixture();
  final c=(await t.runAsync(audio.makeController))!;
  const title='1 A.M Study Session 📚 - [lofi hip hop/chill beats]';
  final track=WaveTrack({'id':'corners','title':title,'artist':'Lofi Girl','album':title,'source':'soundcloud','duration':3673,'artwork':'https://qa.invalid/forest.jpg'});
  c.tracks=[track];c.audio.tracks=[track];c.audio.current=track;c.settings['lyricsUnderCover']=false;
  await base.viewport(t,const Size(1440,900));
  for(final scale in [1.0,1.25]){
    await t.pumpWidget(audio.shell(c,PlayerPage(controller:c,onMore:(_){}),scale:scale));await t.pumpAndSettle();
    final play=t.getRect(find.byKey(const Key('player-play')));
    expect(play.top,greaterThanOrEqualTo(0));expect(play.bottom,lessThanOrEqualTo(900));
    await base.screenshot(t,'cover22-evaluator-final-1440-initial-$scale');
  }
  await t.pumpWidget(audio.shell(c,PlayerPage(controller:c,onMore:(_){}),scale:1));await t.pumpAndSettle();
  final image=find.descendant(of:find.byKey(const Key('album-front-sleeve')),matching:find.byType(RawImage));
  for(var i=0;i<15;i++){
   if(image.evaluate().isNotEmpty&&t.widget<RawImage>(image.first).image!=null)break;
   await t.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:150)));await t.pump(const Duration(milliseconds:200));
  }
  expect(t.widget<RawImage>(image.first).image,isNotNull);
  final mouse=await t.createGesture(kind:PointerDeviceKind.mouse);await mouse.addPointer(location:t.getCenter(find.byKey(const Key('album-3d'))));await t.pump(const Duration(milliseconds:700));
  final results=<Map<String,dynamic>>[];
  var currentX=-9.0,currentY=-18.0;
  for(final pose in [const Offset(-38,-85),const Offset(-38,-90),const Offset(-38,-122),const Offset(38,-85),const Offset(38,92),const Offset(-38,92)]){
   final gesture=t.widget<GestureDetector>(find.byKey(const Key('album-3d')));
   gesture.onLongPressStart!(const LongPressStartDetails());
   gesture.onLongPressMoveUpdate!(LongPressMoveUpdateDetails(offsetFromOrigin:Offset((pose.dy-currentY)/.65,(currentX-pose.dx)/.22)));
   await t.pump();currentX=pose.dx;currentY=pose.dy;
   final matrix=t.widget<Transform>(find.byKey(const Key('album-3d-transform'))).transform;
   final bounds=t.getRect(find.byKey(const Key('album-stage-bounds'))),center=bounds.center;
   final side=t.widget<AlbumStage>(find.byType(AlbumStage)).size;
   final discLeft=t.widget<AnimatedPositioned>(find.byKey(const Key('album-record-position'))).left!;
   final titleBox=t.getRect(find.byWidgetPredicate((w)=>w is ScrollingLabel&&w.text==title));
   final circle=<Offset>[];
   for(var i=0;i<1024;i++){
    final a=i*math.pi*2/1024;
    circle.add(center+MatrixUtils.transformPoint(matrix,Offset(discLeft+side*.47-side/2+side*.47*math.cos(a),side*.47*math.sin(a))));
   }
   final top=circle.map((p)=>p.dy).reduce(math.min),bottom=circle.map((p)=>p.dy).reduce(math.max);
   final name='cover22-evaluator-final-native-corner-${pose.dx.toInt()}-${pose.dy.toInt()}';await base.screenshot(t,name);
   results.add({'x':pose.dx,'y':pose.dy,'size':side,'discLeft':discLeft,'stage':{'left':bounds.left,'top':bounds.top,'right':bounds.right,'bottom':bounds.bottom},'title':{'left':titleBox.left,'top':titleBox.top,'right':titleBox.right,'bottom':titleBox.bottom},'paintedCircle':{'top':top,'bottom':bottom,'gapToTitle':titleBox.top-bottom},'capture':'work/qa/native-$name.png'});
   expect(top,greaterThanOrEqualTo(bounds.top));expect(bottom,lessThanOrEqualTo(bounds.bottom));expect(bottom,lessThan(titleBox.top));expect(t.widget<AlbumStage>(find.byType(AlbumStage)).size,302);expect(t.takeException(),isNull);
  }
  await t.runAsync(()=>File('../../work/qa/cover22-native-evaluator-corners-final.json').writeAsString(jsonEncode(results)));
  await mouse.removePointer();await base.clean(t,c);clearArtworkFixture();
 });
}


