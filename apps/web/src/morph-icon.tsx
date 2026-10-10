import { useMemo } from 'react';
import { MorphIcon } from 'morphicons/react';
import { useStore } from './store';
import { useDocumentVisible } from './visual-lifecycle';

const paths={
  play:'M8.5 5.2C8 4.9 7.5 5.2 7.5 5.8V18.2C7.5 18.8 8 19.1 8.5 18.8L18.8 12.6C19.3 12.3 19.3 11.7 18.8 11.4Z',pause:'M8 5.5V18.5M16 5.5V18.5',
  heart:'M19.5 5.5C17.5 3.5 14.4 4 12 6.5C9.6 4 6.5 3.5 4.5 5.5C2.5 7.5 3 10.7 5.1 12.8L12 19.5L18.9 12.8C21 10.7 21.5 7.5 19.5 5.5Z',
  heartFull:'M19.5 5.5C17.5 3.5 14.4 4 12 6.5C9.6 4 6.5 3.5 4.5 5.5C2.5 7.5 3 10.7 5.1 12.8L12 19.5L18.9 12.8C21 10.7 21.5 7.5 19.5 5.5Z',
  moon:'M20 13.1A8.1 8.1 0 0 1 10.9 4A8.1 8.1 0 1 0 20 13.1Z',
  sun:'M15.5 12A3.5 3.5 0 1 1 8.5 12A3.5 3.5 0 1 1 15.5 12ZM12 3V4.5M12 19.5V21M3 12H4.5M19.5 12H21M5.6 5.6L6.7 6.7M17.3 17.3L18.4 18.4M18.4 5.6L17.3 6.7M6.7 17.3L5.6 18.4',
  menu:'M4.5 6.5H19.5M4.5 12H19.5M4.5 17.5H19.5',close:'M6.5 6.5L17.5 17.5M17.5 6.5L6.5 17.5',
  home:'M3.5 10L10.8 4A2 2 0 0 1 13.2 4L20.5 10M5.5 9V18A2 2 0 0 0 7.5 20H16.5A2 2 0 0 0 18.5 18V9M9.5 20V14H14.5V20',
  search:'M16.5 10.5A6 6 0 1 1 4.5 10.5A6 6 0 1 1 16.5 10.5ZM15 15L20 20',
  library:'M5 5V19M10 4V19M15 5L19 18.5',
  users:'M13.5 7.5A3 3 0 1 1 7.5 7.5A3 3 0 1 1 13.5 7.5ZM4 20V18A6.5 6.5 0 0 1 17 18V20M17 4.5A3 3 0 0 1 17 10.5M20 20V18A5 5 0 0 0 17.5 13.7',
  waves:'M3 8.5C6 5.5 7 11.5 10 8.5S14 5.5 17 8.5S19.5 11.5 21 8.5M3 15.5C6 12.5 7 18.5 10 15.5S14 12.5 17 15.5S19.5 18.5 21 15.5',
  settings:'M10 3H14L14.6 5.4A7 7 0 0 1 16.5 6.5L19 5.9L21 9.3L19.2 11A7 7 0 0 1 19.2 13L21 14.7L19 18.1L16.5 17.5A7 7 0 0 1 14.6 18.6L14 21H10L9.4 18.6A7 7 0 0 1 7.5 17.5L5 18.1L3 14.7L4.8 13A7 7 0 0 1 4.8 11L3 9.3L5 5.9L7.5 6.5A7 7 0 0 1 9.4 5.4ZM15.2 12A3.2 3.2 0 1 1 8.8 12A3.2 3.2 0 1 1 15.2 12Z',
  equalizer:'M5.5 4V8M5.5 13V20M12 4V14M12 19V20M18.5 4V5M18.5 10V20M3.5 8H7.5V13H3.5ZM10 14H14V19H10ZM16.5 5H20.5V10H16.5Z',
  bell:'M6 16V10A6 6 0 0 1 18 10V16L19.5 18H4.5ZM10 21H14',
  previous:'M5.5 5.5V18.5M17.7 6L8.5 11.4C8 11.7 8 12.3 8.5 12.6L17.7 18C18.1 18.3 18.5 18 18.5 17.5V6.5C18.5 6 18.1 5.7 17.7 6Z',
  next:'M18.5 5.5V18.5M6.3 6L15.5 11.4C16 11.7 16 12.3 15.5 12.6L6.3 18C5.9 18.3 5.5 18 5.5 17.5V6.5C5.5 6 5.9 5.7 6.3 6Z',
  queue:'M4 5H20M4 10.5H15M4 16H11M17 14L21 17L17 20Z',
  devices:'M4 4.5H16A1.5 1.5 0 0 1 17.5 6V14A1.5 1.5 0 0 1 16 15.5H4A1.5 1.5 0 0 1 2.5 14V6A1.5 1.5 0 0 1 4 4.5ZM7 19H13M10 15.5V19M18 10.5H21A1 1 0 0 1 22 11.5V20A1 1 0 0 1 21 21H18A1 1 0 0 1 17 20V11.5A1 1 0 0 1 18 10.5Z',
  volume:'M4 9H7.5L11.5 5.5V18.5L7.5 15H4ZM15.5 8.5C18 10.5 18 13.5 15.5 15.5M18.5 5.5C22.5 9 22.5 15 18.5 18.5',
  muted:'M4 9H7.5L11.5 5.5V18.5L7.5 15H4ZM16.5 9.5L21 14M21 9.5L16.5 14',
  shuffle:'M3.5 6.5H5.5C10 6.5 13.5 17.5 18 17.5H20.5M17.5 14.5L20.5 17.5L17.5 20.5M3.5 17.5H5.5C7.5 17.5 9 15.5 10 14M14 10C15.5 7.8 16.5 6.5 18 6.5H20.5M17.5 3.5L20.5 6.5L17.5 9.5',
  repeat:'M5 7H17A3.5 3.5 0 0 1 20.5 10.5V12M8 4L5 7L8 10M19 17H7A3.5 3.5 0 0 1 3.5 13.5V12M16 14L19 17L16 20',
  repeatOne:'M5 7H17A3.5 3.5 0 0 1 20.5 10.5V12M8 4L5 7L8 10M19 17H7A3.5 3.5 0 0 1 3.5 13.5V12M16 14L19 17L16 20M10.5 11L12 9.5V14.5',
  expand:'M4.5 9V4.5H9M15 4.5H19.5V9M19.5 15V19.5H15M9 19.5H4.5V15',
  mini:'M5 4.5H19A1.5 1.5 0 0 1 20.5 6V18A1.5 1.5 0 0 1 19 19.5H5A1.5 1.5 0 0 1 3.5 18V6A1.5 1.5 0 0 1 5 4.5ZM12 12H18V17H12Z',
  down:'M6 9L12 15L18 9'
} as const;

/** The original icon paths become genuine interruptible morphicons animations. */
export function AnimatedIcon({name,size=20,className}:{name:keyof typeof paths;size?:number;className?:string}) {
  const store=useStore(),visible=useDocumentVisible();
  return <MotionIcon name={name} size={size} className={className} speed={store.settings.appearance.speed} motion={store.motion&&visible}/>;
}

export function MotionIcon({name,size=20,className='',speed=1,motion=true}:{name:keyof typeof paths;size?:number;className?:string;speed?:number;motion?:boolean}){
  const spring=useMemo(()=>({stiffness:180*speed*speed,damping:24*speed}),[speed]);
  if(name==='heart'||name==='heartFull')return <svg width={size} height={size} viewBox="0 0 24 24" className={`heart-icon icon-${name} ${name==='heartFull'?'filled':''} ${className}`} aria-hidden="true" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round"><path d={paths.heart}/></svg>;
  return <MorphIcon icon={paths[name]} size={size} className={`animated-icon icon-${name} ${className}`} strokeWidth={1.75} strokeLinecap="round" strokeLinejoin="round" fill="none" spring={spring} reducedMotion={motion?'user':'always'}/>;
}
