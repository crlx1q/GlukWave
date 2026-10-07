// Adapted from Originkit Halftone Bloom, fetched by the authorised Originkit CLI.
// Original two-pass halftone finish is retained; GlukWave supplies the shared flowing field.
import { BLOOM, bloomFieldGLSL, type WavePointer } from "../wave-math";

const FINISH_SRC = `#version 300 es
precision highp float;
uniform sampler2D uField;
uniform vec2 uRes;
uniform float uTime;
uniform vec3 uBg;
uniform float uPaper;
uniform vec2 uMouse;
uniform float uOn;
uniform float uReach;
uniform float uCell;
uniform float uPR;
out vec4 o;

const float PI = 3.14159265359;
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
const float TURN = ${BLOOM.turn.toFixed(4)};
const float SWELL = ${BLOOM.swell.toFixed(4)};
const float REST = ${BLOOM.rest.toFixed(4)};
const float CAP = ${BLOOM.cap.toFixed(4)};

float ign(vec2 p, float f) { p += 5.588238 * mod(f, 64.0); return fract(52.9829189 * fract(0.06711056 * p.x + 0.00583715 * p.y)); }

vec3 scene(vec2 uv) { return max(texture(uField, clamp(uv, 0.0, 1.0)).rgb, 0.0); }

void main() {
  vec2 frag = gl_FragCoord.xy;
  vec2 uv = frag / uRes;

  mat2 turn = mat2(cos(TURN), -sin(TURN), sin(TURN), cos(TURN));
  vec2 rp = turn * frag;
  vec2 c = (floor(rp / uCell) + 0.5) * uCell;
  vec2 src = transpose(turn) * c;
  vec3 soft = scene(uv);
  vec3 ink = scene(src / uRes);
  float lvl = clamp(texture(uField,clamp(src/uRes,0.0,1.0)).a,0.0,1.0);
  float radius = uCell * sqrt(pow(lvl, 0.9) / PI);
  float presence = smoothstep(0.03, 0.16, lvl) * REST;

  if (uOn > 0.0) {
    vec2 d = (src - uMouse) / uReach;
    float w = uOn * exp(-dot(d, d));
    if (w > 1e-4) {
      radius *= 1.0 + SWELL * w;
      presence = mix(presence, 1.0, min(w, 1.0));
    }
  }
  radius = min(radius, uCell * CAP);
  float aa = 0.7 * uPR;
  float dm = 1.0 - smoothstep(radius - aa, radius + aa, length(rp - c));
  vec3 dots = ink * min(0.8 / max(lvl, 1e-3), 2.2) * dm;
  vec3 L = mix(soft, dots, presence);

  vec3 dark = uBg + L * (1.0 - uBg);
  float strength = clamp(max(L.r, max(L.g, L.b)), 0.0, 1.0);
  vec3 paper = uBg * (1.0 - strength) + L * 0.96;
  vec3 col = mix(dark, paper, uPaper);
  col += (ign(frag, floor(uTime * 24.0)) - 0.5) / 255.0;
  o = vec4(clamp(col, 0.0, 1.0), 1.0);
}
`

const VERT_SRC=`#version 300 es
const vec2 P[3]=vec2[3](vec2(-1.,-1.),vec2(3.,-1.),vec2(-1.,3.));
void main(){gl_Position=vec4(P[gl_VertexID],0.,1.);}`;
const FIELD_SRC=`#version 300 es
precision highp float;
uniform vec2 uRes;
uniform float uTime;
uniform float uEnergy;
uniform vec3 uC1;
uniform vec3 uC2;
out vec4 o;
${bloomFieldGLSL}
void main(){vec2 p=gl_FragCoord.xy/uRes;p.y=1.-p.y;
  float level=waveField(p,uTime,uEnergy);
  vec3 color=mix(uC1,uC2,.5+.5*sin(p.x*6.+uTime*.23));
  o=vec4(color*level,level);
}`;

export type WaveFrame={width:number;height:number;phase:number;energy:number;pointer:WavePointer;tint:string;background:string};
export type WaveRenderer={draw:(frame:WaveFrame)=>boolean;dispose:()=>void};
export const rgb=(hex:string)=>[1,3,5].map(index=>parseInt(hex.slice(index,index+2),16)/255);

