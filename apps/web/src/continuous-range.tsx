import { useEffect, useRef, useState, type CSSProperties } from 'react';

/** Keep a drag under the listener's finger while fresh socket positions arrive. */
export function ContinuousRange({value,min=0,max,step=.1,label,onCommit,disabled=false,style,className,resetKey}: {
 value:number;min?:number;max:number;step?:number;label:string;onCommit:(value:number)=>void;disabled?:boolean;style?:CSSProperties;className?:string;resetKey?:string;
}) {
 const [draft,setDraft]=useState(value),editing=useRef(false),pending=useRef<number|null>(null),timer=useRef<ReturnType<typeof setTimeout>|undefined>(undefined),send=useRef(onCommit),latest=useRef(value);
 send.current=onCommit;latest.current=value;
 const flush=()=>{clearTimeout(timer.current);timer.current=undefined;const next=pending.current;pending.current=null;if(next!==null)send.current(next);};
 const release=()=>{flush();editing.current=false;};
 useEffect(()=>{if(!editing.current)setDraft(value);},[value]);
 useEffect(()=>{editing.current=false;pending.current=null;clearTimeout(timer.current);setDraft(latest.current);},[resetKey]);
 useEffect(()=>{if(disabled){clearTimeout(timer.current);pending.current=null;editing.current=false;setDraft(latest.current);}},[disabled]);
 useEffect(()=>{window.addEventListener('pointerup',release);window.addEventListener('pointercancel',release);return()=>{clearTimeout(timer.current);window.removeEventListener('pointerup',release);window.removeEventListener('pointercancel',release);};},[]);
 return <input type="range" min={min} max={Math.max(min+step,max)} step={step} value={Math.min(max,Math.max(min,draft))} aria-label={label} disabled={disabled} style={style} className={className}
  onPointerDown={()=>{editing.current=true;}}
  onChange={event=>{editing.current=true;const next=Number(event.target.value);setDraft(next);pending.current=next;if(!timer.current)timer.current=setTimeout(flush,150);}}
  onPointerUp={release} onPointerCancel={release} onKeyUp={release} onBlur={release}/>
}
