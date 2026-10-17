import { useEffect, useRef, useState, type PointerEvent, type MouseEvent } from 'react';
import { usePlayer } from './player';

const clamp=(value:number)=>Math.max(0,Math.min(1,value));
/** Only the mini metadata and the full cover/handle own touch gestures. Scrollable
 * lyrics, queue, sliders and transport buttons retain their native behaviour. */
export function usePlayerGestures(kind:'mini'|'full') {
  const player=usePlayer(),[shift,setShift]=useState(0),[preview,setPreview]=useState<{track:typeof player.track;side:number;width:number}|null>(null),[dragging,setDragging]=useState(false),suppressClickUntil=useRef(0),snapTimer=useRef<ReturnType<typeof setTimeout>|null>(null);
  useEffect(()=>()=>{if(snapTimer.current)clearTimeout(snapTimer.current);},[]);
  const gesture=useRef<{id:number;x:number;y:number;axis:'x'|'y'|'none'|null;lastX:number;lastY:number;lastAt:number;velocity:number;velocityX:number}|null>(null);
  const neighbour=(direction:number)=>{const index=player.queue.findIndex(item=>item.id===player.track?.id);return index>=0?player.queue[index+direction]:undefined;};
  const reset=()=>{gesture.current=null;setDragging(false);setShift(0);player.setRevealProgress(null);if(snapTimer.current)clearTimeout(snapTimer.current);snapTimer.current=setTimeout(()=>setPreview(null),280);};
  const handlers={
    onPointerDown:(event:PointerEvent<HTMLElement>)=>{
      if(!player.track||event.pointerType==='mouse'||event.button!==0||!matchMedia('(max-width: 850px)').matches)return;
      const target=event.target as HTMLElement;
      if(target.closest('input,textarea,select,a,.cover-tools,.np-tabs,.transport,.icon-btn'))return;
      if(kind==='mini'&&!target.closest('.player-track-info,.player-art'))return;
      if(kind==='full'&&!target.closest('.np-cover-growth,.np-drag-handle'))return;
      if(snapTimer.current)clearTimeout(snapTimer.current);setPreview(null);setDragging(true);gesture.current={id:event.pointerId,x:event.clientX,y:event.clientY,axis:null,lastX:event.clientX,lastY:event.clientY,lastAt:performance.now(),velocity:0,velocityX:0};
    },
    onPointerMove:(event:PointerEvent<HTMLElement>)=>{
      const current=gesture.current;if(!current||current.id!==event.pointerId)return;
      const dx=event.clientX-current.x,dy=event.clientY-current.y,now=performance.now();
      current.velocityX=(event.clientX-current.lastX)/Math.max(1,now-current.lastAt);current.lastX=event.clientX;current.velocity=(event.clientY-current.lastY)/Math.max(1,now-current.lastAt);current.lastY=event.clientY;current.lastAt=now;
      if(!current.axis&&Math.max(Math.abs(dx),Math.abs(dy))>8){current.axis=Math.abs(dx)>Math.abs(dy)*1.15?'x':((kind==='mini'?dy<0:dy>0)?'y':'none');if(current.axis!=='none')event.currentTarget.setPointerCapture(event.pointerId);}
      if(current.axis==='x'){event.preventDefault();const side=dx<0?1:-1,next=neighbour(side),width=event.currentTarget.querySelector('.player-track')?.getBoundingClientRect().width||event.currentTarget.getBoundingClientRect().width;setPreview(next?{track:next,side,width}:null);setShift(next?Math.max(-width,Math.min(width,dx)):dx*.12);}
      if(current.axis==='y'){event.preventDefault();const height=window.visualViewport?.height||window.innerHeight;player.setRevealProgress(clamp(kind==='mini'?-dy*1.12/height:1-Math.max(0,dy)/height));}
    },
    onPointerUp:(event:PointerEvent<HTMLElement>)=>{
      const current=gesture.current;if(!current||current.id!==event.pointerId)return;
      const dx=event.clientX-current.x,dy=event.clientY-current.y,height=window.visualViewport?.height||window.innerHeight;
      if(current.axis){suppressClickUntil.current=performance.now()+300;if(event.currentTarget.hasPointerCapture(current.id))event.currentTarget.releasePointerCapture(current.id);}
      if(current.axis==='y')player.setFull(kind==='mini'?(-dy*1.12/height>.26||current.velocity<-.55):!(dy/height>.22||current.velocity>.55));
      if(current.axis==='x'&&(Math.abs(dx)>60||Math.abs(dx)>12&&Math.abs(current.velocityX)>.7)){const next=neighbour(dx<0?1:-1);if(next)void player.playTrack(next,player.queue);}
      reset();
    },
    onPointerCancel:(event:PointerEvent<HTMLElement>)=>{const current=gesture.current;if(!current||current.id!==event.pointerId)return;suppressClickUntil.current=performance.now()+300;reset();},
    onClickCapture:(event:MouseEvent<HTMLElement>)=>{if(performance.now()<suppressClickUntil.current){event.preventDefault();event.stopPropagation();}}
  };
  return {handlers,shift,preview,dragging};
}
