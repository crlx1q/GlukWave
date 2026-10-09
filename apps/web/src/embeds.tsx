import { t, useLocale } from './locale';
import { useEffect, useMemo, useRef, useState } from 'react';
import { ChevronDown, ChevronUp, ExternalLink } from 'lucide-react';
import { usePlayer, type EmbedController } from './player';
import { sourceNames } from './types';
import { useStore } from './store';
type YouTubeInstance={playVideo:()=>void;pauseVideo:()=>void;seekTo:(position:number,allowSeekAhead:boolean)=>void;setVolume:(volume:number)=>void;getCurrentTime:()=>number;getDuration:()=>number;getPlayerState:()=>number;destroy:()=>void};
type SCWidget={bind:(event:string,handler:()=>void)=>void;unbind:(event:string)=>void;play:()=>void;pause:()=>void;seekTo:(position:number)=>void;setVolume:(volume:number)=>void;getPosition:(callback:(position:number)=>void)=>void;getDuration:(callback:(duration:number)=>void)=>void;isPaused:(callback:(paused:boolean)=>void)=>void};
type SpotifyController={addListener:(event:string,handler:(data:{data:{position:number;duration:number;isPaused:boolean}})=>void)=>void;play:()=>void;pause:()=>void;seek:(position:number)=>void;destroy:()=>void};
type SpotifySDK={createController:(element:HTMLElement,options:unknown,callback:(controller:SpotifyController)=>void)=>void};
type ProviderWindow=Window & {YT?:{Player:new(element:HTMLElement,options:unknown)=>YouTubeInstance};onYouTubeIframeAPIReady?:()=>void;SC?:{Widget:((element:HTMLIFrameElement)=>SCWidget)&{Events:{READY:string;PLAY:string;PAUSE:string;FINISH:string}}};onSpotifyIframeApiReady?:(api:SpotifySDK)=>void;gwSpotifySdk?:SpotifySDK};
function loadScript(source:string){let script=document.querySelector<HTMLScriptElement>(`script[src="${source}"]`);if(!script){script=document.createElement('script');script.src=source;script.async=true;document.head.appendChild(script);}return script;}
/** This is the only official provider host. It stays in this shell position while
 * routes and the fullscreen layer change; visual placement never reparents it. */
