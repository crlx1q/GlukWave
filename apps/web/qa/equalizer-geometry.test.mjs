import test from 'node:test';
import assert from 'node:assert/strict';
import {equalizerPath,EQ_EDITOR_GAIN_SCALE} from '../src/equalizer-geometry.ts';
const bands=[0,0,-12,12,0,7,-5,0,0,0];
test('Equalizer rounding preserves every exact band handle and uses a deliberate angular zero-radius path',()=>{
 const sharp=equalizerPath(bands,0),soft=equalizerPath(bands,48);
 assert(!sharp.includes('C'));assert(soft.includes('C'));
 const commands=soft.match(/[MC][^MC]+/g);
 assert.equal(commands.length,10);
 for(let i=0;i<commands.length;i++){
  const coords=commands[i].slice(1).trim().split(/[ ,]+/).map(Number);
  assert.equal(coords.at(-2),15+i*30);assert(Math.abs(coords.at(-1)-(72-bands[i]*EQ_EDITOR_GAIN_SCALE))<.001);
 }
});
test('Every rounded segment remains between its two gains, including rapid alternating extremes',()=>{
 for(const radius of [1,8,24,48])for(const values of [bands,[-12,12,-12,12,-12,12,-12,12,-12,12],[12,12,12,12,12,12,12,12,12,12]]){
  const commands=equalizerPath(values,radius).match(/[MC][^MC]+/g);let y=Number(commands[0].split(',')[1]);
  for(const command of commands.slice(1)){
   const coords=command.slice(1).trim().split(/[ ,]+/).map(Number),end=coords[5];
   for(let i=0;i<=100;i++){const t=i/100,point=(1-t)**3*y+3*(1-t)**2*t*coords[1]+3*(1-t)*t*t*coords[3]+t**3*end;assert(point>=Math.min(y,end)-.001&&point<=Math.max(y,end)+.001);}
   y=end;
  }
 }
});
test('Rounding follows the actual setting, flattens derivative at peaks and clamps invalid gain extremes',()=>{
 assert.notEqual(equalizerPath(bands,8),equalizerPath(bands,24));assert.equal(equalizerPath(bands,48),equalizerPath(bands,24));
 const commands=equalizerPath(bands,24).match(/[MC][^MC]+/g),peak=commands[3].slice(1).split(/[ ,]+/).map(Number),next=commands[4].slice(1).split(/[ ,]+/).map(Number);
 assert(Math.abs(peak[3]-peak[5])<.001);assert(Math.abs(next[1]-peak[5])<.001);
 const extremes=equalizerPath([99,-99],0);assert(extremes.startsWith('M15,4.'));assert(extremes.includes('L45,139.'));assert.equal(equalizerPath([],24),'');
});