function link(gl:WebGL2RenderingContext,fragment:string) {
  const shaders:WebGLShader[]=[];
  for(const [type,source]of [[gl.VERTEX_SHADER,VERT_SRC],[gl.FRAGMENT_SHADER,fragment]] as const){const shader=gl.createShader(type);if(!shader)return null;gl.shaderSource(shader,source);gl.compileShader(shader);shaders.push(shader);if(!gl.getShaderParameter(shader,gl.COMPILE_STATUS)){shaders.forEach(item=>gl.deleteShader(item));return null;}}
  const program=gl.createProgram();if(!program){shaders.forEach(item=>gl.deleteShader(item));return null;}
  shaders.forEach(shader=>gl.attachShader(program,shader));gl.linkProgram(program);shaders.forEach(shader=>gl.deleteShader(shader));
  if(!gl.getProgramParameter(program,gl.LINK_STATUS)){gl.deleteProgram(program);return null;}return program;
}

/** Originkit's two-pass field/finish pipeline, bounded to a half-resolution field.
 * The React host owns frame scheduling, reduced motion, visibility and dimensions.
 */
export function createHalftoneBloom(canvas:HTMLCanvasElement):WaveRenderer|null {
  const gl=canvas.getContext('webgl2',{antialias:false,alpha:false,depth:false,stencil:false,powerPreference:'low-power'});if(!gl)return null;
  const field=link(gl,FIELD_SRC),finish=link(gl,FINISH_SRC);
  if(!field||!finish){if(field)gl.deleteProgram(field);if(finish)gl.deleteProgram(finish);return null;}
  const locations=(program:WebGLProgram,names:string[])=>Object.fromEntries(names.map(name=>[name,gl.getUniformLocation(program,name)]));
  const uf=locations(field,['uRes','uTime','uEnergy','uC1','uC2']),un=locations(finish,['uField','uRes','uTime','uBg','uPaper','uMouse','uOn','uReach','uCell','uPR']);
  const vao=gl.createVertexArray(),fbo=gl.createFramebuffer(),texture=gl.createTexture();let tw=0,th=0;
  gl.bindVertexArray(vao);gl.bindTexture(gl.TEXTURE_2D,texture);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
  return {
    draw(frame){
      if(gl.isContextLost())return false;const {width,height,phase,energy,pointer,tint,background}=frame;if(!width||!height)return true;
      const bw=canvas.width,bh=canvas.height,nw=Math.max(1,Math.round(bw/2)),nh=Math.max(1,Math.round(bh/2));
      gl.bindTexture(gl.TEXTURE_2D,texture);
      if(nw!==tw||nh!==th){tw=nw;th=nh;gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA8,tw,th,0,gl.RGBA,gl.UNSIGNED_BYTE,null);gl.bindFramebuffer(gl.FRAMEBUFFER,fbo);gl.framebufferTexture2D(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,texture,0);if(gl.checkFramebufferStatus(gl.FRAMEBUFFER)!==gl.FRAMEBUFFER_COMPLETE)return false;}
      const c1=rgb(tint).map(value=>Math.min(1,value*.55+.4)),c2=rgb(tint).map((value,index)=>Math.min(1,value*.7+[.24,.3,.34][index])),bg=rgb(background);
      gl.bindFramebuffer(gl.FRAMEBUFFER,fbo);gl.viewport(0,0,tw,th);gl.useProgram(field);gl.uniform2f(uf.uRes,tw,th);gl.uniform1f(uf.uTime,phase);gl.uniform1f(uf.uEnergy,energy);gl.uniform3fv(uf.uC1,c1);gl.uniform3fv(uf.uC2,c2);gl.drawArrays(gl.TRIANGLES,0,3);
      const pr=bw/width;gl.bindFramebuffer(gl.FRAMEBUFFER,null);gl.viewport(0,0,bw,bh);gl.useProgram(finish);gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,texture);gl.uniform1i(un.uField,0);gl.uniform2f(un.uRes,bw,bh);gl.uniform1f(un.uTime,phase);gl.uniform3fv(un.uBg,bg);gl.uniform1f(un.uPaper,0);gl.uniform2f(un.uMouse,pointer.x*bw,(1-pointer.y)*bh);gl.uniform1f(un.uOn,pointer.active);gl.uniform1f(un.uReach,height*BLOOM.reach*pr);gl.uniform1f(un.uCell,BLOOM.cell*pr);gl.uniform1f(un.uPR,pr);gl.drawArrays(gl.TRIANGLES,0,3);return true;
    },
    dispose(){gl.deleteTexture(texture);gl.deleteFramebuffer(fbo);gl.deleteVertexArray(vao);gl.deleteProgram(field);gl.deleteProgram(finish);}
  };
}
