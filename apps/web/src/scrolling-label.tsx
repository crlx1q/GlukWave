import {useLayoutEffect,useRef,useState,type CSSProperties} from 'react';
import {useVisualVisibility} from './visual-lifecycle';
import './scrolling-label.css';

/** Only overflowing, visible labels move. The accessible text remains intact. */
export function ScrollingLabel({text,motion=true,className=''}:{text:string;motion?:boolean;className?:string}) {
 const box=useRef<HTMLSpanElement>(null),ink=useRef<HTMLSpanElement>(null),[distance,setDistance]=useState(0),visible=useVisualVisibility(box,distance>1,distance);
 useLayoutEffect(()=>{const host=box.current,label=ink.current;if(!host||!label)return;let live=true;const measure=()=>{if(live)setDistance(Math.max(0,label.scrollWidth-host.clientWidth));};const observer=new ResizeObserver(measure);observer.observe(host);observer.observe(label);measure();void document.fonts.ready.then(measure);document.fonts.addEventListener('loadingdone',measure);return()=>{live=false;observer.disconnect();document.fonts.removeEventListener('loadingdone',measure);};},[text]);
 const moving=distance>1&&motion&&visible;
 return <span ref={box} className={`scrolling-label ${className}`} data-overflow={distance>1} data-moving={moving} style={{'--label-distance':`${distance}px`,'--label-duration':`${Math.max(4,distance/28+3)}s`} as CSSProperties}><span ref={ink} className="scrolling-label-ink">{text}</span></span>;
}
