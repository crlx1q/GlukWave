import {usePlayer} from './player';
import {coverEnvelopeHeight,coverSceneHeight,fitCover} from './cover-fit';
import { t, useLocale } from './locale';
import { useEffect, useId, useLayoutEffect, useMemo, useRef, useState, type CSSProperties, type PointerEvent } from 'react';
import { CircleDot, Disc3, FlipHorizontal, RotateCcw } from 'lucide-react';
import { useStore } from './store';
import { Art, IconButton, largeArtwork } from './ui';
import { sourceNames, type Track } from './types';
import { useVisualVisibility } from './visual-lifecycle';

export function AlbumCover({track,playing,gestureOwned=false,active=true,showTools=true,toolsOnly=false,stageBudget,onToolSelect}:{track:Track;playing:boolean;gestureOwned?:boolean;active?:boolean;showTools?:boolean;toolsOnly?:boolean;stageBudget?:number;onToolSelect?:()=>void}) {useLocale();
  const player=usePlayer(),store=useStore(),appearance=store.settings.appearance,[rotation,setRotation]=useState({x:-9,y:-18}),[dragging,setDragging]=useState(false),[manual,setManual]=useState(false),[hovering,setHovering]=useState(false),hint=useId();
  const stage=useRef<HTMLDivElement>(null),visible=useVisualVisibility(stage,active),activeRef=useRef(active&&visible);activeRef.current=active&&visible;
  const [stageSize,setStageSize]=useState({width:0,height:0});
  useLayoutEffect(()=>{const node=stage.current;if(!node)return;const measure=()=>setStageSize({width:node.clientWidth,height:node.clientHeight});measure();const observer=new ResizeObserver(measure);observer.observe(node);return()=>observer.disconnect();},[]);
  // Artwork has one responsive size. The stage grows around it; rotation never shrinks it.
  const spacious = appearance.cover3d && stageSize.width >= 330 && matchMedia('(min-width:600px)').matches && (matchMedia('(max-height:700px),(min-width:1100px) and (max-height:1000px)').matches || (stageBudget??0)>=410);
  const coverSize=useMemo(()=>spacious?Math.min(302,Math.max(0,stageSize.width-24)/1.5,Math.max(0,(stageBudget??410)-24)/1.36):fitCover(stageSize.width,stageBudget??0,appearance.cover3d,0,0),[stageSize.width,stageBudget,appearance.cover3d,spacious]);
  const sceneHeight=useMemo(()=>appearance.cover3d?(spacious?Math.ceil(coverSize*410/302):coverEnvelopeHeight(coverSize)):coverSceneHeight(coverSize),[coverSize,appearance.cover3d,spacious]);
  const hold=useRef<ReturnType<typeof setTimeout>|null>(null),heldPointer=useRef<{id:number;x:number;y:number}|null>(null),angles=useRef(rotation),frame=useRef(0),animationGoal=useRef<{x:number;y:number}|null>(null),motion=useRef(store.motion),speed=useRef(appearance.speed),drag=useRef<{pointerId:number;x:number;y:number;baseX:number;baseY:number;lastX:number;lastTime:number;velocity:number}|null>(null);motion.current=store.motion;speed.current=appearance.speed;
  const update=(next:{x:number;y:number})=>{angles.current=next;setRotation(next);};
  const cancelHold=()=>{if(hold.current)clearTimeout(hold.current);hold.current=null;heldPointer.current=null;};
  const cancel=()=>{cancelHold();cancelAnimationFrame(frame.current);frame.current=0;animationGoal.current=null;};
  const animate=(next:{x:number;y:number},done?:()=>void)=>{cancel();update(next);done?.();};
  useEffect(()=>{cancel();drag.current=null;setDragging(false);setManual(false);update({x:-9,y:-18});},[track.id]);
  useEffect(()=>{if(!store.motion||!appearance.cover3d)cancel();},[store.motion,appearance.cover3d]);
  useEffect(()=>{if(!visible)cancel();return cancel;},[visible]);
  const end=(event:PointerEvent<HTMLDivElement>,inertia:boolean)=>{
    cancelHold();const previous=drag.current;if(!previous)return;if(gestureOwned&&event.pointerType!=='mouse')event.stopPropagation();drag.current=null;setDragging(false);
    if(event.currentTarget.hasPointerCapture(previous.pointerId))event.currentTarget.releasePointerCapture(previous.pointerId);
    if(!inertia||!motion.current||!appearance.cover3d||Math.abs(previous.velocity)<.04)return;
    let velocity=previous.velocity,last=performance.now();
    const spin=(now:number)=>{if(!motion.current||!activeRef.current){cancel();return;}const delta=Math.min(34,now-last)/16.67*speed.current;last=now;update({...angles.current,y:angles.current.y+velocity*delta});velocity*=Math.pow(.94,delta);if(Math.abs(velocity)>.04)frame.current=requestAnimationFrame(spin);else frame.current=0;};
    frame.current=requestAnimationFrame(spin);
  };
  const transform=`translateX(${-12*Math.cos(rotation.y*Math.PI/180)}%) rotateX(${rotation.x}deg) rotateY(${rotation.y}deg)`;
  useEffect(()=>{if(toolsOnly)return;const action=(event:Event)=>{const detail=(event as CustomEvent).detail;if(detail?.trackId!==track.id)return;setManual(true);if(detail.action==='flip'){const base=animationGoal.current||angles.current;animate({...base,y:base.y+180});}else animate({x:-9,y:-18},()=>setManual(false));};window.addEventListener('gw:cover-action',action);return()=>window.removeEventListener('gw:cover-action',action);},[track.id,toolsOnly]);
  const toolAction=(action:'flip'|'reset')=>{if(toolsOnly)window.dispatchEvent(new CustomEvent('gw:cover-action',{detail:{trackId:track.id,action}}));else if(action==='flip'){const base=animationGoal.current||angles.current;setManual(true);animate({...base,y:base.y+180});}else{setManual(true);animate({x:-9,y:-18},()=>setManual(false));}};
  return <>
    {!toolsOnly&&<div ref={stage} style={(coverSize?{'--cover-scene-height':`${sceneHeight}px`}:undefined) as CSSProperties|undefined} data-visual-visible={visible} className={`album-stage ${playing&&visible&&store.motion?'spinning':''} ${appearance.cover3d?'three-dimensional':'flat'} ${dragging?'dragging':''} ${manual?'manual-rotation':''} reference-sleeve ${appearance.coverKind==='cd'?'case-cd':''} ${hovering?'record-hover':''}`} onPointerEnter={()=>setHovering(true)} onPointerLeave={()=>setHovering(false)} onFocus={()=>setHovering(true)} onBlur={()=>setHovering(false)} role="group" aria-label={t('copy.156')} aria-describedby={hint} tabIndex={appearance.cover3d?0:-1}
      onDragStart={event=>event.preventDefault()}
      onPointerDown={event=>{if(!appearance.cover3d||event.button!==0)return;const node=event.currentTarget,id=event.pointerId,x=event.clientX,y=event.clientY;const begin=()=>{cancel();setManual(true);setDragging(true);drag.current={pointerId:id,x,y,baseX:angles.current.x,baseY:angles.current.y,lastX:x,lastTime:performance.now(),velocity:0};node.setPointerCapture(id);};if(gestureOwned&&event.pointerType!=='mouse'){cancelHold();heldPointer.current={id,x,y};hold.current=setTimeout(begin,450);}else begin();}}
      onPointerMove={event=>{const current=drag.current;if(!current||current.pointerId!==event.pointerId){const pending=heldPointer.current;if(pending&&pending.id===event.pointerId&&Math.hypot(event.clientX-pending.x,event.clientY-pending.y)>8)cancelHold();return;}if(gestureOwned&&event.pointerType!=='mouse')event.stopPropagation();const now=performance.now(),delta=event.clientX-current.lastX;current.velocity=delta*.32;current.lastX=event.clientX;current.lastTime=now;update({x:Math.max(-38,Math.min(38,current.baseX-(event.clientY-current.y)*.22)),y:current.baseY+(event.clientX-current.x)*.65});}}
      onPointerUp={event=>end(event,true)} onPointerCancel={event=>end(event,false)} onLostPointerCapture={event=>end(event,false)}
      onKeyDown={event=>{if(!appearance.cover3d||!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(event.key))return;event.preventDefault();const base=animationGoal.current||angles.current;setManual(true);animate({x:Math.max(-38,Math.min(38,base.x+(event.key==='ArrowUp'?-5:event.key==='ArrowDown'?5:0))),y:base.y+(event.key==='ArrowLeft'?-10:event.key==='ArrowRight'?10:0)});}}>
      <div className="album-shadow" aria-hidden="true"/><div className="album-object" style={{transform,'--cover-transform':transform,'--reflection':`${(Math.sin(rotation.y*Math.PI/180)+1)*50}%`,'--cover-light-y':`${50+rotation.x*2}%`,...(coverSize?{'--cover-fit':`${coverSize}px`}: {})} as CSSProperties}>
        <div className={`vinyl ${appearance.coverKind==='cd'?'compact-disc':''}`}><div className="vinyl-grooves"><div className="vinyl-label" style={track.artwork?{backgroundImage:`url(${JSON.stringify(largeArtwork(track.artwork))})`}:undefined}><span/></div></div><i className="vinyl-glint" aria-hidden="true"/></div>
        <div className="album-cover sleeve-front"><Art track={track} className="sleeve-art track-loading-cover" trackLoading={player.trackLoading} highResolution/><span className="cover-reflection" aria-hidden="true"/><span className="sleeve-brand-symbol" aria-hidden="true"><span className="logo-mark"/></span></div>
        <div className="album-back sleeve-back"><span className="sleeve-back-logo">glukwave / studio sessions</span><h3>{track.title}</h3><span className="back-tracklist">01 — {track.title}<br/>{track.artist}<br/>{track.album||sourceNames[track.source]}</span><div className="sleeve-barcode" aria-hidden="true"/><span className="back-micro">GLUK WAVE · 33⅓ RPM</span></div>
        <div className="album-spine" aria-hidden="true"><span>{track.title} · {track.artist}</span></div>
        <div className="album-top-edge" aria-hidden="true"/><div className="album-bottom-edge" aria-hidden="true"/><div className="album-inner-edge" aria-hidden="true"/>
      </div>
    </div>}
    {showTools&&<div className="cover-tools" onClick={event=>{if((event.target as HTMLElement).closest('button'))onToolSelect?.();}} role="toolbar" aria-label={t('copy.158')}><button type="button" className={`cover-mode-button ${appearance.cover3d?'selected':''}`} aria-pressed={appearance.cover3d} onClick={()=>void store.saveSettings({appearance:{cover3d:!appearance.cover3d}})}>{appearance.cover3d?t('copy.159'):t('copy.160')}</button><div className="cover-kind-options">{([['vinyl',t('copy.053'),Disc3],['cd','CD',CircleDot]] as const).map(([kind,label,Icon])=><button type="button" aria-pressed={appearance.coverKind===kind} className={appearance.coverKind===kind?'selected':''} key={kind} onClick={()=>void store.saveSettings({appearance:{coverKind:kind}})}><Icon size={14}/>{label}</button>)}</div><IconButton title={t('copy.161')} disabled={!appearance.cover3d} onClick={()=>toolAction('flip')}><FlipHorizontal size={17}/></IconButton><IconButton title={t('copy.162')} onClick={()=>toolAction('reset')}><RotateCcw size={17}/></IconButton></div>}
    {!toolsOnly&&<p id={hint} className="cover-hint">{appearance.cover3d?(gestureOwned?t('copy.163'):t('copy.164')):t('copy.165')}</p>}
  </>;
}

