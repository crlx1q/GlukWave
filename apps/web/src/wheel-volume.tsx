import {useEffect,useRef,useState,type ReactNode} from 'react';
import {wheelVolume} from './volume';

export function WheelVolume({children,className='',value,onChange,onDraft,onCancel,resetKey}:{children:(volume:number,wheelRevision:number)=>ReactNode;className?:string;value:number;onChange:(volume:number)=>void;onDraft?:(volume:number)=>void;onCancel?:()=>void;resetKey?:string}) {
 const box=useRef<HTMLDivElement>(null),[draft,setDraft]=useState(value),[wheelRevision,setWheelRevision]=useState(0),current=useRef({value,onChange,onDraft,onCancel}),timer=useRef<ReturnType<typeof setTimeout>|undefined>(undefined),wheelEditing=useRef(false);current.current.onChange=onChange;current.current.onDraft=onDraft;current.current.onCancel=onCancel;
 useEffect(()=>{if(!wheelEditing.current){current.current.value=value;setDraft(value);}},[value]);
 useEffect(()=>{clearTimeout(timer.current);timer.current=undefined;if(wheelEditing.current)current.current.onCancel?.();wheelEditing.current=false;current.current.value=value;setDraft(value);},[resetKey]);
 const commitWheel=()=>{if(!wheelEditing.current)return;clearTimeout(timer.current);timer.current=undefined;wheelEditing.current=false;current.current.onChange(current.current.value);};
 useEffect(()=>{
  const node=box.current;if(!node)return;
  const wheel=(event:WheelEvent)=>{
   if(event.ctrlKey||!event.deltaY)return;
   event.preventDefault();
   if(node.querySelector('[data-range-editing=true]'))return;
   const next=wheelVolume(current.current.value,event.deltaY);
   if(next===current.current.value)return;
   wheelEditing.current=true;current.current.value=next;setDraft(next);setWheelRevision(revision=>revision+1);
   current.current.onDraft?.(next);clearTimeout(timer.current);timer.current=setTimeout(commitWheel,240);
  };
  node.addEventListener('wheel',wheel,{passive:false});
  return()=>{clearTimeout(timer.current);if(wheelEditing.current)current.current.onCancel?.();node.removeEventListener('wheel',wheel);};
 },[]);
 return <div className={className} ref={box} onPointerDownCapture={commitWheel} onKeyDownCapture={commitWheel}>{children(draft,wheelRevision)}</div>;
}
