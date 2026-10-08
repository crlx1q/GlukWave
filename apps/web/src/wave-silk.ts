import { rgb, type WaveFrame, type WaveRenderer } from './vendor/halftone-bloom';

/** Flow ribbon adapted from the owner's index(3).html WaveEngine. Asymmetric
 * folds remain; click impulses and synthetic audio do not. `silk` is retained
 * as the persisted key for compatibility with existing appearance preferences. */
const vertex=`precision highp float;
attribute vec4 aSeed;
uniform float uTime,uEnergy,uRatio,uActive;
uniform vec2 uSize,uPointer,uVelocity;
varying float vAlpha,vAccent;
void main(){
 float u=aSeed.x,v=aSeed.y,seed=aSeed.z,depth=aSeed.w;
 float t=uTime*.24,envelope=sin(u*3.14159265);
 float fa=exp(-pow((u-.31)/.13,2.)),fb=exp(-pow((u-.70)/.105,2.));
 float cy=.62*sin(u*5.15+t)+.27*sin(u*12.4-t*.72)+.14*cos(u*23.+t*.37);
 cy+=.16*sin(u*7.1+1.7)+.10*cos(u*13.7-2.2);
 cy+=fa*.48*cos((u-.31)*14.-t*.18)-fb*.55*cos((u-.70)*17.+t*.24);
 float width=abs(.56*(.48+.52*sin(u*8.+1.2)*sin(u*3.7-2.)))+.10;
 width*=mix(.62,1.18,.5+.5*sin(u*4.3+2.4))*(1.48+uEnergy*.44);
 float layer=floor(mod(seed,3.))-1.;
 cy+=layer*.13*sin(u*9.2+t*.44);
 float angle=u*13.5+sin(u*7.2+t)*1.15+uEnergy*.24+layer*.2;
 float yy=v*width*cos(angle)+sin(seed*31.+uTime*1.3)*.012;
 float zz=v*width*sin(angle)+cos(seed*19.+uTime*.9)*.012;
 float x=.018+u*.964+envelope*(fa*.026*sin((u-.31)*18.+t*.42)+fb*.020*sin((u-.70)*24.-t*.36));
 float y=.57+(cy+yy)*.19;
 vec2 delta=(vec2(x,y)-uPointer)*uSize;
 float radius=clamp(uSize.y*.42,65.,145.);
 float influence=exp(-dot(delta,delta)/(radius*radius))*uActive;
 float turn=influence*clamp(length(uVelocity),0.,1.8)*1.05;
 y+=(yy*cos(turn)-zz*sin(turn)-yy)*.19+influence*(uPointer.y-y)*.17;
 y+=influence*uVelocity.y*.025;x+=influence*uVelocity.x*.012*envelope;
 gl_Position=vec4(x*2.-1.,1.-y*2.,0.,1.);
 gl_PointSize=(1.05+depth*1.05)*(1.+uEnergy*.13)*uRatio;
 vAlpha=(.38+depth*.53)*(.70+.30*sin(seed*8.)*sin(seed*8.));vAccent=step(.84,depth);
}`;
const fragment=`precision mediump float;
uniform vec3 uColor,uAccent;
varying float vAlpha,vAccent;
void main(){vec2 p=gl_PointCoord-.5;float d=dot(p,p);if(d>.25)discard;
gl_FragColor=vec4(mix(uColor,uAccent,vAccent*.64),(1.-smoothstep(.045,.25,d))*vAlpha);}`;
function random(index:number){const n=Math.sin(index*127.1+311.7)*43758.5453123;return n-Math.floor(n);}
export function ribbonSeeds(count:number){const values=new Float32Array(count*4);for(let i=0;i<count;i++)values.set([random(i*4),random(i*4+1)*2-1,random(i*4+2)*1000,random(i*4+3)],i*4);return values;}
const seeds=ribbonSeeds(20000);
function colors(frame:WaveFrame){const tint=rgb(frame.tint),bg=rgb(frame.background),dark=bg[0]*.2126+bg[1]*.7152+bg[2]*.0722<.48;return {base:tint.map(v=>dark?.72+v*.24:v*.45),accent:tint.map(v=>dark?.40+v*.58:v*.68)};}
export function createSilkWave(canvas:HTMLCanvasElement):WaveRenderer|null {
 const gl=canvas.getContext('webgl',{alpha:true,antialias:false,premultipliedAlpha:false,powerPreference:'low-power'});if(!gl)return null;
 const compile=(type:number,text:string)=>{const shader=gl.createShader(type);if(!shader)return null;gl.shaderSource(shader,text);gl.compileShader(shader);if(!gl.getShaderParameter(shader,gl.COMPILE_STATUS)){gl.deleteShader(shader);return null;}return shader;};
 const vs=compile(gl.VERTEX_SHADER,vertex),fs=compile(gl.FRAGMENT_SHADER,fragment),program=gl.createProgram();
 if(!vs||!fs||!program){if(vs)gl.deleteShader(vs);if(fs)gl.deleteShader(fs);if(program)gl.deleteProgram(program);return null;}
 gl.attachShader(program,vs);gl.attachShader(program,fs);gl.linkProgram(program);gl.deleteShader(vs);gl.deleteShader(fs);
 if(!gl.getProgramParameter(program,gl.LINK_STATUS)){gl.deleteProgram(program);return null;}
 const buffer=gl.createBuffer();if(!buffer){gl.deleteProgram(program);return null;}
 gl.useProgram(program);gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,seeds,gl.STATIC_DRAW);
 const attribute=gl.getAttribLocation(program,'aSeed'),uniform=Object.fromEntries(['Time','Energy','Ratio','Size','Pointer','Velocity','Active','Color','Accent'].map(key=>[key,gl.getUniformLocation(program,'u'+key)]));
 let quality=1,samples=0,cost=0;
 return {draw(frame){if(gl.isContextLost())return false;const start=performance.now(),{width,height,phase,energy,pointer}=frame,color=colors(frame);
  gl.viewport(0,0,canvas.width,canvas.height);gl.clearColor(0,0,0,0);gl.clear(gl.COLOR_BUFFER_BIT);gl.useProgram(program);
  gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.enableVertexAttribArray(attribute);gl.vertexAttribPointer(attribute,4,gl.FLOAT,false,0,0);
  gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA);
  gl.uniform1f(uniform.Time,phase);gl.uniform1f(uniform.Energy,energy);gl.uniform1f(uniform.Ratio,canvas.width/width);
  gl.uniform2f(uniform.Size,width,height);gl.uniform2f(uniform.Pointer,pointer.x,pointer.y);gl.uniform2f(uniform.Velocity,pointer.vx||0,pointer.vy||0);gl.uniform1f(uniform.Active,pointer.active);
  gl.uniform3fv(uniform.Color,color.base);gl.uniform3fv(uniform.Accent,color.accent);
  gl.drawArrays(gl.POINTS,0,Math.round((width<500?9000:width<900?14500:20000)*quality));
  cost+=performance.now()-start;if(++samples===90){if(cost/samples>5)quality=Math.max(.45,quality*.75);cost=0;samples=0;}return true;
 },dispose(){gl.deleteBuffer(buffer);gl.deleteProgram(program);}};
}

