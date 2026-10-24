import { useEffect, useRef, useState, type CSSProperties } from 'react';
import { RangeInput } from './range-input';
import {progressPosition,type ProgressReader} from './progress-clock';
import {useProgressPaint} from './progress-paint';
import {useVolumeHint} from './volume-hint';

/** Keep a drag under the listener's finger while fresh socket positions arrive. */
export function ContinuousRange({value,min=0,max,step=.1,label,onCommit,onDraft,onCancel,disabled=false,style,className,resetKey,orientation,valueText,readProgress,allowOffStep=false,volumeHint=false}: {
 value:number;min?:number;max:number;step?:number;label:string;onCommit:(value:number)=>void;onDraft?:(value:number)=>void;onCancel?:()=>void;disabled?:boolean;style?:CSSProperties;className?:string;resetKey?:string;orientation?:'vertical'|'horizontal';valueText?:string;readProgress?:ProgressReader;allowOffStep?:boolean;volumeHint?:boolean;
}) {
 const [draft,setDraft]=useState(value),editing=useRef(false),pointer=useRef(false),pending=useRef<number|null>(null),timer=useRef<ReturnType<typeof setTimeout>|undefined>(undefined),send=useRef(onCommit),draftCallback=useRef(onDraft),latest=useRef(value);
 send.current=onCommit;draftCallback.current=onDraft;latest.current=value;
 const input=useRef<HTMLInputElement>(null);
 const hint=useVolumeHint(input,volumeHint&&!disabled,resetKey);
 useProgressPaint(input,readProgress,position=>{const node=input.current;if(!node||editing.current)return;const next=Math.min(max,Math.max(min,position)),progress=`${(next-min)/(max-min||1)*100}%`;node.value=String(next);node.style.setProperty('--range-progress',progress);node.style.setProperty('--progress',progress);node.dataset.progressPosition=String(next);},value);
 const flush=()=>{clearTimeout(timer.current);timer.current=undefined;const next=pending.current;pending.current=null;editing.current=false;pointer.current=false;if(next!==null)send.current(next);};
 const release=()=>{if(pointer.current)flush();};
 const cancelCallback=useRef(onCancel);cancelCallback.current=onCancel;
 const cancel=()=>{const wasEditing=editing.current;clearTimeout(timer.current);timer.current=undefined;pending.current=null;editing.current=false;pointer.current=false;setDraft(latest.current);if(wasEditing)cancelCallback.current?.();};
 useEffect(()=>{if(!editing.current)setDraft(value);},[value]);
 useEffect(cancel,[resetKey]);
 useEffect(()=>{if(disabled)cancel();},[disabled]);
 useEffect(()=>{window.addEventListener('pointerup',release);window.addEventListener('pointercancel',cancel);return()=>{clearTimeout(timer.current);if(editing.current)cancelCallback.current?.();window.removeEventListener('pointerup',release);window.removeEventListener('pointercancel',cancel);};},[]);
 const displayed=readProgress&&!editing.current?progressPosition(readProgress(),performance.now()):draft;
 return <><RangeInput ref={input} min={min} max={Math.max(min+step,max)} step={readProgress||allowOffStep?'any':step} value={Math.min(max,Math.max(min,displayed))} aria-label={label} aria-orientation={orientation} aria-valuetext={valueText} disabled={disabled} style={style} className={className}
  onPointerEnter={event=>{if(event.pointerType==='mouse')hint.enter();}} onPointerLeave={hint.hide}
  onPointerDown={()=>{clearTimeout(timer.current);timer.current=undefined;editing.current=true;pointer.current=true;}}
  onChange={event=>{editing.current=true;const raw=Number(event.target.value),next=allowOffStep?Math.max(min,Math.min(max,Math.round(raw/step)*step)):raw;setDraft(next);onDraft?.(next);pending.current=next;if(!pointer.current){clearTimeout(timer.current);timer.current=setTimeout(flush,240);}}}
  onPointerUp={release} onPointerCancel={()=>{hint.hide();cancel();}} onBlur={()=>{hint.hide();flush();}} onKeyDown={event=>{if(event.key==='Escape'){event.preventDefault();hint.hide();cancel();}else if((readProgress||allowOffStep)&&['ArrowLeft','ArrowDown','ArrowRight','ArrowUp','Home','End','PageUp','PageDown'].includes(event.key)){event.preventDefault();editing.current=true;const base=Number(event.currentTarget.value),direction=['ArrowLeft','ArrowDown','PageDown'].includes(event.key)?-1:1,next=Math.min(max,Math.max(min,event.key==='Home'?min:event.key==='End'?max:base+direction*step*(event.key.startsWith('Page')?10:1)));setDraft(next);draftCallback.current?.(next);pending.current=next;clearTimeout(timer.current);timer.current=setTimeout(flush,240);}}}/>{hint.hint}</>
}
