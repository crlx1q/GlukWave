import { t, useLocale } from './locale';
import { useEffect, useRef, useState } from 'react';
import { Cloud, Compass, Heart, Music2, Plus, SlidersHorizontal, Waves } from 'lucide-react';
import { useStore } from './store';
import { usePlayer } from './player';
import { api, errorText } from './api';
import { IconButton } from './ui';
import { AnimatedIcon } from './morph-icon';
import { WaveVisual } from './wave';
import { trackCount, type Track } from './types';
const getMoods=()=>[
 {id:'personal',label:t('copy.382'),query:'chill electronic',caption:t('copy.385'),Icon:Heart},
 {id:'calm',label:t('copy.386'),query:'lofi hip hop',caption:t('copy.389'),Icon:Cloud},
 {id:'focus',label:t('copy.390'),query:'ambient instrumental',caption:t('copy.393'),Icon:Waves},
 {id:'energy',label:t('copy.394'),query:'energetic electronic',caption:t('copy.397'),Icon:Compass},
 {id:'night',label:t('copy.398'),query:'late night jazz',caption:t('copy.369'),Icon:Music2}
] as const;
export function PersonalWave({upload}:{upload:()=>void}) {useLocale();
 const moods=getMoods(),store=useStore(),player=usePlayer(),key=`gw-mood:${store.user?.id||'guest'}`;
 const [selected,setSelected]=useState(()=>{try{return moods.find(item=>item.id===localStorage.getItem(key))?.id||'personal';}catch{return 'personal';}}),[busy,setBusy]=useState(false),[waveQueue,setWaveQueue]=useState<Track[]>([]),request=useRef<AbortController|null>(null);
 const mood=moods.find(item=>item.id===selected)!,liked=store.library.tracks.filter(track=>store.library.likedIds.includes(track.id)),personal=liked.length?liked:store.library.tracks;
 const playing=player.state.playing&&waveQueue.some(track=>track.id===player.track?.id),canResume=!!player.track&&waveQueue.some(track=>track.id===player.track?.id);
 useEffect(()=>()=>request.current?.abort(),[]);
 const choose=(id:typeof selected)=>{request.current?.abort();request.current=null;setBusy(false);setSelected(id);setWaveQueue([]);try{localStorage.setItem(key,id);}catch{/* This choice still works without storage. */}};
 const start=async()=>{
  if(playing){await player.command({command:'pause'});return;}
  if(canResume){await player.command({command:'play'});return;}
  if(selected==='personal'&&personal.length){setWaveQueue(personal);await player.playTrack(personal[Math.floor(Math.random()*personal.length)],personal);return;}
  const controller=new AbortController();request.current?.abort();request.current=controller;setBusy(true);
  try{const result=await api<{tracks:Track[]}>(`/search?q=${encodeURIComponent(mood.query)}&source=all`,{signal:controller.signal});if(controller.signal.aborted)return;if(result.tracks.length){setWaveQueue(result.tracks);await player.playTrack(result.tracks[Math.floor(Math.random()*result.tracks.length)],result.tracks);}else{store.setQuery(mood.query);store.setSource('all');store.navigate('search');store.notify(t('copy.401'));}}
  catch(error){if(!controller.signal.aborted)store.notify(errorText(error),true);}finally{if(request.current===controller){request.current=null;setBusy(false);}}
 };
 return <section className={`personal-wave ${playing?'is-playing':''}`} aria-labelledby="personal-wave-title">
  <div className="wave-hero"><WaveVisual/>
   <header className="wave-heading"><div><h2 id="personal-wave-title">{t('copy.368')}</h2><p>{selected==='personal'&&personal.length?t('template.019',{v0:trackCount(personal.length)}):t('v7.wave.caption')}</p></div>
    <div className="wave-actions"><IconButton title={t('copy.407')} onClick={upload}><Plus size={18}/></IconButton><IconButton title={t('v7.wave.settings')} onClick={()=>{store.navigate('settings');location.hash='settings?section=appearance';}}><SlidersHorizontal size={18}/></IconButton><button className="wave-play" disabled={busy} aria-label={busy?t('copy.403'):playing?t('copy.404'):t('copy.406')} onClick={()=>void start()}>{busy?<span className="loader"/>:<AnimatedIcon name={playing?'pause':'play'} size={23}/>}</button></div>
   </header>
   {playing&&player.track&&<div className="wave-current"><span className="wave-live" aria-hidden="true"><i/><i/><i/><i/><i/></span><span>{player.track.artist}<b>{player.track.title}</b></span></div>}
  </div>
  <div className="mood-row"><span className="mood-label">{t('copy.409')}</span><div className="mood-scroll">{moods.map(({id,label,Icon})=><button className={`mood-chip ${id===selected?'selected':''}`} key={id} aria-pressed={id===selected} onClick={()=>choose(id)}><Icon size={15}/>{label}</button>)}</div></div>
 </section>;
}
