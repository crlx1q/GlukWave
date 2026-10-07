import { vertexSource, fragmentSource } from './wave-shaders';
import { rgb, type WaveRenderer } from './vendor/halftone-bloom';

/** Preserve the original GlukWave lit, twisted ribbon with a smaller mesh. */
export function createSilkWave(canvas:HTMLCanvasElement):WaveRenderer|null {
  const gl=canvas.getContext('webgl',{alpha:true,antialias:true,premultipliedAlpha:false,powerPreference:'low-power'});if(!gl)return null;
  const shader=(type:number,source:string)=>{const value=gl.createShader(type);if(!value)return null;gl.shaderSource(value,source);gl.compileShader(value);if(!gl.getShaderParameter(value,gl.COMPILE_STATUS)){gl.deleteShader(value);return null;}return value;};
  const fragment=fragmentSource.replace('uniform float u_hue;','uniform float u_hue;uniform vec3 u_accent;').replace('color*=.47+diff*.84;','color=mix(color,u_accent,.28);color*=.47+diff*.84;');
  const vertex=shader(gl.VERTEX_SHADER,vertexSource),pixel=shader(gl.FRAGMENT_SHADER,fragment),program=gl.createProgram();
  if(!vertex||!pixel||!program){if(vertex)gl.deleteShader(vertex);if(pixel)gl.deleteShader(pixel);if(program)gl.deleteProgram(program);return null;}
  gl.attachShader(program,vertex);gl.attachShader(program,pixel);gl.linkProgram(program);gl.deleteShader(vertex);gl.deleteShader(pixel);
  if(!gl.getProgramParameter(program,gl.LINK_STATUS)){gl.deleteProgram(program);return null;}
  const uv:number[]=[],N=120,M=24;for(let i=0;i<N;i++)for(let j=0;j<M;j++){const u=i/N*Math.PI*2,un=(i+1)/N*Math.PI*2,v=j/M*2-1,vn=(j+1)/M*2-1;uv.push(u,v,un,v,un,vn,u,v,un,vn,u,vn);}
  const buffer=gl.createBuffer();gl.useProgram(program);gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(uv),gl.STATIC_DRAW);const attribute=gl.getAttribLocation(program,'a_uv');gl.enableVertexAttribArray(attribute);gl.vertexAttribPointer(attribute,2,gl.FLOAT,false,0,0);
  const uniforms=Object.fromEntries(['time','pointer','res','scale','hue','accent'].map(name=>[name,gl.getUniformLocation(program,'u_'+name)]));gl.enable(gl.DEPTH_TEST);gl.clearColor(0,0,0,0);
  return {
    draw({width,height,phase,energy,pointer,tint}){if(gl.isContextLost())return false;gl.viewport(0,0,canvas.width,canvas.height);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);gl.useProgram(program);gl.uniform1f(uniforms.time,phase);gl.uniform2f(uniforms.pointer,(pointer.x-.5)*pointer.active,(pointer.y-.5)*pointer.active);gl.uniform2f(uniforms.res,width,height);gl.uniform1f(uniforms.scale,Math.min(width*.34,height*.34)*(1+energy*.12));gl.uniform1f(uniforms.hue,0);gl.uniform3fv(uniforms.accent,rgb(tint));gl.drawArrays(gl.TRIANGLES,0,uv.length/2);return true;},
    dispose(){gl.deleteBuffer(buffer);gl.deleteProgram(program);}
  };
}
