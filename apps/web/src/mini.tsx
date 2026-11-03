import {MiniAtmosphere} from './studio-ui';
import './studio31.css';
import './browser-compat';
import {ScrollingLabel} from './scrolling-label';
import { createRoot } from 'react-dom/client';
import { useEffect, useMemo, useState, useRef, useCallback } from 'react';
import { LocaleProvider, t, useLocale } from './locale';
import { time, type PaletteColors, type PlayerState, type Track } from './types';
import { MotionIcon,PlaybackMotionIcon } from './morph-icon';
import { ContinuousRange } from './continuous-range';
import {WheelVolume} from './wheel-volume';
import {PacketProgressClock,type ProgressSample} from './progress-clock';
import {ProgressTime} from './progress-paint';
import { useDocumentVisible } from './visual-lifecycle';
import './motion-controls.css';
import './playback-feedback.css';

type MiniState={miniBackground?:'cover'|'pixels'|'plain';progress?:ProgressSample;progressScope?:string;progressRevision?:number;trackLoading?:boolean;track?:Track;state:Partial<PlayerState>;duration:number;palette?:PaletteColors;motion?:boolean;speed?:number};
function Mini(){
 const locale=useLocale(),visible=useDocumentVisible(),id=new URLSearchParams(location.search).get('device'),channel=useMemo(()=>typeof BroadcastChannel==='function'?new BroadcastChannel('glukwave-mini-'+id):null,[id]),[data,setData]=useState<MiniState>({state:{playing:false},duration:0});
 const current=useRef(data);current.current=data;
 const clock=useRef(new PacketProgressClock());
 const readProgress=useCallback(()=>{const data=current.current,now=performance.now(),sample=data.progress||{position:data.state.position||0,duration:data.duration,playing:false,at:now};return clock.current.read(sample,`${data.progressScope}:${data.progressRevision}`,now);},[]);
 useEffect(()=>{
  if(!channel)return;
  channel.onmessage=event=>{if(event.data?.type==='state')setData({...event.data,progress:event.data.progress?{...event.data.progress,at:performance.now()}:undefined});};
  const subscribe=()=>channel?.postMessage({type:document.hidden?'unsubscribe':'subscribe'});
  const leave=()=>channel?.postMessage({type:'unsubscribe'});
  document.addEventListener('visibilitychange',subscribe);window.addEventListener('pagehide',leave);subscribe();
  return()=>{leave();document.removeEventListener('visibilitychange',subscribe);window.removeEventListener('pagehide',leave);channel.close();};
 },[channel]);
 useEffect(()=>{document.title=data.state.playing&&data.track?data.track.title+' · GlukWave':'GlukWave';},[data.track?.id,data.state.playing,locale.language]);
 useEffect(()=>{
  if(data.palette){const {bg,surface,ink,accent}=data.palette,root=document.documentElement;for(const [key,value]of Object.entries({bg,surface,ink,accent}))root.style.setProperty('--'+key,value);root.style.setProperty('--line','color-mix(in srgb,'+ink+' 18%,'+bg+')');}
  document.documentElement.dataset.motion=data.motion?'full':'reduce';document.documentElement.style.setProperty('--motion-speed',String(data.speed||1));
 },[data.palette,data.motion,data.speed]);
 const send=(command:string,position?:number)=>channel?.postMessage({command,position}),iconMotion=visible&&data.motion!==false;
 return <>
  <MiniAtmosphere track={data.track} mode={data.miniBackground||'cover'} motion={data.motion!==false&&visible}/><header><img className="track-loading-cover" data-loading={data.trackLoading} aria-busy={data.trackLoading} src={data.track?.artwork||'/brand/logo.png'} alt=""/><p><b><ScrollingLabel text={data.track?.title||'GlukWave'} motion={iconMotion}/></b><small><ScrollingLabel text={data.track?.artist||t('mini.empty')} motion={iconMotion}/></small></p></header>
  <section>
   <button disabled={!data.track} onClick={()=>send('previous')} aria-label={t('copy.627')}><MotionIcon name="previous" size={20} motion={iconMotion} speed={data.speed}/></button>
   <button className={`main-play ${data.trackLoading?'is-loading':''}`} aria-busy={!!data.trackLoading} data-loading={!!data.trackLoading} disabled={!data.track} onClick={()=>send(data.state.playing?'pause':'play')} aria-label={t(data.state.playing?'copy.628':'copy.629')}><PlaybackMotionIcon playing={!!data.state.playing} loading={!!data.trackLoading} size={22} motion={iconMotion} speed={data.speed}/></button>
   <button disabled={!data.track} onClick={()=>send('next')} aria-label={t('copy.630')}><MotionIcon name="next" size={20} motion={iconMotion} speed={data.speed}/></button>
  </section>
  <div className={`progress-line ${data.trackLoading?'is-loading':''}`} aria-busy={!!data.trackLoading}><ContinuousRange readProgress={readProgress} value={Math.min(data.duration||1,data.state.position||0)} max={Math.max(1,data.duration)} step={.1} resetKey={data.progressScope||data.track?.id} onCommit={position=>send('seek',position)} disabled={!data.track||data.trackLoading} label={t('copy.634')}/></div>
  <div className="times"><ProgressTime read={readProgress} value={data.state.position||0}/><WheelVolume className="mini-volume" value={data.state.volume??1} resetKey={data.progressScope} onChange={volume=>channel?.postMessage({command:'volume',volume})}>{(volume,wheelRevision)=><><button aria-label={t('copy.643')} onClick={()=>channel?.postMessage({command:'volume',volume:volume?0:.8})}><MotionIcon name={!volume?'muted':volume<.5?'volumeLow':'volume'} size={15} motion={iconMotion} speed={data.speed}/></button><ContinuousRange wheelRevision={wheelRevision} value={volume} max={1} step={.02} allowOffStep resetKey={data.progressScope} label={t('copy.643')} onCommit={volume=>channel?.postMessage({command:'volume',volume})}/></>}</WheelVolume><span>{time(data.duration)}</span></div>
 </>;
}
createRoot(document.getElementById('root')!).render(<LocaleProvider><Mini/></LocaleProvider>);
