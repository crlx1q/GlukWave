import {t,useLocale} from './locale';
import {useEffect,useRef,useState} from 'react';
import {Cloud,Compass,Heart,Music2,Plus,SlidersHorizontal,Smile,Sun,Waves} from 'lucide-react';
import {useStore} from './store';
import {usePlayer} from './player';
import {errorText} from './api';
import {IconButton} from './ui';
import {ListeningMotionIcon,PlaybackIcon} from './morph-icon';
import {WaveVisual} from './wave';
const modes=['personal','favorites','discovery','popular'] as const;
const getMoods=()=>[
 {id:'personal',Icon:Heart},{id:'energy',Icon:Sun},{id:'happy',Icon:Smile},
 {id:'calm',Icon:Cloud},{id:'sad',Icon:Music2},{id:'focus',Icon:Waves},{id:'dream',Icon:Compass}
] as const;
type Mode=typeof modes[number];type Mood=ReturnType<typeof getMoods>[number]['id'];
function savedChoice(key:string){try{const value=JSON.parse(localStorage.getItem(key)||'null');return {mode:modes.includes(value?.mode)?value.mode as Mode:'personal' as Mode,mood:getMoods().some(item=>item.id===value?.mood)?value.mood as Mood:'personal' as Mood};}catch{return {mode:'personal' as Mode,mood:'personal' as Mood};}}
export function PersonalWave({upload}:{upload:()=>void}){
 useLocale();const store=useStore(),player=usePlayer(),key=`gw-wave-choice:${store.user?.id||'guest'}`;
 const [choice,setChoice]=useState(()=>savedChoice(key)),[busy,setBusy]=useState(false),[error,setError]=useState(''),generation=useRef(0);
 useEffect(()=>{generation.current++;setBusy(false);setError('');setChoice(savedChoice(key));return()=>{generation.current++;};},[key]);
 useEffect(()=>{if(player.waveActive){const next={mode:player.waveOptions.mode,mood:player.waveOptions.mood};setChoice(next);try{localStorage.setItem(key,JSON.stringify(next));}catch{/* Current wave remains visible without storage. */}}},[player.waveActive,player.waveOptions.mode,player.waveOptions.mood]);
 const matches=player.waveActive&&player.waveOptions.mode===choice.mode&&player.waveOptions.mood===choice.mood;
 const playing=matches&&player.state.playing;
 const choose=(patch:Partial<typeof choice>)=>{const next={...choice,...patch};setChoice(next);setError('');try{localStorage.setItem(key,JSON.stringify(next));}catch{/* Selection works without storage. */}};
 const start=async()=>{const request=++generation.current;setBusy(true);setError('');try{
  if(matches&&player.track)await player.command({command:playing?'pause':'play'});
  else await player.startWave(choice);
 }catch(reason){if(request===generation.current)setError(errorText(reason));}finally{if(request===generation.current)setBusy(false);}};
 return <section className={`personal-wave ${playing?'is-playing':''}`} aria-labelledby="personal-wave-title" aria-busy={busy}>
  <div className="wave-hero"><WaveVisual/>
   <header className="wave-heading"><div><h2 id="personal-wave-title">{t('copy.368')}</h2><p>{t(`wave18.caption.${choice.mode}`)}</p></div>
    <div className="wave-actions"><IconButton title={t('copy.407')} onClick={upload}><Plus size={18}/></IconButton><IconButton title={t('v7.wave.settings')} onClick={()=>{store.navigate('settings');location.hash='settings?section=taste';}}><SlidersHorizontal size={18}/></IconButton><button className={`wave-play ${busy?'is-loading':''}`} disabled={busy} aria-label={busy?t('copy.403'):playing?t('copy.404'):t('copy.406')} onClick={()=>void start()}><PlaybackIcon playing={!!playing} loading={busy} size={23}/></button></div>
   </header>
   {matches&&player.track&&<div className="wave-current"><ListeningMotionIcon playing={player.state.playing} loading={player.trackLoading}/><span>{player.track.artist}<b>{player.track.title}</b></span></div>}
  </div>
  <div className="wave-personalization"><div className="wave-mode-row" role="group" aria-label={t('wave18.modeLabel')}>{modes.map(mode=><button type="button" disabled={busy} className={`wave-mode ${mode===choice.mode?'selected':''}`} key={mode} aria-pressed={mode===choice.mode} onClick={()=>choose({mode})}>{t(`wave18.mode.${mode}`)}</button>)}</div>
   <div className="mood-row"><span className="mood-label">{t('copy.409')}</span><div className="mood-scroll" role="group" aria-label={t('copy.409')}>{getMoods().map(({id,Icon})=><button type="button" disabled={busy} className={`mood-chip ${id===choice.mood?'selected':''}`} key={id} aria-pressed={id===choice.mood} onClick={()=>choose({mood:id})}><Icon size={15}/>{t(`wave18.mood.${id}`)}</button>)}</div></div>
  </div>
  {error&&<div className="wave-inline-error" role="alert"><span>{error}</span><button className="text-button" onClick={()=>void start()}>{t('wave18.retry')}</button></div>}
 </section>;
}
