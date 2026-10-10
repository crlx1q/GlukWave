import {SourceMark} from './ui';
import {ScrollingLabel} from './scrolling-label';
import { createRoot } from 'react-dom/client';
import { useEffect, useMemo, useState } from 'react';
import { LocaleProvider, t, useLocale } from './locale';
import { time, type PaletteColors, type PlayerState, type Track } from './types';
import { MotionIcon } from './morph-icon';
import { ContinuousRange } from './continuous-range';
import { useDocumentVisible } from './visual-lifecycle';
import './motion-controls.css';

type MiniState={trackLoading?:boolean;track?:Track;state:Partial<PlayerState>;duration:number;palette?:PaletteColors;motion?:boolean;speed?:number};
function Mini(){
 const locale=useLocale(),visible=useDocumentVisible(),id=new URLSearchParams(location.search).get('device'),channel=useMemo(()=>new BroadcastChannel('glukwave-mini-'+id),[id]),[data,setData]=useState<MiniState>({state:{playing:false},duration:0});
 useEffect(()=>{
  channel.onmessage=event=>{if(event.data?.type==='state')setData(event.data);};
  const subscribe=()=>channel.postMessage({type:document.hidden?'unsubscribe':'subscribe'});
  const leave=()=>channel.postMessage({type:'unsubscribe'});
  document.addEventListener('visibilitychange',subscribe);window.addEventListener('pagehide',leave);subscribe();
  return()=>{leave();document.removeEventListener('visibilitychange',subscribe);window.removeEventListener('pagehide',leave);channel.close();};
 },[channel]);
 useEffect(()=>{document.title=data.state.playing&&data.track?data.track.title+' · GlukWave':'GlukWave';},[data.track?.id,data.state.playing,locale.language]);
 useEffect(()=>{
  if(data.palette){const {bg,surface,ink,accent}=data.palette,root=document.documentElement;for(const [key,value]of Object.entries({bg,surface,ink,accent}))root.style.setProperty('--'+key,value);root.style.setProperty('--line','color-mix(in srgb,'+ink+' 18%,'+bg+')');}
  document.documentElement.dataset.motion=data.motion?'full':'reduce';
 },[data.palette,data.motion]);
 const send=(command:string,position?:number)=>channel.postMessage({command,position}),iconMotion=visible&&data.motion!==false;
 return <>
  <header><img className="track-loading-cover" data-loading={data.trackLoading} aria-busy={data.trackLoading} src={data.track?.artwork||'/brand/logo.png'} alt=""/><p><b><ScrollingLabel text={data.track?.title||'GlukWave'} motion={iconMotion}/></b><small><ScrollingLabel text={data.track?.artist||t('mini.empty')} motion={iconMotion}/></small>{data.track?.playback.attribution&&/^https:\/\//i.test(data.track.playback.attribution.sourceUrl)&&<a className="mini-source-credit" href={data.track.playback.attribution.sourceUrl} target="_blank" rel="noopener noreferrer"><SourceMark source={data.track.playback.attribution.source}/><span>{data.track.playback.attribution.artist}</span><b>{data.track.playback.attribution.source==='soundcloud'?'SoundCloud':data.track.playback.attribution.source}</b></a>}</p></header>
  <section>
   <button disabled={!data.track} onClick={()=>send('previous')} aria-label={t('copy.627')}><MotionIcon name="previous" size={20} motion={iconMotion} speed={data.speed}/></button>
   <button disabled={!data.track} onClick={()=>send(data.state.playing?'pause':'play')} aria-label={t(data.state.playing?'copy.628':'copy.629')}><MotionIcon name={data.state.playing?'pause':'play'} size={22} motion={iconMotion} speed={data.speed}/></button>
   <button disabled={!data.track} onClick={()=>send('next')} aria-label={t('copy.630')}><MotionIcon name="next" size={20} motion={iconMotion} speed={data.speed}/></button>
  </section>
  <ContinuousRange value={Math.min(data.duration||1,data.state.position||0)} max={Math.max(1,data.duration)} step={.1} resetKey={data.track?.id} onCommit={position=>send('seek',position)} disabled={!data.track} label={t('copy.634')}/>
  <div className="times"><span>{time(data.state.position)}</span><span>{time(data.duration)}</span></div>
 </>;
}
createRoot(document.getElementById('root')!).render(<LocaleProvider><Mini/></LocaleProvider>);
