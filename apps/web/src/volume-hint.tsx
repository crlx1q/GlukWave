import {useEffect,useLayoutEffect,useRef,useState,type RefObject} from 'react';
import {createPortal} from 'react-dom';

/** A portal keeps the small label above clipped player surfaces. */
export function useVolumeHint(input:RefObject<HTMLInputElement|null>,enabled:boolean,scope:unknown){
 const [visible,setVisible]=useState(false),delay=useRef<ReturnType<typeof setTimeout>|undefined>(undefined);
 const hide=()=>{clearTimeout(delay.current);delay.current=undefined;setVisible(false);};
 const enter=()=>{if(!enabled||input.current?.disabled)return;clearTimeout(delay.current);delay.current=setTimeout(()=>setVisible(true),1000);};
 useEffect(()=>{hide();},[scope,enabled]);
 useEffect(()=>{window.addEventListener('blur',hide);return()=>{clearTimeout(delay.current);window.removeEventListener('blur',hide);};},[]);
 return {hint:enabled&&visible?<VolumeHint input={input}/>:null,enter,hide};
}

function VolumeHint({input}:{input:RefObject<HTMLInputElement|null>}){
 const bubble=useRef<HTMLDivElement>(null);
 useLayoutEffect(()=>{let frame=0;const paint=()=>{const node=input.current,label=bubble.current;if(!node||!label)return;const rect=node.getBoundingClientRect(),ratio=(Number(node.value)-Number(node.min))/(Number(node.max)-Number(node.min)||1),zoom=Number(getComputedStyle(document.documentElement).zoom)||1,thumb=14*rect.width/(node.offsetWidth||rect.width),x=rect.left+thumb/2+Math.max(0,Math.min(1,ratio))*(rect.width-thumb),viewport=window.visualViewport,left=viewport?.offsetLeft||0,right=left+(viewport?.width||innerWidth),width=label.getBoundingClientRect().width;label.textContent=`${Math.round(Number(node.value)*100)}%`;label.style.left=`${Math.max(left+6+width/2,Math.min(right-6-width/2,x))/zoom}px`;label.style.top=`${Math.max(6,rect.top-8)/zoom}px`;label.style.visibility='visible';frame=requestAnimationFrame(paint);};paint();return()=>cancelAnimationFrame(frame);},[input]);
 return createPortal(<div ref={bubble} className="volume-thumb-hint" role="tooltip" style={{visibility:'hidden'}}>0%</div>,document.body);
}