export function ProviderEmbed(){useLocale();
 const player=usePlayer(),store=useStore(),ref=useRef<HTMLDivElement>(null),iframe=useRef<HTMLIFrameElement>(null),[ready,setReady]=useState(false),[expanded,setExpanded]=useState(false);
 const current=useRef({player,store});current.current={player,store};const track=player.track,playback=player.playback;
 const frameSource=useMemo(()=>{if(!track||!playback)return '';if(playback.kind!=='soundcloud')return playback.embedUrl||'';const url=new URL(playback.embedUrl||'https://w.soundcloud.com/player/');url.searchParams.set('url',track.sourceUrl);for(const [name,value] of Object.entries({auto_play:'false',visual:'false',show_artwork:'false',show_comments:'false',show_playcount:'false',show_user:'false',sharing:'false',download:'false',buying:'false',hide_related:'true',single_active:'true'}))url.searchParams.set(name,value);return url.href;},[track?.id,track?.sourceUrl,playback?.kind,playback?.embedUrl]);
 useEffect(()=>{
  setReady(false);if(!track||!playback||playback.kind==='audio')return;
  let cancelled=false,timer:ReturnType<typeof setInterval>|undefined,cleanup:(()=>void)|undefined,scriptCleanup:(()=>void)|undefined;
  const providerWindow=window as ProviderWindow,account=store.user?.id;
  const alive=()=>!cancelled&&current.current.player.track?.id===track.id&&current.current.player.playback?.kind===playback.kind&&current.current.store.user?.id===account;
  const install=(controller:EmbedController)=>{if(!alive()){controller.destroy?.();return;}current.current.player.embedReady(controller);setReady(true);};
  const update=(position:number,playing:boolean,total?:number)=>{if(alive())current.current.player.embedUpdate(position,playing,total);};
  const finish=()=>{if(alive())current.current.player.finish();};
  if(playback.kind==='soundcloud'){
   const start=()=>{
    if(!alive()||!iframe.current||!providerWindow.SC)return;
    const sdk=providerWindow.SC.Widget,widget=sdk(iframe.current);let destroyed=false,installed=false;
    const read=()=>{if(!alive()||destroyed)return;widget.getPosition(position=>{if(!alive()||destroyed)return;widget.isPaused(paused=>{if(!alive()||destroyed)return;widget.getDuration(duration=>{if(!destroyed)update(position/1000,!paused,duration/1000);});});});};
    const destroy=()=>{if(destroyed)return;destroyed=true;widget.pause();for(const event of [sdk.Events.READY,sdk.Events.PLAY,sdk.Events.PAUSE,sdk.Events.FINISH])widget.unbind(event);if(timer)clearInterval(timer);};
    widget.bind(sdk.Events.READY,()=>{if(!alive()||installed)return;installed=true;install({play:()=>widget.play(),pause:()=>widget.pause(),seek:position=>widget.seekTo(position*1000),volume:volume=>widget.setVolume(volume*100),destroy});read();timer=setInterval(read,750);});
    widget.bind(sdk.Events.PLAY,read);widget.bind(sdk.Events.PAUSE,read);widget.bind(sdk.Events.FINISH,finish);cleanup=destroy;
   };
   if(providerWindow.SC)start();else{const script=loadScript('https://w.soundcloud.com/player/api.js');script.addEventListener('load',start,{once:true});scriptCleanup=()=>script.removeEventListener('load',start);}
  }else if(playback.kind==='youtube'){
   const start=()=>{
    if(!alive()||!ref.current||!providerWindow.YT)return;const element=document.createElement('div');ref.current.replaceChildren(element);
    const instance=new providerWindow.YT.Player(element,{width:'100%',height:'100%',videoId:track.sourceId,playerVars:{playsinline:1,rel:0,origin:location.origin},events:{onReady:()=>{install({play:()=>instance.playVideo(),pause:()=>instance.pauseVideo(),seek:position=>instance.seekTo(position,true),volume:volume=>instance.setVolume(volume*100),destroy:()=>instance.destroy()});if(alive())timer=setInterval(()=>{if(alive())update(instance.getCurrentTime()||0,instance.getPlayerState()===1,instance.getDuration());},750);},onStateChange:(event:{data:number})=>{if(!alive())return;update(instance.getCurrentTime()||0,event.data===1,instance.getDuration());if(event.data===0)finish();},onError:()=>{if(alive())current.current.store.notify(t('copy.375'),true);}}});cleanup=()=>instance.destroy();
   };
   if(providerWindow.YT?.Player)start();else{const previous=providerWindow.onYouTubeIframeAPIReady,handler=()=>{previous?.();start();};providerWindow.onYouTubeIframeAPIReady=handler;loadScript('https://www.youtube.com/iframe_api');scriptCleanup=()=>{if(providerWindow.onYouTubeIframeAPIReady===handler)providerWindow.onYouTubeIframeAPIReady=previous;};}
  }else if(playback.kind==='spotify'){
   const start=(sdk:SpotifySDK)=>{if(!alive()||!ref.current)return;ref.current.replaceChildren();sdk.createController(ref.current,{width:'100%',height:152,uri:`spotify:track:${track.sourceId}`},instance=>{if(!alive()){instance.destroy();return;}install({play:()=>instance.play(),pause:()=>instance.pause(),seek:position=>instance.seek(position),destroy:()=>instance.destroy()});instance.addListener('playback_update',event=>update(event.data.position/1000,!event.data.isPaused,event.data.duration/1000));cleanup=()=>instance.destroy();});};
   if(providerWindow.gwSpotifySdk)start(providerWindow.gwSpotifySdk);else{const previous=providerWindow.onSpotifyIframeApiReady,handler=(sdk:SpotifySDK)=>{providerWindow.gwSpotifySdk=sdk;previous?.(sdk);start(sdk);};providerWindow.onSpotifyIframeApiReady=handler;loadScript('https://open.spotify.com/embed/iframe-api/v1');scriptCleanup=()=>{if(providerWindow.onSpotifyIframeApiReady===handler)providerWindow.onSpotifyIframeApiReady=previous;};}
  }else setReady(true);
  return()=>{cancelled=true;scriptCleanup?.();if(timer)clearInterval(timer);try{cleanup?.();}catch{/* A removed provider frame has no playback left. */}};
 },[track?.id,playback?.kind,frameSource,store.user?.id]);
 if(!track||!playback||playback.kind==='audio')return null;
 const collapsible=playback.kind==='soundcloud',open=!collapsible||expanded||!ready||player.autoplayBlocked;
 return <aside className={`provider-stage ${playback.kind} persistent-provider ${player.full?'in-full':''} ${open?'expanded':'collapsed'}`} aria-label={t('template.020', {v0: sourceNames[track.source]})} data-ready={ready}>
  <div className="provider-stage-heading">{collapsible?<button type="button" onClick={()=>setExpanded(!open)} aria-expanded={open} aria-label={open?t('copy.376'):t('copy.377')}><span><i className={player.state.playing?'source-playing':''}/>{sourceNames[track.source]}</span>{open?<ChevronDown size={15}/>:<ChevronUp size={15}/>}</button>:<span>{sourceNames[track.source]}{' '}{t('copy.378')}</span>}<a href={track.sourceUrl} target="_blank" rel="noopener noreferrer" aria-label={t('copy.379')}><ExternalLink size={14}/></a></div>
  <div className="provider-body" inert={collapsible&&!open} aria-hidden={collapsible&&!open}>{playback.kind==='soundcloud'?<iframe key={track.id} ref={iframe} src={frameSource} allow="autoplay" title={`SoundCloud: ${track.title}`} height="84"/>:playback.kind==='yandex'?<iframe key={track.id} src={frameSource} allow="autoplay" title={t('template.021', {v0: track.title})} height="210"/>:<div ref={ref} className="provider-frame"/>}{!ready&&<div className="provider-loading skeleton" role="status">{t('copy.380')}</div>}{playback.kind==='spotify'&&<small className="provider-note">{t('copy.381')}</small>}</div>
 </aside>;
}
