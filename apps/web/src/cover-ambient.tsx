import {useEffect,useRef,useState} from 'react';
import {useVisualVisibility} from './visual-lifecycle';

/** The image is filtered once; only its oversized wrapper drifts. */
export function CoverAmbient({artwork,active,playing,motion,blur}:{artwork:string|undefined;active:boolean;playing:boolean;motion:boolean;blur:boolean}){
 const element=useRef<HTMLDivElement>(null),visible=useVisualVisibility(element,active&&blur&&!!artwork),[images,setImages]=useState<{current?:string;previous?:string}>({current:artwork}),current=useRef(artwork);
 useEffect(()=>{if(!blur||!artwork||artwork===current.current){setImages(value=>value.previous?{current:value.current}:value);return;}const preload=new Image();let live=true,timer:ReturnType<typeof setTimeout>|undefined;preload.onload=()=>{if(!live)return;const previous=current.current;current.current=artwork;setImages({current:artwork,previous:motion?previous:undefined});timer=setTimeout(()=>{if(live)setImages({current:artwork});},900);};preload.src=artwork;return()=>{live=false;clearTimeout(timer);preload.onload=null;};},[artwork,blur,motion]);
 return <div ref={element} className="np-backdrop" aria-hidden="true" data-ambient-moving={visible&&playing&&motion} data-visual-visible={visible}>{blur&&images.current&&<div className="np-backdrop-drift">{images.previous&&<div className="np-backdrop-image ambient-previous" style={{backgroundImage:`url(${JSON.stringify(images.previous)})`}}/>}<div key={images.current} className={`np-backdrop-image ${images.previous?'ambient-enter':''}`} style={{backgroundImage:`url(${JSON.stringify(images.current)})`}}/></div>}</div>;
}
