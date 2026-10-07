import { t, useLocale } from './locale';
import { useEffect, useRef, useState } from 'react';
import { Cloud, Compass, Heart, Music2, Plus, Waves } from 'lucide-react';
import { useStore } from './store';
import { usePlayer } from './player';
import { api, errorText } from './api';
import { IconButton } from './ui';
import { AnimatedIcon } from './morph-icon';
import { WaveVisual } from './wave';
import { trackCount, type Track } from './types';

const getMoods=()=>[
  {id:'personal',label:t('copy.382'),query:'chill electronic',lines:[t('copy.383'),t('copy.384')],caption:t('copy.385'),Icon:Heart},
  {id:'calm',label:t('copy.386'),query:'lofi hip hop',lines:[t('copy.387'),t('copy.388')],caption:t('copy.389'),Icon:Cloud},
  {id:'focus',label:t('copy.390'),query:'ambient instrumental',lines:[t('copy.391'),t('copy.392')],caption:t('copy.393'),Icon:Waves},
  {id:'energy',label:t('copy.394'),query:'energetic electronic',lines:[t('copy.395'),t('copy.396')],caption:t('copy.397'),Icon:Compass},
  {id:'night',label:t('copy.398'),query:'late night jazz',lines:[t('copy.399'),t('copy.400')],caption:t('copy.369'),Icon:Music2}
] as const;

export function PersonalWave({upload}:{upload:()=>void}) {useLocale();
  const moods=getMoods(),store=useStore(),player=usePlayer(),key=`gw-mood:${store.user?.id||'guest'}`;
  const [selected,setSelected]=useState(()=>{try{return moods.find(item=>item.id===localStorage.getItem(key))?.id||'personal';}catch{return 'personal';}}),[busy,setBusy]=useState(false),[waveQueue,setWaveQueue]=useState<Track[]>([]),request=useRef<AbortController|null>(null);
  const mood=moods.find(item=>item.id===selected)!,liked=store.library.tracks.filter(track=>store.library.likedIds.includes(track.id)),personal=liked.length?liked:store.library.tracks;
  const playing=player.state.playing&&waveQueue.some(track=>track.id===player.track?.id);
  useEffect(()=>()=>request.current?.abort(),[]);
  const choose=(id:typeof selected)=>{request.current?.abort();request.current=null;setBusy(false);setSelected(id);try{localStorage.setItem(key,id);}catch{/* Mood still applies when storage is unavailable. */}};
  const start=async()=>{
    if(playing){await player.command({command:'pause'});return;}
    if(selected==='personal'&&personal.length){setWaveQueue(personal);await player.playTrack(personal[Math.floor(Math.random()*personal.length)],personal);return;}
    const controller=new AbortController();request.current?.abort();request.current=controller;setBusy(true);
    try{const result=await api<{tracks:Track[]}>(`/search?q=${encodeURIComponent(mood.query)}&source=all`,{signal:controller.signal});if(controller.signal.aborted)return;if(result.tracks.length){setWaveQueue(result.tracks);await player.playTrack(result.tracks[Math.floor(Math.random()*result.tracks.length)],result.tracks);}else{store.setQuery(mood.query);store.setSource('all');store.navigate('search');store.notify(t('copy.401'));}}
    catch(error){if(!controller.signal.aborted)store.notify(errorText(error),true);}finally{if(request.current===controller){request.current=null;setBusy(false);}}
  };
  return <><section className="wave-hero"><WaveVisual/><div className="hero-orbit"/><div className="hero-orbit orbit-two"/><div className="hero-top"><span><i className="pulse-dot"/>{t('copy.402')}</span><span>GLUKWAVE / YOUR FREQUENCY</span></div><div className="hero-copy"><h2>{t('copy.368')}<span>.</span></h2><p>{mood.lines[0]}<br/>{mood.lines[1]}</p><div className="hero-actions"><button className="wave-play" disabled={busy} onClick={()=>void start()}><AnimatedIcon name={playing?'pause':'play'} size={17}/>{busy?t('copy.403'):playing?t('copy.404'):selected==='personal'&&!personal.length?t('copy.405'):t('copy.406')}</button><IconButton title={t('copy.407')} className="icon-btn hero-upload" onClick={upload}><Plus size={19}/></IconButton></div></div><div className="hero-bottom"><span className="wave-live" aria-hidden="true"><i/><i/><i/><i/><i/></span><span>{selected==='personal'&&personal.length?t('template.019', {v0: trackCount(personal.length)}):mood.caption}</span><span className="infinity-label">∞ <small>{t('copy.408')}</small></span></div></section><div className="mood-row"><span className="mood-label">{t('copy.409')}</span><div className="mood-scroll">{moods.map(({id,label,Icon})=><button className={`mood-chip ${id===selected?'selected':''}`} key={id} aria-pressed={id===selected} onClick={()=>choose(id)}><Icon size={14}/>{label}</button>)}</div></div></>;
}
