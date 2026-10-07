import { useMemo } from 'react';
import { MorphIcon } from 'morphicons/react';
import { useStore } from './store';

const paths={
  play:'M8 4L20 12L8 20Z',pause:'M7 5V19M17 5V19',
  heart:'M20.8 4.6A5.5 5.5 0 0 0 13 4.6L12 5.6L11 4.6A5.5 5.5 0 0 0 3.2 12.4L12 21L20.8 12.4A5.5 5.5 0 0 0 20.8 4.6Z',
  heartFull:'M21 8C21 2 14 1 12 6C10 1 3 2 3 8C3 13 8 18 12 21C16 18 21 13 21 8Z',
  moon:'M20.9 13A9 9 0 0 1 11 3.1A9 9 0 1 0 20.9 13Z',
  sun:'M16 12A4 4 0 1 1 8 12A4 4 0 1 1 16 12ZM12 2V4M12 20V22M2 12H4M20 12H22M5 5L6.5 6.5M17.5 17.5L19 19M19 5L17.5 6.5M6.5 17.5L5 19',
  menu:'M4 6H20M4 12H20M4 18H20',close:'M6 6L18 18M18 6L6 18'
} as const;

/** The original icon paths become genuine interruptible morphicons animations. */
export function AnimatedIcon({name,size=20,className}:{name:keyof typeof paths;size?:number;className?:string}) {
  const store=useStore(),speed=store.settings.appearance.speed;
  const spring=useMemo(()=>({stiffness:180*speed*speed,damping:24*speed}),[speed]);
  if(name==='heart'||name==='heartFull')return <svg width={size} height={size} viewBox="0 0 24 24" className={`heart-icon ${name==='heartFull'?'filled':''} ${className||''}`} aria-hidden="true" fill={name==='heartFull'?'currentColor':'none'} stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round"><path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8l1.1 1.1L12 21l7.8-7.5 1.1-1.1a5.5 5.5 0 0 0-.1-7.8Z"/></svg>;
  return <MorphIcon icon={paths[name]} size={size} className={className} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" fill="none" spring={spring} reducedMotion={store.motion?'user':'always'}/>;
}
