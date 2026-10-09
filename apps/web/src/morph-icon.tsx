import { useMemo } from 'react';
import { MorphIcon } from 'morphicons/react';
import { useStore } from './store';
import { useDocumentVisible } from './visual-lifecycle';

const paths={
  play:'M8 4L20 12L8 20Z',pause:'M7 5V19M17 5V19',
  heart:'M20.8 4.6A5.5 5.5 0 0 0 13 4.6L12 5.6L11 4.6A5.5 5.5 0 0 0 3.2 12.4L12 21L20.8 12.4A5.5 5.5 0 0 0 20.8 4.6Z',
  heartFull:'M21 8C21 2 14 1 12 6C10 1 3 2 3 8C3 13 8 18 12 21C16 18 21 13 21 8Z',
  moon:'M20.9 13A9 9 0 0 1 11 3.1A9 9 0 1 0 20.9 13Z',
  sun:'M16 12A4 4 0 1 1 8 12A4 4 0 1 1 16 12ZM12 2V4M12 20V22M2 12H4M20 12H22M5 5L6.5 6.5M17.5 17.5L19 19M19 5L17.5 6.5M6.5 17.5L5 19',
  menu:'M4 6H20M4 12H20M4 18H20',close:'M6 6L18 18M18 6L6 18',
  home:'M3 10.5L12 3L21 10.5M5 9V19A2 2 0 0 0 7 21H17A2 2 0 0 0 19 19V9M9 21V14H15V21',
  search:'M16 10A6 6 0 1 1 4 10A6 6 0 1 1 16 10ZM14.5 14.5L21 21',
  library:'M4 5V20M9 3V20M15 5L20 19',
  users:'M14 7A3 3 0 1 1 8 7A3 3 0 1 1 14 7ZM4 21V18A6 6 0 0 1 16 18V21M17 4A3 3 0 0 1 17 10M20 21V18A5 5 0 0 0 17 13',
  waves:'M2 8C5 4 7 12 10 8S15 4 18 8S21 12 23 8M2 16C5 12 7 20 10 16S15 12 18 16S21 20 23 16',
  settings:'M4 6H20M4 18H20M8 3V9M16 15V21M4 12H20',
  bell:'M6 16V9A6 6 0 0 1 18 9V16L20 19H4ZM10 22H14',
  previous:'M6 5V19M18 5L8 12L18 19Z',
  next:'M18 5V19M6 5L16 12L6 19Z',
  queue:'M4 5H20M4 11H14M4 17H12M17 15L22 18L17 21Z',
  devices:'M3 4H17V15H3ZM7 19H13M10 15V19M17 10H22V21H17Z',
  volume:'M3 9H7L12 5V19L7 15H3ZM16 8C19 10 19 14 16 16M19 5C24 9 24 15 19 19',
  muted:'M3 9H7L12 5V19L7 15H3ZM17 9L22 14M22 9L17 14',
  shuffle:'M3 6H6L18 18H22M18 14L22 18L18 22M3 18H6L18 6H22M18 2L22 6L18 10',
  repeat:'M5 6H18A3 3 0 0 1 21 9V13M5 2L1 6L5 10M19 18H6A3 3 0 0 1 3 15V11M19 14L23 18L19 22',
  repeatOne:'M5 6H18A3 3 0 0 1 21 9V13M5 2L1 6L5 10M19 18H6A3 3 0 0 1 3 15V11M19 14L23 18L19 22M10 11L12 9V15'
} as const;

/** The original icon paths become genuine interruptible morphicons animations. */
export function AnimatedIcon({name,size=20,className}:{name:keyof typeof paths;size?:number;className?:string}) {
  const store=useStore(),visible=useDocumentVisible();
  return <MotionIcon name={name} size={size} className={className} speed={store.settings.appearance.speed} motion={store.motion&&visible}/>;
}

export function MotionIcon({name,size=20,className='',speed=1,motion=true}:{name:keyof typeof paths;size?:number;className?:string;speed?:number;motion?:boolean}){
  const spring=useMemo(()=>({stiffness:180*speed*speed,damping:24*speed}),[speed]);
  if(name==='heart'||name==='heartFull')return <svg width={size} height={size} viewBox="0 0 24 24" className={`heart-icon icon-${name} ${name==='heartFull'?'filled':''} ${className}`} aria-hidden="true" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round"><path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8l1.1 1.1L12 21l7.8-7.5 1.1-1.1a5.5 5.5 0 0 0-.1-7.8Z"/></svg>;
  return <MorphIcon icon={paths[name]} size={size} className={`animated-icon icon-${name} ${className}`} strokeWidth={1.75} strokeLinecap="round" strokeLinejoin="round" fill="none" spring={spring} reducedMotion={motion?'user':'always'}/>;
}
