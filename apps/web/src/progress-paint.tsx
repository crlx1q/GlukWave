import {useLayoutEffect,useRef,type RefObject} from 'react';
import {time} from './types';
import {progressAdvancing,progressPosition,type ProgressReader} from './progress-clock';

type Paint=()=>number;
const paints=new Set<Paint>();let frame=0,timer:ReturnType<typeof setTimeout>|undefined;
function wake(){clearTimeout(timer);timer=undefined;if(!frame&&!document.hidden&&paints.size)frame=requestAnimationFrame(tick);}
function tick(){frame=0;if(document.hidden)return;let delay=Infinity;for(const paint of paints){const next=paint();if(next)delay=Math.min(delay,next);}if(delay===16)wake();else if(Number.isFinite(delay))timer=setTimeout(wake,delay);}
function visibility(){if(document.hidden){cancelAnimationFrame(frame);clearTimeout(timer);timer=undefined;frame=0;}else wake();}
/** One visible scheduler, isolated DOM writes, no application-wide frame state. */
export function useProgressPaint<T extends Element>(ref:RefObject<T|null>,read:ProgressReader|undefined,paint:(position:number,duration:number)=>void,revision?:unknown){
 const current=useRef({read,paint}),refresh=useRef<()=>void>(()=>{});current.current={read,paint};
 useLayoutEffect(()=>{
  const element=ref.current;if(!element||!read)return;let inView=false,last=0;
  const reduced=matchMedia('(prefers-reduced-motion: reduce)');
  const draw=()=>{if(!inView||document.hidden)return 0;const sample=current.current.read?.();if(!sample)return 0;const now=performance.now(),reduce=reduced.matches||document.documentElement.dataset.motion==='reduce';if(!reduce||now-last>=100){current.current.paint(progressPosition(sample,now),sample.duration);last=now;}return progressAdvancing(sample,now)?reduce?100:16:0;};
  refresh.current=()=>{last=-Infinity;draw();wake();};
  const observer=new IntersectionObserver(entries=>{inView=entries.at(-1)?.isIntersecting||false;refresh.current();});observer.observe(element);
  if(!paints.size)document.addEventListener('visibilitychange',visibility);paints.add(draw);
  return()=>{observer.disconnect();paints.delete(draw);refresh.current=()=>{};if(!paints.size){cancelAnimationFrame(frame);clearTimeout(timer);timer=undefined;frame=0;document.removeEventListener('visibilitychange',visibility);}};
 },[ref,!!read]);
 useLayoutEffect(()=>refresh.current(),[revision]);
}
export function ProgressTime({read,value,revision}:{read:ProgressReader;value:number;revision?:unknown}){const ref=useRef<HTMLSpanElement>(null);useProgressPaint(ref,read,position=>{const text=time(position);if(ref.current&&ref.current.textContent!==text)ref.current.textContent=text;},revision);return <span ref={ref}>{time(value)}</span>;}