/** Deterministic Canvas fallback uses the same folded field and hover mapping. */
export function drawFlowRibbon(context:CanvasRenderingContext2D,frame:WaveFrame){
 const {width,height,phase,energy,pointer}=frame,t=phase*.24,color=colors(frame),count=width<500?2400:4200;
 const base=color.base.map(v=>Math.round(v*255)),accent=color.accent.map(v=>Math.round(v*255)),paths=Array.from({length:8},()=>new Path2D());
 for(let i=0;i<count;i++){
  const offset=i*4,u=seeds[offset],v=seeds[offset+1],seed=seeds[offset+2],depth=seeds[offset+3],envelope=Math.sin(u*Math.PI);
  const fa=Math.exp(-(((u-.31)/.13)**2)),fb=Math.exp(-(((u-.70)/.105)**2));
  let cy=.62*Math.sin(u*5.15+t)+.27*Math.sin(u*12.4-t*.72)+.14*Math.cos(u*23+t*.37)+.16*Math.sin(u*7.1+1.7)+.10*Math.cos(u*13.7-2.2);
  cy+=fa*.48*Math.cos((u-.31)*14-t*.18)-fb*.55*Math.cos((u-.70)*17+t*.24);
  const layer=Math.floor(seed%3)-1;cy+=layer*.13*Math.sin(u*9.2+t*.44);
  const span=(Math.abs(.56*(.48+.52*Math.sin(u*8+1.2)*Math.sin(u*3.7-2)))+.10)*(.62+(.5+.5*Math.sin(u*4.3+2.4))*.56)*(1.48+energy*.44),angle=u*13.5+Math.sin(u*7.2+t)*1.15+energy*.24+layer*.2;
  const yy=v*span*Math.cos(angle)+Math.sin(seed*31+phase*1.3)*.012,zz=v*span*Math.sin(angle)+Math.cos(seed*19+phase*.9)*.012;
  let x=.018+u*.964+envelope*(fa*.026*Math.sin((u-.31)*18+t*.42)+fb*.020*Math.sin((u-.70)*24-t*.36)),y=.57+(cy+yy)*.19;
  const dx=(x-pointer.x)*width,dy=(y-pointer.y)*height,radius=Math.max(65,Math.min(145,height*.42)),influence=Math.exp(-(dx*dx+dy*dy)/(radius*radius))*pointer.active,turn=influence*Math.min(1.8,Math.hypot(pointer.vx||0,pointer.vy||0))*1.05;
  y+=(yy*Math.cos(turn)-zz*Math.sin(turn)-yy)*.19+influence*(pointer.y-y)*.17+influence*(pointer.vy||0)*.025;x+=influence*(pointer.vx||0)*.012*envelope;
  const radiusDot=.42+depth*.42,path=paths[Math.min(7,Math.floor(depth*8))];path.moveTo(x*width+radiusDot,y*height);path.arc(x*width,y*height,radiusDot,0,Math.PI*2);
 }
 for(let index=0;index<8;index++){context.fillStyle=`rgba(${(index===7?accent:base).join(',')},${.32+(index+.5)/8*.50})`;context.fill(paths[index]);}
}

