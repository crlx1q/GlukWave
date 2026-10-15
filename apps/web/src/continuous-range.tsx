import { useEffect, useRef, useState, type CSSProperties } from 'react';
import { RangeInput } from './range-input';
import type {ProgressReader} from './progress-clock';
import {useProgressPaint} from './progress-paint';

/** Keep a drag under the listener's finger while fresh socket positions arrive. */
export function ContinuousRange({value,min=0,max,step=.1,label,onCommit,onDraft,onCancel,disabled=false,style,className,resetKey,orientation,valueText,readProgress}: {
 value:number;min?:number;max:number;step?:number;label:string;onCommit:(value:number)=>void;onDraft?:(value:number)=>void;onCancel?:()=>void;disabled?:boolean;style?:CSSProperties;className?:string;resetKey?:string;orientation?:'vertical'|'horizontal';valueText?:string;readProgress?:ProgressReader;
}) {
 const [draft,setDraft]=useState(value),editing=useRef(false),pointer=useRef(false),pending=useRef<number|null>(null),timer=useRef<ReturnType<typeof setTimeout>|undefined>(undefined),send=useRef(onCommit),draftCallback=useRef(onDraft),latest=useRef(value);
 send.current=onCommit;draftCallback.current=onDraft;latest.current=value;
 const input=useRef<HTMLInputElement>(null);
 useProgressPaint(input,readProgress,position=>{const node=input.current;if(!node||editing.current)return;const next=Math.min(max,Math.max(min,position)),progress=`${(next-min)/(max-min||1)*100}%`;node.value=String(next);node.style.setProperty('--range-progress',progress);node.style.setProperty('--progress',progress);node.dataset.progressPosition=String(next);},value);
 const flush=()=>{clearTimeout(timer.current);timer.current=undefined;const next=pending.current;pending.current=null;editing.current=false;pointer.current=false;if(next!==null)send.current(next);};
 const release=()=>{if(pointer.current)flush();};
 const cancelCallback=useRef(onCancel);cancelCallback.current=onCancel;
 const cancel=()=>{const wasEditing=editing.current;clearTimeout(timer.current);timer.current=undefined;pending.current=null;editing.current=false;pointer.current=false;setDraft(latest.current);if(wasEditing)cancelCallback.current?.();};
 useEffect(()=>{if(!editing.current)setDraft(value);},[value]);
 useEffect(cancel,[resetKey]);
 useEffect(()=>{if(disabled)cancel();},[disabled]);
 useEffect(()=>{window.addEventListener('pointerup',release);window.addEventListener('pointercancel',cancel);return()=>{clearTimeout(timer.current);if(editing.current)cancelCallback.current?.();window.removeEventListener('pointerup',release);window.removeEventListener('pointercancel',cancel);};},[]);
 return <RangeInput ref={input} min={min} max={Math.max(min+step,max)} step={readProgress?'any':step} value={Math.min(max,Math.max(min,draft))} aria-label={label} aria-orientation={orientation} aria-valuetext={valueText} disabled={disabled} style={style} className={className}
  onPointerDown={()=>{clearTimeout(timer.current);timer.current=undefined;editing.current=true;pointer.current=true;}}
  onChange={event=>{editing.current=true;const next=Number(event.target.value);setDraft(next);onDraft?.(next);pending.current=next;if(!pointer.current){clearTimeout(timer.current);timer.current=setTimeout(flush,240);}}}
  onPointerUp={release} onPointerCancel={cancel} onBlur={flush} onKeyDown={event=>{if(event.key==='Escape'){event.preventDefault();cancel();}else if(readProgress&&['ArrowLeft','ArrowDown','ArrowRight','ArrowUp','Home','End','PageUp','PageDown'].includes(event.key)){event.preventDefault();editing.current=true;const base=Number(event.currentTarget.value),direction=['ArrowLeft','ArrowDown','PageDown'].includes(event.key)?-1:1,next=Math.min(max,Math.max(min,event.key==='Home'?min:event.key==='End'?max:base+direction*step*(event.key.startsWith('Page')?10:1)));setDraft(next);draftCallback.current?.(next);pending.current=next;clearTimeout(timer.current);timer.current=setTimeout(flush,240);}}}/>
}
