import { t, useLocale } from './locale';
import { useEffect, useId, useRef, useState, type CSSProperties, type PointerEvent } from 'react';
import { CircleDot, Disc3, FlipHorizontal, RotateCcw } from 'lucide-react';
import { useStore } from './store';
import { Art, Brand, IconButton } from './ui';
import { sourceNames, type Track } from './types';

export function AlbumCover({track,playing,gestureOwned=false}:{track:Track;playing:boolean;gestureOwned?:boolean}) {useLocale();
  const store=useStore(),appearance=store.settings.appearance,[rotation,setRotation]=useState({x:-9,y:-18}),[dragging,setDragging]=useState(false),[manual,setManual]=useState(false),hint=useId();
  const angles=useRef(rotation),frame=useRef(0),motion=useRef(store.motion),speed=useRef(appearance.speed),drag=useRef<{pointerId:number;x:number;y:number;baseX:number;baseY:number;lastX:number;lastTime:number;velocity:number}|null>(null);motion.current=store.motion;speed.current=appearance.speed;
  const update=(next:{x:number;y:number})=>{angles.current=next;setRotation(next);};
  const cancel=()=>{cancelAnimationFrame(frame.current);frame.current=0;};
  useEffect(()=>{cancel();drag.current=null;setDragging(false);setManual(false);update({x:-9,y:-18});},[track.id]);
  useEffect(()=>{if(!store.motion||!appearance.cover3d)cancel();},[store.motion,appearance.cover3d]);
  useEffect(()=>{const hidden=()=>{if(document.hidden)cancel();};document.addEventListener('visibilitychange',hidden);return()=>{cancel();document.removeEventListener('visibilitychange',hidden);};},[]);
  const end=(event:PointerEvent<HTMLDivElement>,inertia:boolean)=>{
    const previous=drag.current;if(!previous)return;drag.current=null;setDragging(false);
    if(event.currentTarget.hasPointerCapture(previous.pointerId))event.currentTarget.releasePointerCapture(previous.pointerId);
    if(!inertia||!motion.current||!appearance.cover3d||Math.abs(previous.velocity)<.04)return;
    let velocity=previous.velocity,last=performance.now();
    const spin=(now:number)=>{if(!motion.current||document.hidden){cancel();return;}const delta=Math.min(34,now-last)/16.67*speed.current;last=now;update({...angles.current,y:angles.current.y+velocity*delta});velocity*=Math.pow(.94,delta);if(Math.abs(velocity)>.04)frame.current=requestAnimationFrame(spin);else frame.current=0;};
    frame.current=requestAnimationFrame(spin);
  };
  const transform=`rotateX(${rotation.x}deg) rotateY(${rotation.y}deg)`;
  return <>
    <div className={`album-stage ${playing?'spinning':''} ${appearance.cover3d?'three-dimensional':'flat'} ${dragging?'dragging':''} ${manual?'manual-rotation':''}`} role="group" aria-label={t('copy.156')} aria-describedby={hint} tabIndex={appearance.cover3d?0:-1}
      onDragStart={event=>event.preventDefault()}
      onPointerDown={event=>{if(!appearance.cover3d||event.button!==0||(gestureOwned&&event.pointerType!=='mouse'))return;cancel();setManual(true);setDragging(true);drag.current={pointerId:event.pointerId,x:event.clientX,y:event.clientY,baseX:angles.current.x,baseY:angles.current.y,lastX:event.clientX,lastTime:performance.now(),velocity:0};event.currentTarget.setPointerCapture(event.pointerId);}}
      onPointerMove={event=>{const current=drag.current;if(!current||current.pointerId!==event.pointerId)return;const now=performance.now(),delta=event.clientX-current.lastX;current.velocity=delta*.42/(Math.max(8,now-current.lastTime)/16.67);current.lastX=event.clientX;current.lastTime=now;update({x:Math.max(-75,Math.min(75,current.baseX-(event.clientY-current.y)*.22)),y:current.baseY+(event.clientX-current.x)*.42});}}
      onPointerUp={event=>end(event,true)} onPointerCancel={event=>end(event,false)} onLostPointerCapture={event=>end(event,false)}
      onKeyDown={event=>{if(!appearance.cover3d||!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(event.key))return;event.preventDefault();cancel();setManual(true);update({x:Math.max(-75,Math.min(75,angles.current.x+(event.key==='ArrowUp'?-5:event.key==='ArrowDown'?5:0))),y:angles.current.y+(event.key==='ArrowLeft'?-10:event.key==='ArrowRight'?10:0)});}}>
      <div className="album-object" style={{transform,'--cover-transform':transform} as CSSProperties}>
        <div className={`vinyl ${appearance.coverKind==='cd'?'compact-disc':''}`}><div className="vinyl-label" style={track.artwork?{backgroundImage:`url(${JSON.stringify(track.artwork)})`}:undefined}/></div>
        <Art track={track} className="album-cover" highResolution/>
        <div className="album-back"><Brand animated={false}/><span className="album-back-wave" aria-hidden="true">∿</span><b>{track.title}</b><span>{track.artist}</span><small>{track.album||sourceNames[track.source]}</small><p>{t('copy.157')}</p></div>
        <div className="album-spine" aria-hidden="true">{track.title} · {track.artist}</div>
      </div>
    </div>
    <div className="cover-tools" aria-label={t('copy.158')}><button type="button" className={`cover-mode-button ${appearance.cover3d?'selected':''}`} aria-pressed={appearance.cover3d} onClick={()=>void store.saveSettings({appearance:{cover3d:!appearance.cover3d}})}>{appearance.cover3d?t('copy.159'):t('copy.160')}</button><div className="cover-kind-options">{([['vinyl',t('copy.053'),Disc3],['cd','CD',CircleDot]] as const).map(([kind,label,Icon])=><button type="button" aria-pressed={appearance.coverKind===kind} className={appearance.coverKind===kind?'selected':''} key={kind} onClick={()=>void store.saveSettings({appearance:{coverKind:kind}})}><Icon size={14}/>{label}</button>)}</div><IconButton title={t('copy.161')} disabled={!appearance.cover3d} onClick={()=>{cancel();setManual(true);update({...angles.current,y:angles.current.y+180});}}><FlipHorizontal size={17}/></IconButton><IconButton title={t('copy.162')} onClick={()=>{cancel();setManual(false);update({x:-9,y:-18});}}><RotateCcw size={17}/></IconButton></div>
    <p id={hint} className="cover-hint">{appearance.cover3d?(gestureOwned?t('copy.163'):t('copy.164')):t('copy.165')}</p>
  </>;
}

