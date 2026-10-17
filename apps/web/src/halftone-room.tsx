import { useEffect, useRef } from 'react';
import { useStore } from './store';

/** Original GlukWave sound rings, painted in a bounded dot grid. No remote art,
 * shaders or background video. Hidden and reduced-motion scenes are static. */
export function HalftoneRoom() {
 const canvas=useRef<HTMLCanvasElement>(null),{motion}=useStore();
 useEffect(()=>{
  const node=canvas.current;if(!node)return;const context=node.getContext('2d');if(!context)return;
  let frame=0,last=0,phase=0,width=1,height=1;
  const draw=()=>{context.clearRect(0,0,width,height);const step=Math.max(14,width/76,height/62);context.fillStyle=getComputedStyle(node).getPropertyValue('--accent').trim()||'#c5a779';context.globalAlpha=.44;for(let y=step/2;y<height;y+=step)for(let x=step/2;x<width;x+=step){const dx=(x-width*.28)/width,dy=(y-height*.48)/height,ring=Math.sqrt(dx*dx+dy*dy*.65),wave=(Math.sin(ring*27-phase)+Math.cos((dx-dy)*13+phase))*.25+.5,radius=(.35+wave*3.1)*Math.exp(-ring*ring*4.2);if(radius>.3){context.beginPath();context.arc(x,y,radius,0,Math.PI*2);context.fill();}}};
  const resize=()=>{const box=node.getBoundingClientRect(),ratio=Math.min(1.5,devicePixelRatio||1);width=Math.max(1,box.width);height=Math.max(1,box.height);node.width=Math.round(width*ratio);node.height=Math.round(height*ratio);context.setTransform(ratio,0,0,ratio,0,0);draw();};
  const tick=(now:number)=>{if(document.hidden||!motion)return;if(now-last>=40){phase=(now%32000)/32000*Math.PI*2;last=now;draw();}frame=requestAnimationFrame(tick);};
  const start=()=>{cancelAnimationFrame(frame);draw();if(motion&&!document.hidden)frame=requestAnimationFrame(tick);};
  const observer=new ResizeObserver(resize);observer.observe(node);resize();start();document.addEventListener('visibilitychange',start);
  return()=>{cancelAnimationFrame(frame);observer.disconnect();document.removeEventListener('visibilitychange',start);};
 },[motion]);
 return <canvas ref={canvas} className="halftone-room" aria-hidden="true"/>;
}
