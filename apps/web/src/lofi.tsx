import { t, useLocale, getLanguage } from './locale';
import { useEffect, useRef, useState } from 'react';
import { CloudRain, ExternalLink, Leaf, Maximize2, Minimize2, Moon, Play, Snowflake, Sparkles, Square, Volume2, Waves } from 'lucide-react';
import { useStore } from './store';
import { usePlayer } from './player';
import { drawPixelScene } from './pixel-scene';
import { IconButton } from './ui';

type Scene=0|1|3|6;
type Atmosphere='fireflies'|'rain'|'none';
type LoFiPreferences={scene:Scene;atmosphere:Atmosphere;rainVolume:number};
const getScenes=()=>[{id:0,label:t('copy.410'),title:t('copy.411'),Icon:Leaf},{id:1,label:t('copy.412'),title:t('copy.413'),Icon:Waves},{id:3,label:t('copy.414'),title:t('copy.415'),Icon:Snowflake},{id:6,label:t('copy.416'),title:t('copy.417'),Icon:Moon}] as const;
const localKey=(id?:string)=>`gw-lofi:${id||'guest'}`;
function readPreferences(id?:string):LoFiPreferences{try{const value=JSON.parse(localStorage.getItem(localKey(id))||'null');return {scene:[0,1,3,6].includes(value?.scene)?value.scene:0,atmosphere:['fireflies','rain','none'].includes(value?.atmosphere)?value.atmosphere:'fireflies',rainVolume:typeof value?.rainVolume==='number'?Math.max(0,Math.min(100,value.rainVolume)):25};}catch{return {scene:0,atmosphere:'fireflies',rainVolume:25};}}

function LivingScene({scene,atmosphere,paused}:{scene:Scene;atmosphere:Atmosphere;paused:boolean}) {useLocale();
  const scenes=getScenes(),canvas=useRef<HTMLCanvasElement>(null),store=useStore();
  useEffect(()=>{
    const element=canvas.current,context=element?.getContext('2d');if(!element||!context)return;
    const base=document.createElement('canvas');drawPixelScene(base,scene);element.width=480;element.height=280;context.imageSmoothingEnabled=false;
    let frame=0,visible=true,last=0,time=.8;
    const draw=(now:number,force=false)=>{
      if(document.hidden||!visible)return;
      if(!force&&store.motion&&!paused&&last&&now-last<42){frame=requestAnimationFrame(draw);return;}
      if(store.motion&&!paused&&last)time+=Math.min(70,now-last)/1000*store.settings.appearance.speed;last=now;
      context.drawImage(base,0,0);
      if(store.motion&&!paused){
        for(let y=171;y<236;y+=2)context.drawImage(base,140,y,265,2,140+Math.sin(y*.21+time*1.3)*1.7,y,265,2);
        for(let i=0;i<27;i++){context.fillStyle=`rgba(231,231,180,${(Math.sin(time+i)*.5+.5)*.17})`;context.fillRect(175+(i*137%240)+Math.sin(time+i)*4,176+i*2.1,5+i%8,1);}
        if(atmosphere!=='none'){
          if(atmosphere==='rain'||scene===3){const wet=atmosphere==='rain',count=wet?100:55;context.strokeStyle='rgba(222,231,225,.3)';context.lineWidth=.8;for(let i=0;i<count;i++){const x=(i*93.7+time*(wet?38:8))%480,y=(i*69.3+time*(wet?260:23))%280;if(wet){context.beginPath();context.moveTo(x,y);context.lineTo(x-4,y+13);context.stroke();}else{context.fillStyle=`rgba(245,243,234,${.2+i%4*.14})`;context.beginPath();context.arc(x+Math.sin(time+i)*7,y,1+i%3*.4,0,Math.PI*2);context.fill();}}}
          else for(let i=0;i<26;i++){const x=(i*127.7)%480+Math.sin(time*.4+i)*16,y=84+(i*79.1)%168+Math.cos(time*.6+i)*13,alpha=(Math.sin(time+i*.8)*.5+.5)**3*.7,gradient=context.createRadialGradient(x,y,0,x,y,6);gradient.addColorStop(0,`rgba(225,228,156,${alpha})`);gradient.addColorStop(1,'rgba(225,228,156,0)');context.fillStyle=gradient;context.fillRect(x-6,y-6,12,12);}
        }
        frame=requestAnimationFrame(draw);
      }
    };
    const repaint=()=>{cancelAnimationFrame(frame);last=0;if(!document.hidden&&visible)draw(performance.now(),true);};
    const observer=new IntersectionObserver(entries=>{visible=entries[0].isIntersecting;repaint();});observer.observe(element);document.addEventListener('visibilitychange',repaint);repaint();
    return()=>{cancelAnimationFrame(frame);observer.disconnect();document.removeEventListener('visibilitychange',repaint);};
  },[scene,atmosphere,store.motion,store.settings.appearance.speed,paused]);
  return <canvas ref={canvas} className="lofi-landscape" role="img" aria-label={t('template.022', {v0: scenes.find(item=>item.id===scene)?.title})}/>;
}

