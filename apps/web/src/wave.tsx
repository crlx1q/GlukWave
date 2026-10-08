import { useEffect, useRef } from 'react';
import { useStore } from './store';
import { usePlayer } from './player';
import { api } from './api';
import type { Appearance } from './types';
import { BLOOM, bloomDot, easeEnergy, envelopeAt, type AudioEnvelope, type WavePointer } from './wave-math';
import { createHalftoneBloom, rgb, type WaveFrame } from './vendor/halftone-bloom';
import { createSilkWave, drawFlowRibbon } from './wave-silk';

function drawCanvas(context:CanvasRenderingContext2D,frame:WaveFrame,style:Appearance['waveStyle']) {
  const {width,height,phase,energy,pointer,tint,background}=frame,tone=rgb(tint).map(value=>Math.round(value*255));context.clearRect(0,0,width,height);
  if(style==='bloom'){
    context.fillStyle=background;context.fillRect(0,0,width,height);const cell=BLOOM.cell,cos=Math.cos(BLOOM.turn),sin=Math.sin(BLOOM.turn),columns=Math.ceil((width*cos+height*sin)/cell)+1,firstRow=Math.floor(-width*sin/cell)-1,lastRow=Math.ceil(height*cos/cell)+1;
    for(let row=firstRow;row<=lastRow;row++)for(let col=-1;col<=columns;col++){
      const cx=(col+.5)*cell,cy=(row+.5)*cell,x=cx*cos-cy*sin,y=cx*sin+cy*cos;if(x<-cell||x>width+cell||y<-cell||y>height+cell)continue;
      const u=x/width,v=y/height,dot=bloomDot(u,v,phase,energy,pointer,width/height);if(dot.level<.003)continue;
      const mix=.5+.5*Math.sin(u*6+phase*.23),color=tone.map((value,index)=>Math.min(255,value*(.55+.15*mix)+(.4*(1-mix)+[.24,.3,.34][index]*mix)*255));
      context.fillStyle=`rgba(${color.join(',')},${dot.presence*(.5+dot.level*.5)})`;context.beginPath();context.arc(x,y,cell*dot.radius,0,Math.PI*2);context.fill();
    }
  }else if(style==='particles'){
    const columns=Math.min(125,Math.max(55,Math.round(width/5)));
    for(let layer=0;layer<3;layer++)for(let point=0;point<columns;point++)for(let band=0;band<5;band++){
      const u=point/(columns-1),x=u*width,y=height*.53+Math.sin(u*9+phase*.5+layer*.7)*height*(.15+energy*.018)+Math.cos(u*14-phase*.7+band*.25)*height*.055+(band-2)*5+Math.sin(point*127+band*73+layer)*7+(pointer.y-.5)*pointer.active*10;
      context.fillStyle=`rgba(${tone.map(value=>Math.min(255,value+layer*20)).join(',')},${.2+(.5+.5*Math.sin(point*27+band+layer))*.53})`;context.beginPath();context.arc(x,y,.45+(Math.sin(point*13+band)+1)*.3+energy*.3,0,Math.PI*2);context.fill();
    }
  }else{drawFlowRibbon(context,frame);
  }
}

