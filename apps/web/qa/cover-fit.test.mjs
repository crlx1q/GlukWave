import test from 'node:test';import assert from 'node:assert/strict';
import {coverBounds,coverEnvelopeHeight,coverSceneHeight,fitCover} from '../src/cover-fit.ts';
test('Artwork is stable through complete turns and every face fits the fixed viewport envelope',()=>{
 for(const [width,height]of [[378,156],[248,176],[320,312],[390,365],[160,130]])for(const x of [-9,-6,0,6,9])for(const y of [-180,-90,-18,0,45,90,180,540]){
  const size=fitCover(width,height,true,x,y);assert(size>20&&size<=Math.min(340,width-24));assert.equal(size,fitCover(width,height,true,0,0));assert.equal(size,fitCover(width,height,true,65,190));
  const sceneHeight=coverEnvelopeHeight(size);assert(sceneHeight<=height);
  for(const dx of [0])for(const dy of [-5,0,5]){const b=coverBounds(size,x+dx,y+dy);assert(b.bottom-b.top<=sceneHeight-16);assert(b.right-b.left<=width-20);}
 }
});
test('Flat art uses available square without distortion and detached/zero-sized stages stay safe',()=>{
 assert.equal(fitCover(378,156,false,-9,-18),120);assert.equal(fitCover(320,365,false,0,0),296);assert.equal(fitCover(390,500,false,0,0),340);assert.equal(fitCover(0,0,true,0,0),0);
});

test('Ordinary cover composition reserves its actual headroom rather than worst-case vertical space',()=>{const size=305,bounds=coverBounds(size,-9,-18),height=coverSceneHeight(size,bounds);assert(height>=bounds.bottom-bounds.top+60);assert(height<400);assert.equal(coverSceneHeight(size),size+36);});
