/** Shared normalized field for the web shader, Canvas fallback and Flutter painter.
 * Time is seconds multiplied by the user's animation speed. Energy is measured,
 * never inferred from elapsed time. Pointer coordinates are normalized top-left.
 */
export const BLOOM = {turn:.32,rest:.78,swell:1.1,cap:.55,reach:.32,phase:.8,cell:6} as const;
export type WavePointer={x:number;y:number;active:number;vx?:number;vy?:number};
export const clamp01=(value:number)=>Math.max(0,Math.min(1,value));
export const smoothstep=(a:number,b:number,value:number)=>{const t=clamp01((value-a)/(b-a));return t*t*(3-2*t);};

export function bloomField(u:number,v:number,phase:number,energy:number):number {
  const e=clamp01(energy),envelope=Math.sin(Math.PI*u);
  const centre=.52+Math.sin(u*7.54+phase*.65)*.145+Math.sin(u*13.19-phase*.38)*.065;
  const width=(.042+.012*Math.sin(u*9.42+phase*.23))*(1+e*.3);
  const band=(offset:number,scale:number)=>Math.exp(-(((v-centre-offset)/(width*scale))**2)*.65);
  const level=(.82*band(0,1)+.27*band(.11*Math.sin(u*5.2-phase*.24)+.075,.68)+.2*band(-.1,.6))*(.35+.65*envelope)*(1+e*.25);
  return clamp01(level);
}

export function bloomDot(u:number,v:number,phase:number,energy:number,pointer:WavePointer,aspect:number) {
  const level=bloomField(u,v,phase,energy),dx=(u-pointer.x)*aspect/BLOOM.reach,dy=(v-pointer.y)/BLOOM.reach;
  const influence=clamp01(pointer.active)*Math.exp(-dx*dx-dy*dy);
  return {level,radius:Math.min(BLOOM.cap,Math.sqrt(Math.pow(level,.9)/Math.PI)*(1+BLOOM.swell*influence)),presence:smoothstep(.03,.16,level)*BLOOM.rest*(1-influence)+influence};
}

export type AudioEnvelope={available:boolean;duration:number;samples:number[];source:'soundcloud-envelope'|'decoded-pcm'|null};
export function envelopeAt(envelope:AudioEnvelope|null,position:number,playing:boolean):number {
  if(!playing||!envelope?.available||envelope.duration<=0||!envelope.samples.length)return 0;
  const index=clamp01(position/envelope.duration)*(envelope.samples.length-1),low=Math.floor(index),high=Math.min(envelope.samples.length-1,low+1),part=index-low;
  return clamp01(envelope.samples[low]*(1-part)+envelope.samples[high]*part);
}
export function easeEnergy(current:number,target:number,seconds:number):number {
  return current+(target-current)*(1-Math.exp(-Math.min(.07,seconds)/(target>current ? .08 : .24)));
}

export const bloomFieldGLSL=`
float waveField(vec2 p,float t,float energy) {
  float e=clamp(energy,0.0,1.0),envelope=sin(3.14159265359*p.x);
  float centre=.52+sin(p.x*7.54+t*.65)*.145+sin(p.x*13.19-t*.38)*.065;
  float width=(.042+.012*sin(p.x*9.42+t*.23))*(1.0+e*.3);
  float a=(p.y-centre)/width;
  float b=(p.y-centre-(.11*sin(p.x*5.2-t*.24)+.075))/(width*.68);
  float c=(p.y-centre+.1)/(width*.6);
  return clamp((.82*exp(-a*a*.65)+.27*exp(-b*b*.65)+.2*exp(-c*c*.65))*(.35+.65*envelope)*(1.0+e*.25),0.0,1.0);
}`;