export function WaveVisual({className='wave-canvas',color,background:backgroundOverride,waveStyle,speed}:{className?:string;color?:string;background?:string;waveStyle?:Appearance['waveStyle'];speed?:number}) {
  const root=useRef<HTMLDivElement>(null),canvas=useRef<HTMLCanvasElement>(null),fallback=useRef<HTMLCanvasElement>(null),store=useStore(),player=usePlayer(),envelope=useRef<AudioEnvelope|null>(null);
  const style=waveStyle||store.settings.appearance.waveStyle,velocity=speed??store.settings.appearance.speed,tint=color||store.settings.appearance[store.resolvedTheme].accent,motion=store.motion,paused=player.full;
  const audio=useRef({playing:player.state.playing,position:player.state.position,local:player.playback?.kind==='audio',sample:player.audioEnergy});audio.current={playing:player.state.playing,position:player.state.position,local:player.playback?.kind==='audio',sample:player.audioEnergy};
  useEffect(()=>{
    envelope.current=null;if(!player.track)return;const controller=new AbortController();
    void api<AudioEnvelope>(`/tracks/${encodeURIComponent(player.track.id)}/waveform`,{signal:controller.signal}).then(result=>{if(!controller.signal.aborted&&result.available&&result.duration>0&&Array.isArray(result.samples)&&result.samples.length<=4096)envelope.current={...result,samples:result.samples.map(value=>Math.max(0,Math.min(1,Number(value)||0)))};}).catch(()=>{});
    return()=>{controller.abort();envelope.current=null;};
  },[player.track?.id,store.user?.id]);
  useEffect(()=>{
    const host=root.current,element=canvas.current,backup=fallback.current,context=backup?.getContext('2d');if(!host||!element||!backup||!context)return;
    const renderer=style==='bloom'?createHalftoneBloom(element):style==='silk'?createSilkWave(element):null;
    const parent=host.parentElement||host,pointer:WavePointer={x:.5,y:.5,active:0},target:WavePointer={...pointer,vx:0,vy:0};let frame=0,inView=true,last=0,lastPointer=0,phase=BLOOM.phase as number,energy=0,width=0,height=0,ratio=1;
    const background=backgroundOverride||store.settings.appearance[store.resolvedTheme].bg;
    const resize=()=>{const rect=host.getBoundingClientRect();width=rect.width;height=rect.height;ratio=Math.min(devicePixelRatio||1,1.5,1100/Math.max(1,width),520/Math.max(1,height));for(const item of [element,backup]){item.width=Math.max(1,Math.round(width*ratio));item.height=Math.max(1,Math.round(height*ratio));}};
    const draw=(now:number,force=false)=>{
      if(document.hidden||!inView||paused||!width||!height)return;
      const interval=width<500?1000/24:1000/30;if(!force&&motion&&last&&now-last<interval){frame=requestAnimationFrame(draw);return;}
      const dt=last?Math.min(.07,(now-last)/1000):0;last=now;if(motion)phase+=dt*velocity;
      const state=audio.current,measured=state.playing?(state.local?state.sample():null):0,targetEnergy=measured??envelopeAt(envelope.current,state.position,state.playing);energy=motion?easeEnergy(energy,targetEnergy,dt):0;
      if(motion){const k=1-Math.exp(-dt*12);pointer.x+=(target.x-pointer.x)*k;pointer.y+=(target.y-pointer.y)*k;pointer.active+=(target.active-pointer.active)*(1-Math.exp(-dt*5));pointer.vx=(pointer.vx||0)+((target.vx||0)-(pointer.vx||0))*k;pointer.vy=(pointer.vy||0)+((target.vy||0)-(pointer.vy||0))*k;target.vx=(target.vx||0)*Math.exp(-dt*8);target.vy=(target.vy||0)*Math.exp(-dt*8);}
      const value:WaveFrame={width,height,phase,energy,pointer,tint,background},gpu=renderer?.draw(value)===true;element.style.display=gpu?'block':'none';backup.style.display=gpu?'none':'block';
      if(!gpu){context.setTransform(ratio,0,0,ratio,0,0);drawCanvas(context,value,style);}
      if(motion)frame=requestAnimationFrame(draw);
    };
    const repaint=()=>{cancelAnimationFrame(frame);last=0;if(!document.hidden&&inView&&!paused){resize();draw(performance.now(),true);}};
    const read=(event:PointerEvent)=>{if(!motion||event.pointerType==='touch'&&event.buttons===0)return;const rect=host.getBoundingClientRect(),now=performance.now(),x=Math.max(0,Math.min(1,(event.clientX-rect.left)/Math.max(1,rect.width))),y=Math.max(0,Math.min(1,(event.clientY-rect.top)/Math.max(1,rect.height)));const seconds=Math.max(.016,Math.min(.15,(now-lastPointer)/1000));if(lastPointer&&target.active){target.vx=Math.max(-1.8,Math.min(1.8,(x-target.x)/seconds));target.vy=Math.max(-1.8,Math.min(1.8,(y-target.y)/seconds));}target.x=x;target.y=y;target.active=1;lastPointer=now;};
    const leave=()=>{target.active=0;target.vx=0;target.vy=0;lastPointer=0;};
    const touchEnd=(event:PointerEvent)=>{if(event.pointerType==='touch')leave();};
    const contextLost=()=>repaint();
    const observer=new IntersectionObserver(entries=>{inView=entries[0].isIntersecting;repaint();}),size=new ResizeObserver(repaint);observer.observe(host);size.observe(host);parent.addEventListener('pointermove',read,{passive:true});parent.addEventListener('pointerleave',leave);parent.addEventListener('pointerup',touchEnd,{passive:true});parent.addEventListener('pointercancel',leave);element.addEventListener('webglcontextlost',contextLost);document.addEventListener('visibilitychange',repaint);repaint();
    return()=>{cancelAnimationFrame(frame);renderer?.dispose();observer.disconnect();size.disconnect();parent.removeEventListener('pointermove',read);parent.removeEventListener('pointerleave',leave);parent.removeEventListener('pointerup',touchEnd);parent.removeEventListener('pointercancel',leave);element.removeEventListener('webglcontextlost',contextLost);document.removeEventListener('visibilitychange',repaint);};
  },[style,velocity,tint,backgroundOverride,motion,paused,store.resolvedTheme,store.settings.appearance.light.bg,store.settings.appearance.dark.bg,store.settings.appearance.amoled.bg]);
  return <div ref={root} className={className} aria-hidden="true"><canvas key={style} ref={canvas} className="wave-layer"/><canvas ref={fallback} className="wave-layer"/></div>;
}