export function LoFiPage() {useLocale();
  const scenes=getScenes(),store=useStore(),player=usePlayer(),[preferences,setPreferences]=useState<LoFiPreferences>(()=>readPreferences(store.user?.id)),[zen,setZen]=useState(false),[clock,setClock]=useState(new Date()),[original,setOriginal]=useState(false),[originalStatus,setOriginalStatus]=useState<'loading'|'loaded'|'error'>('loading'),[rainOn,setRainOn]=useState(false),[starting,setStarting]=useState(false);
  const stage=useRef<HTMLDivElement>(null),sound=useRef<{context:AudioContext;source:AudioBufferSourceNode;gain:GainNode}|null>(null),soundGeneration=useRef(0),mounted=useRef(true),volumeRef=useRef(preferences.rainVolume);volumeRef.current=preferences.rainVolume;
  useEffect(()=>{try{localStorage.setItem(localKey(store.user?.id),JSON.stringify(preferences));}catch{/* Current scene still works when local preferences cannot be saved. */}},[preferences,store.user?.id]);
  const change=(partial:Partial<LoFiPreferences>)=>setPreferences(current=>({...current,...partial}));
  const stopRain=()=>{soundGeneration.current++;const current=sound.current;sound.current=null;if(current){current.context.onstatechange=null;try{current.source.stop();}catch{/* Source may already have stopped. */}current.source.disconnect();current.gain.disconnect();void current.context.close().catch(()=>{});}if(mounted.current){setRainOn(false);setStarting(false);}};
  const startRain=async()=>{
    if(starting)return;stopRain();setStarting(true);const generation=++soundGeneration.current;
    try {
      const context=new AudioContext();
      const buffer=context.createBuffer(1,context.sampleRate*4,context.sampleRate),data=buffer.getChannelData(0);let last=0;for(let i=0;i<data.length;i++){last=(last+Math.random()*.04-.02)/1.02;data[i]=last*3.5;}
      const source=context.createBufferSource(),filter=context.createBiquadFilter(),gain=context.createGain();source.buffer=buffer;source.loop=true;filter.type='lowpass';filter.frequency.value=1600;gain.gain.value=0;source.connect(filter);filter.connect(gain);gain.connect(context.destination);sound.current={context,source,gain};source.start();await context.resume();
      if(!mounted.current||generation!==soundGeneration.current){source.disconnect();if(context.state!=='closed')await context.close();return;}
      gain.gain.setTargetAtTime(volumeRef.current/100*.6,context.currentTime,.2);setRainOn(context.state==='running');setStarting(false);context.onstatechange=()=>{if(mounted.current&&sound.current?.context===context)setRainOn(context.state==='running');};
      if(context.state!=='running')store.notify(t('copy.418'),true);
    }catch{stopRain();store.notify(t('copy.419'),true);}
  };
  useEffect(()=>{const current=sound.current;if(current)current.gain.gain.setTargetAtTime(preferences.rainVolume/100*.6,current.context.currentTime,.2);},[preferences.rainVolume]);
  useEffect(()=>{mounted.current=true;return()=>{mounted.current=false;stopRain();};},[]);
  useEffect(()=>{const update=()=>{if(!document.hidden)setClock(new Date());};update();const timer=setInterval(update,10000);document.addEventListener('visibilitychange',update);return()=>{clearInterval(timer);document.removeEventListener('visibilitychange',update);};},[]);
  useEffect(()=>{if(!zen)return;const before=document.body.style.overflow,focused=document.activeElement as HTMLElement|null,background=[...document.querySelectorAll<HTMLElement>('.sidebar,.topbar,.player,.mobile-nav')].filter(element=>!element.inert);background.forEach(element=>element.inert=true);document.body.style.overflow='hidden';stage.current?.querySelector<HTMLButtonElement>('button')?.focus();const escape=(event:KeyboardEvent)=>{if(event.key==='Escape')setZen(false);if(event.key==='Tab'){const controls=[...stage.current?.querySelectorAll<HTMLButtonElement>('button:not(:disabled)')||[]].filter(element=>element.getClientRects().length),first=controls[0],last=controls.at(-1);if(event.shiftKey&&document.activeElement===first){event.preventDefault();last?.focus();}else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first?.focus();}}};window.addEventListener('keydown',escape);return()=>{document.body.style.overflow=before;background.forEach(element=>element.inert=false);window.removeEventListener('keydown',escape);focused?.focus();};},[zen]);
  useEffect(()=>{const element=stage.current;if(!element)return;const resize=()=>{const rect=element.getBoundingClientRect();element.style.setProperty('--frame-scale',String(Math.max(rect.width/620,rect.height/450)));};const observer=new ResizeObserver(resize);observer.observe(element);resize();return()=>observer.disconnect();},[]);
  useEffect(()=>{if(!original)return;setOriginalStatus('loading');const timeout=setTimeout(()=>setOriginalStatus(current=>current==='loading'?'error':current),14000);return()=>clearTimeout(timeout);},[original,preferences.scene]);
  useEffect(()=>{if(store.offline)setOriginal(false);},[store.offline]);
  const title=scenes.find(item=>item.id===preferences.scene)!.title,originalUrl=`https://www.effectgames.com/demos/canvascycle/?sound=0&scene=${preferences.scene}`;
  return <section className={`view lofi-page ${zen?'zen':''}`}>
    <div className="view-heading lofi-heading"><div><p className="eyebrow">{t('copy.420')}</p><h1>{t('copy.421')}<span className="accent-period">.</span></h1><p className="intro">{t('copy.422')}</p></div><button className="subtle-button" onClick={()=>setZen(true)}><Maximize2 size={16}/>{t('copy.423')}</button></div>
    <div ref={stage} className="lofi-stage" role={zen?'dialog':undefined} aria-modal={zen?true:undefined} aria-label={zen?t('copy.424'):undefined}>
      <LivingScene scene={preferences.scene} atmosphere={preferences.atmosphere} paused={player.full||original&&originalStatus==='loaded'}/>
      {original&&originalStatus!=='error'&&<div className={`lofi-original ${originalStatus==='loaded'?'loaded':''}`}><iframe key={preferences.scene} src={originalUrl} title={t('copy.425')} referrerPolicy="no-referrer" sandbox="allow-scripts allow-same-origin" onLoad={()=>setOriginalStatus('loaded')} onError={()=>setOriginalStatus('error')}/></div>}
      <div className="lofi-scene-top"><span className="lofi-tag">{original&&originalStatus==='loaded'?'CANVAS CYCLE · EFFECT GAMES':t('copy.426')}</span><IconButton className="icon-btn frosted" title={zen?t('copy.427'):t('copy.428')} onClick={()=>setZen(current=>!current)}>{zen?<Minimize2 size={19}/>:<Maximize2 size={19}/>}</IconButton></div>
      <div className="lofi-clock"><time dateTime={clock.toISOString()}>{clock.toLocaleTimeString(getLanguage(),{hour:'2-digit',minute:'2-digit'})}</time><p>{t('copy.429')}</p></div>
      <div className="lofi-scene-bottom"><div><b>{title}</b><span>{original?originalStatus==='loading'?t('copy.430'):originalStatus==='error'?t('copy.431'):t('copy.432'):t('copy.433')}</span></div><button className="frosted-button" disabled={store.offline&&!original} onClick={()=>setOriginal(current=>!current)}>{original?<Leaf size={16}/>:<Play size={16}/>}<span>{original?t('copy.434'):t('copy.435')}</span></button></div>
      {zen&&<div className="zen-audio-controls"><span>{rainOn?<><CloudRain size={16}/>{t('copy.436')}{' '}{preferences.rainVolume}%</>:t('copy.424')}</span>{rainOn&&<button onClick={stopRain}><Square size={14}/>{t('copy.437')}</button>}</div>}
    </div>
    <div className="lofi-controls"><div><p className="control-label">{t('copy.438')}</p><div className="scene-buttons">{scenes.map(({id,label,Icon})=><button key={id} className={preferences.scene===id?'selected':''} aria-pressed={preferences.scene===id} onClick={()=>change({scene:id})}><Icon size={16}/>{label}</button>)}</div></div><div className="ambient-controls"><p className="control-label">{t('copy.439')}</p><label><CloudRain size={18}/><span>{t('copy.440')}</span><input aria-label={t('copy.441')} type="range" min={0} max={100} value={preferences.rainVolume} onChange={event=>change({rainVolume:Number(event.target.value)})}/><output>{preferences.rainVolume}%</output></label><div className="rain-actions"><button className={rainOn?'subtle-button':'primary-button'} disabled={starting} onClick={()=>rainOn?stopRain():void startRain()}>{rainOn?<Square size={14}/>:<Volume2 size={15}/>}<span>{starting?t('copy.442'):rainOn?t('copy.437'):t('copy.443')}</span></button><small role="status">{rainOn?preferences.rainVolume?t('copy.444'):t('copy.445'):t('copy.446')}</small></div></div></div>
    <div className="ambient-presets"><span><Sparkles size={14}/>{t('copy.447')}</span>{([['fireflies',t('copy.448')],['rain',t('copy.440')],['none',t('copy.449')]] as const).map(([value,label])=><button key={value} className={preferences.atmosphere===value?'selected':''} aria-pressed={preferences.atmosphere===value} onClick={()=>change({atmosphere:value})}>{label}</button>)}</div>
    <p className="lofi-motion-note">{store.motion?t('copy.450'):t('copy.451')}{' '}{t('copy.452')}</p>
    <p className="credit-line">{t('copy.453')}{' '}<a href={originalUrl} target="_blank" rel="noopener noreferrer">{t('copy.379')}{' '}<ExternalLink size={12}/></a><br/><span>{t('copy.454')}</span></p>
  </section>;
}

export function LoFiEntry(){useLocale();const store=useStore(),player=usePlayer();return <button className="lofi-home-entry" onClick={()=>store.navigate('lofi')}><LivingScene scene={0} atmosphere="fireflies" paused={player.full}/><span className="lofi-entry-copy"><small>GLUK LO-FI</small><b>{t('copy.455')}</b><span>{t('copy.456')}</span></span><span className="lofi-entry-arrow"><Leaf size={21}/><span>{t('copy.457')}</span></span></button>;}
