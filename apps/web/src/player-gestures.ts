import { useRef, useState, type PointerEvent, type MouseEvent } from 'react';
import { usePlayer } from './player';

const clamp=(value:number)=>Math.max(0,Math.min(1,value));
/** Only the mini metadata and the full cover/handle own touch gestures. Scrollable
 * lyrics, queue, sliders and transport buttons retain their native behaviour. */
export function usePlayerGestures(kind:'mini'|'full') {
  const player=usePlayer(),[shift,setShift]=useState(0),suppressClickUntil=useRef(0);
  const gesture=useRef<{id:number;x:number;y:number;axis:'x'|'y'|'none'|null;lastY:number;lastAt:number;velocity:number}|null>(null);
  const neighbour=(direction:number)=>{const index=player.queue.findIndex(item=>item.id===player.track?.id);return index>=0?player.queue[index+direction]:undefined;};
  const reset=()=>{gesture.current=null;setShift(0);player.setRevealProgress(null);};
  const handlers={
    onPointerDown:(event:PointerEvent<HTMLElement>)=>{
      if(!player.track||event.pointerType==='mouse'||event.button!==0||!matchMedia('(max-width: 850px)').matches)return;
      const target=event.target as HTMLElement;
      if(target.closest('input,textarea,select,a,.cover-tools,.np-tabs,.transport,.icon-btn'))return;
      if(kind==='mini'&&!target.closest('.player-track-info,.player-art'))return;
      if(kind==='full'&&!target.closest('.np-cover-growth,.np-drag-handle'))return;
      gesture.current={id:event.pointerId,x:event.clientX,y:event.clientY,axis:null,lastY:event.clientY,lastAt:performance.now(),velocity:0};
    },
    onPointerMove:(event:PointerEvent<HTMLElement>)=>{
      const current=gesture.current;if(!current||current.id!==event.pointerId)return;
      const dx=event.clientX-current.x,dy=event.clientY-current.y,now=performance.now();
      current.velocity=(event.clientY-current.lastY)/Math.max(1,now-current.lastAt);current.lastY=event.clientY;current.lastAt=now;
      if(!current.axis&&Math.max(Math.abs(dx),Math.abs(dy))>8){current.axis=Math.abs(dx)>Math.abs(dy)*1.15?'x':((kind==='mini'?dy<0:dy>0)?'y':'none');if(current.axis!=='none')event.currentTarget.setPointerCapture(event.pointerId);}
      if(current.axis==='x'){event.preventDefault();setShift(neighbour(dx<0?1:-1)?Math.max(-150,Math.min(150,dx))*.65:dx*.12);}
      if(current.axis==='y'){event.preventDefault();const height=window.visualViewport?.height||window.innerHeight;player.setRevealProgress(clamp(kind==='mini'?-dy*1.12/height:1-Math.max(0,dy)/height));}
    },
    onPointerUp:(event:PointerEvent<HTMLElement>)=>{
      const current=gesture.current;if(!current||current.id!==event.pointerId)return;
      const dx=event.clientX-current.x,dy=event.clientY-current.y,height=window.visualViewport?.height||window.innerHeight;
      if(current.axis){suppressClickUntil.current=performance.now()+300;if(event.currentTarget.hasPointerCapture(current.id))event.currentTarget.releasePointerCapture(current.id);}
      if(current.axis==='y')player.setFull(kind==='mini'?(-dy*1.12/height>.26||current.velocity<-.55):!(dy/height>.22||current.velocity>.55));
      if(current.axis==='x'&&Math.abs(dx)>60){const next=neighbour(dx<0?1:-1);if(next)void player.playTrack(next,player.queue);}
      reset();
    },
    onPointerCancel:(event:PointerEvent<HTMLElement>)=>{const current=gesture.current;if(!current||current.id!==event.pointerId)return;suppressClickUntil.current=performance.now()+300;reset();},
    onClickCapture:(event:MouseEvent<HTMLElement>)=>{if(performance.now()<suppressClickUntil.current){event.preventDefault();event.stopPropagation();}}
  };
  return {handlers,shift};
}
