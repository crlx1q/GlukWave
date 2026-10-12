import { useEffect, useRef, useState, type CSSProperties } from 'react';
import { RangeInput } from './range-input';

/** Keep a drag under the listener's finger while fresh socket positions arrive. */
export function ContinuousRange({value,min=0,max,step=.1,label,onCommit,onDraft,disabled=false,style,className,resetKey,orientation,valueText}: {
 value:number;min?:number;max:number;step?:number;label:string;onCommit:(value:number)=>void;onDraft?:(value:number)=>void;disabled?:boolean;style?:CSSProperties;className?:string;resetKey?:string;orientation?:'vertical'|'horizontal';valueText?:string;
}) {
 const [draft,setDraft]=useState(value),editing=useRef(false),pointer=useRef(false),pending=useRef<number|null>(null),timer=useRef<ReturnType<typeof setTimeout>|undefined>(undefined),send=useRef(onCommit),draftCallback=useRef(onDraft),latest=useRef(value);
 send.current=onCommit;draftCallback.current=onDraft;latest.current=value;
 const flush=()=>{clearTimeout(timer.current);timer.current=undefined;const next=pending.current;pending.current=null;editing.current=false;pointer.current=false;if(next!==null)send.current(next);};
 const release=()=>{if(pointer.current)flush();};
 const cancel=()=>{clearTimeout(timer.current);timer.current=undefined;pending.current=null;editing.current=false;pointer.current=false;setDraft(latest.current);draftCallback.current?.(latest.current);};
 useEffect(()=>{if(!editing.current)setDraft(value);},[value]);
 useEffect(cancel,[resetKey]);
 useEffect(()=>{if(disabled)cancel();},[disabled]);
 useEffect(()=>{window.addEventListener('pointerup',release);window.addEventListener('pointercancel',cancel);return()=>{clearTimeout(timer.current);window.removeEventListener('pointerup',release);window.removeEventListener('pointercancel',cancel);};},[]);
 return <RangeInput min={min} max={Math.max(min+step,max)} step={step} value={Math.min(max,Math.max(min,draft))} aria-label={label} aria-orientation={orientation} aria-valuetext={valueText} disabled={disabled} style={style} className={className}
  onPointerDown={()=>{clearTimeout(timer.current);timer.current=undefined;editing.current=true;pointer.current=true;}}
  onChange={event=>{editing.current=true;const next=Number(event.target.value);setDraft(next);onDraft?.(next);pending.current=next;if(!pointer.current){clearTimeout(timer.current);timer.current=setTimeout(flush,240);}}}
  onPointerUp={release} onPointerCancel={cancel} onBlur={flush} onKeyDown={event=>{if(event.key==='Escape')cancel();}}/>
}
