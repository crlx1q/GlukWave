import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties } from 'react';
import { RangeInput } from './range-input';
import type {ProgressReader} from './progress-clock';
import {useProgressPaint} from './progress-paint';
import {useVolumeHint} from './volume-hint';

/** Keep a drag under the listener's finger while fresh socket positions arrive. */
export function ContinuousRange({value,min=0,max,step=.1,label,onCommit,onDraft,onCancel,disabled=false,style,className,resetKey,orientation,valueText,readProgress,allowOffStep=false,volumeHint=false,wheelRevision}: {
 value:number;min?:number;max:number;step?:number;label:string;onCommit:(value:number)=>void;onDraft?:(value:number)=>void;onCancel?:()=>void;disabled?:boolean;style?:CSSProperties;className?:string;resetKey?:string;orientation?:'vertical'|'horizontal';valueText?:string;readProgress?:ProgressReader;allowOffStep?:boolean;volumeHint?:boolean;wheelRevision?:number;
}) {
 const [draft,setDraft]=useState(value),editing=useRef(false),pointer=useRef(false),pending=useRef<number|null>(null),timer=useRef<ReturnType<typeof setTimeout>|undefined>(undefined),send=useRef(onCommit),draftCallback=useRef(onDraft),latest=useRef(value);
 send.current=onCommit;draftCallback.current=onDraft;latest.current=value;
 const input=useRef<HTMLInputElement>(null);
 const initialValue=useRef(Math.min(max,Math.max(min,value)));
 const frame=useRef(0),previousWheel=useRef({revision:wheelRevision,scope:resetKey});
 const timed=!!readProgress,managed=timed||wheelRevision!==undefined;
 const paint=(position:number)=>{
  const node=input.current;if(!node)return;
  const next=Math.min(max,Math.max(min,position)),progress=`${(next-min)/(max-min||1)*100}%`;
  node.value=String(next);
  node.style.setProperty('--range-progress',progress);
  node.style.setProperty('--progress',progress);
  if(timed)node.dataset.progressPosition=String(next);
 };
 const stopWheel=()=>{cancelAnimationFrame(frame.current);frame.current=0;};
 useLayoutEffect(()=>{
  const previous=previousWheel.current;
  previousWheel.current={revision:wheelRevision,scope:resetKey};
  if(timed||wheelRevision===undefined||editing.current||!input.current)return;
  stopWheel();
  const from=Number(input.current.value),to=Math.min(max,Math.max(min,value));
  const reduce=document.documentElement.dataset.motion==='reduce'||matchMedia('(prefers-reduced-motion: reduce)').matches;
  if(disabled||reduce||previous.scope!==resetKey||previous.revision===wheelRevision||from===to){paint(to);return;}
  const start=performance.now();
  const tick=(now:number)=>{
   const fraction=Math.min(1,Math.max(0,(now-start)/150));
   paint(from+(to-from)*(1-Math.pow(1-fraction,3)));
   frame.current=fraction<1?requestAnimationFrame(tick):0;
  };
  frame.current=requestAnimationFrame(tick);
 },[value,wheelRevision,resetKey,disabled,timed,min,max]);
 useLayoutEffect(()=>()=>cancelAnimationFrame(frame.current),[]);
 const hint=useVolumeHint(input,volumeHint&&!disabled,resetKey);
 useProgressPaint(input,readProgress,position=>{if(!editing.current)paint(position);});
 const begin=()=>{stopWheel();editing.current=true;input.current?.setAttribute('data-range-editing','true');};
 const end=()=>{editing.current=false;pointer.current=false;input.current?.removeAttribute('data-range-editing');};
 const flush=()=>{clearTimeout(timer.current);timer.current=undefined;const next=pending.current;pending.current=null;end();if(next!==null)send.current(next);};
 const release=()=>{if(pointer.current)flush();};
 const cancelCallback=useRef(onCancel);cancelCallback.current=onCancel;
 const cancel=()=>{const wasEditing=editing.current;clearTimeout(timer.current);timer.current=undefined;pending.current=null;end();setDraft(latest.current);if(wasEditing){stopWheel();if(managed)paint(latest.current);cancelCallback.current?.();}};
 useEffect(()=>{if(!editing.current)setDraft(value);},[value]);
 useEffect(cancel,[resetKey]);
 useEffect(()=>{if(disabled)cancel();},[disabled]);
 useEffect(()=>{window.addEventListener('pointerup',release);window.addEventListener('pointercancel',cancel);return()=>{clearTimeout(timer.current);if(editing.current)cancelCallback.current?.();window.removeEventListener('pointerup',release);window.removeEventListener('pointercancel',cancel);};},[]);
 return <><RangeInput ref={input} min={min} max={Math.max(min+step,max)} step={timed||allowOffStep?'any':step} value={managed?undefined:Math.min(max,Math.max(min,draft))} defaultValue={managed?initialValue.current:undefined} aria-label={label} aria-orientation={orientation} aria-valuetext={valueText} disabled={disabled} style={style} className={className}
  onPointerEnter={event=>{if(event.pointerType==='mouse')hint.enter();}} onPointerLeave={hint.hide}
  onPointerDown={()=>{clearTimeout(timer.current);timer.current=undefined;begin();pointer.current=true;}}
  onChange={event=>{begin();const raw=Number(event.target.value),next=allowOffStep?Math.max(min,Math.min(max,Math.round(raw/step)*step)):raw;if(managed)paint(next);setDraft(next);onDraft?.(next);pending.current=next;if(!pointer.current){clearTimeout(timer.current);timer.current=setTimeout(flush,240);}}}
  onPointerUp={release} onPointerCancel={()=>{hint.hide();cancel();}} onBlur={()=>{hint.hide();flush();}} onKeyDown={event=>{if(event.key==='Escape'){event.preventDefault();hint.hide();cancel();}else if((timed||allowOffStep)&&['ArrowLeft','ArrowDown','ArrowRight','ArrowUp','Home','End','PageUp','PageDown'].includes(event.key)){event.preventDefault();begin();const base=Number(event.currentTarget.value),direction=['ArrowLeft','ArrowDown','PageDown'].includes(event.key)?-1:1,next=Math.min(max,Math.max(min,event.key==='Home'?min:event.key==='End'?max:base+direction*step*(event.key.startsWith('Page')?10:1)));if(managed)paint(next);setDraft(next);draftCallback.current?.(next);pending.current=next;clearTimeout(timer.current);timer.current=setTimeout(flush,240);}}}/>{hint.hint}</>
}
