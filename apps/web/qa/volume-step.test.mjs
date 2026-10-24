import test from 'node:test';
import assert from 'node:assert/strict';
import {wheelVolume} from '../src/volume.ts';
test('wheel uses next five-percent stop from fine values, clamps edges and ignores horizontal ticks',()=>{
 assert.deepEqual(Array.from({length:6},(_,i)=>wheelVolume(i*.05,-120)),[.05,.1,.15,.2,.25,.3]);
 assert.equal(wheelVolume(.37,-120),.4);assert.equal(wheelVolume(.37,120),.35);
 assert.equal(wheelVolume(1,-120),1);assert.equal(wheelVolume(0,120),0);assert.equal(wheelVolume(.37,0),.37);
});
