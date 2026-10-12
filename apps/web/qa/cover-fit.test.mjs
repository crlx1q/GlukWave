import test from 'node:test';import assert from 'node:assert/strict';
import {coverBounds,fitCover} from '../src/cover-fit.ts';
test('Complete perspective composition fits short/wide/phone stages through supported rotations',()=>{
 for(const [width,height]of [[378,156],[248,176],[320,312],[390,365],[160,130]])for(const x of [-75,-45,-9,0,45,75])for(const y of [-180,-90,-18,0,45,90,180,540]){
  const size=fitCover(width,height,true,x,y);assert(size>20&&size<=Math.min(340,width-24,height-24));
  for(const dx of [-2,0,2])for(const dy of [-5,0,5]){const b=coverBounds(size,x+dx,y+dy);assert(b.top>=-height/2+16-.01);assert(b.bottom<=height/2-12+.01);assert(b.left>=-width/2+12-.01);assert(b.right<=width/2-12+.01);}
 }
});
test('Flat art uses available square without distortion and detached/zero-sized stages stay safe',()=>{
 assert.equal(fitCover(378,156,false,-9,-18),132);assert.equal(fitCover(320,365,false,0,0),296);assert.equal(fitCover(390,500,false,0,0),340);assert.equal(fitCover(0,0,true,0,0),0);
});
