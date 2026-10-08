import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../l10n/wave_localizations.dart';

/// Only official, visible provider players are controlled here. This bridge
/// never receives a GlukWave credential and never extracts an audio stream.
class ProviderPlayer extends ChangeNotifier {
  WaveTrack? track;
  bool playing = false, ready = false, loading = false;
  double position = 0, duration = 0;
  String? error;
  int generation = 0;
  bool _requestPending = false;
  Completer<void>? _ready;
  Completer<void>? _started;
  Future<void> Function(String script)? evaluate;
  VoidCallback? onEnded;
  void Function(String message)? onError;

  Future<void> load(
    WaveTrack value, {
    double position = 0,
    double volume = .8,
    bool playing = true,
  }) async {
    if (!value.embedded) throw const WaveException('Unsupported provider');
    final revision = ++generation;
    _requestPending = true;
    if (_ready?.isCompleted == false) _ready!.complete();
    if (_started?.isCompleted == false) _started!.complete();
    // Release the old player before replacing its document.
    await command('pause');
    track = value;
    this.position = position;
    duration = value.duration;
    this.playing = false;
    ready = false;
    loading = true;
    error = null;
    _ready = Completer<void>();
    notifyListeners();
    try {
      await _ready!.future.timeout(const Duration(seconds: 25));
      if (generation != revision) return;
      await command('volume', {'volume': volume});
      if (position > 0) await command('seek', {'position': position});
      if (playing) {
        _started = Completer<void>();
        await command('play');
        await _started!.future.timeout(const Duration(seconds: 12));
      }
    } catch (cause) {
      if (generation != revision) return;
      if (generation == revision) {
        this.playing = false;
        loading = false;
        error ??= cause is TimeoutException
            ? 'provider.timeout'
            : 'provider.failed';
        notifyListeners();
      }
      throw WaveException(wt(error ?? 'provider.failed'));
    } finally {
      if (generation == revision) _requestPending = false;
    }
  }

  void cancelPendingLoad() {
    if (!_requestPending) return;
    generation++;
    _requestPending = false;
    if (_ready?.isCompleted == false) _ready!.complete();
    if (_started?.isCompleted == false) _started!.complete();
    track = null;
    evaluate = null;
    loading = playing = ready = false;
    notifyListeners();
  }

  Future<void> command(String command, [Json data = const {}]) async {
    final run = evaluate;
    if (run == null || !ready) return;
    await run(
      'window.waveCommand(${jsonEncode(command)},${jsonEncode(data)});',
    );
  }

  void receive(int revision, dynamic payload) {
    if (revision != generation) return;
    final data = object(payload);
    final event = data['event'];
    if (event == 'ready') {
      ready = true;
      loading = false;
      if (_ready?.isCompleted == false) _ready!.complete();
    } else if (event == 'error') {
      error = 'provider.failed';
      playing = loading = false;
      if (_ready?.isCompleted == false) {
        _ready!.completeError(WaveException(error!));
      }
      if (_started?.isCompleted == false) {
        _started!.completeError(WaveException(error!));
      }
      onError?.call(error!);
    } else if (event == 'state') {
      playing = data['playing'] == true;
      loading = data['loading'] == true;
      if (playing && _started?.isCompleted == false) _started!.complete();
    } else if (event == 'position') {
      position = number(data['position']).clamp(0, double.infinity);
      final length = number(data['duration']);
      if (length > 0) duration = length;
    } else if (event == 'ended') {
      playing = false;
      onEnded?.call();
    }
    notifyListeners();
  }

  Future<void> clear() async {
    await command('pause');
    generation++;
    _requestPending = false;
    if (_ready?.isCompleted == false) _ready!.complete();
    if (_started?.isCompleted == false) _started!.complete();
    track = null;
    playing = loading = ready = false;
    position = duration = 0;
    evaluate = null;
    notifyListeners();
  }
}

String providerDocument(WaveTrack track, int generation, String origin) {
  final source = track.source;
  final sourceUri = Uri.tryParse(track.sourceUrl);
  if (source == 'soundcloud' &&
      (sourceUri?.scheme != 'https' ||
          ![
            'soundcloud.com',
            'www.soundcloud.com',
            'api.soundcloud.com',
          ].contains(sourceUri?.host))) {
    throw const WaveException('Invalid SoundCloud source');
  }
  final sid =
      track.json['sourceId']?.toString() ??
      track.id.replaceFirst('youtube-', '');
  if (source == 'youtube' && !RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(sid)) {
    throw const WaveException('Invalid YouTube source');
  }
  final body = source == 'soundcloud'
      ? '<iframe id="provider" title="SoundCloud" allow="autoplay" src="https://w.soundcloud.com/player/?url=${Uri.encodeComponent(track.sourceUrl)}&amp;auto_play=false&amp;visual=false&amp;show_artwork=true&amp;show_comments=false&amp;show_user=true&amp;hide_related=true"></iframe><script src="https://w.soundcloud.com/player/api.js"></script>'
      : '<div id="provider"></div><script src="https://www.youtube.com/iframe_api"></script>';
  final setup = source == 'soundcloud'
      ? '''
const player=SC.Widget(document.getElementById('provider'));
player.bind(SC.Widget.Events.READY,()=>{send({event:'ready'});player.getDuration(d=>send({event:'position',position:0,duration:d/1000}));});
player.bind(SC.Widget.Events.PLAY,()=>send({event:'state',playing:true}));
player.bind(SC.Widget.Events.PAUSE,()=>send({event:'state',playing:false}));
player.bind(SC.Widget.Events.FINISH,()=>send({event:'ended'}));
player.bind(SC.Widget.Events.ERROR,()=>send({event:'error'}));
player.bind(SC.Widget.Events.PLAY_PROGRESS,e=>send({event:'position',position:e.currentPosition/1000}));
window.waveCommand=(c,d)=>{if(c==='play')player.play();if(c==='pause'||c==='stop')player.pause();if(c==='seek')player.seekTo(d.position*1000);if(c==='volume')player.setVolume(d.volume*100);};
'''
      : '''
let player;
window.onYouTubeIframeAPIReady=()=>{player=new YT.Player('provider',{width:'100%',height:'100%',videoId:${jsonEncode(sid)},playerVars:{playsinline:1,controls:1,origin:${jsonEncode(origin)}},events:{onReady:()=>send({event:'ready'}),onStateChange:e=>{send({event:'state',playing:e.data===1,loading:e.data===3});if(e.data===0)send({event:'ended'});},onError:()=>send({event:'error'}),onAutoplayBlocked:()=>send({event:'state',playing:false})}});};
window.waveCommand=(c,d)=>{if(!player)return;if(c==='play')player.playVideo();if(c==='pause'||c==='stop')player.pauseVideo();if(c==='seek')player.seekTo(d.position,true);if(c==='volume')player.setVolume(d.volume*100);};
setInterval(()=>{if(player&&player.getCurrentTime)send({event:'position',position:player.getCurrentTime(),duration:player.getDuration()});},500);
''';
  // The bridge handler belongs exclusively to this controlled top document.
  // Provider iframes communicate through their official postMessage APIs.
  return '''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;width:100%;height:100%;background:transparent;overflow:hidden}iframe,#provider{width:100%;height:100%;border:0;display:block}</style></head><body>$body<script>
const pending=[];function send(data){if(window.flutter_inappwebview)window.flutter_inappwebview.callHandler('waveProvider',$generation,data);else pending.push(data);}
window.addEventListener('flutterInAppWebViewPlatformReady',()=>{for(const data of pending.splice(0))send(data);});
$setup
</script></body></html>''';
}
