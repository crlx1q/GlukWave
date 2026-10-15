import test from 'node:test';
import assert from 'node:assert/strict';
import {progressPosition,progressAdvancing} from '../src/progress-clock.ts';
const base={position:10,duration:240,playing:true,at:1000,horizon:2000};
test('fractional visual frames follow physical elapsed time at 1, 1.5 and 2 speed',()=>{
 for(const rate of [1,1.5,2])for(const elapsed of [16,33,50,100,500])assert.equal(progressPosition({...base,rate},1000+elapsed),10+elapsed/1000*rate);
});
test('pause, buffering/pending state, backward/forward seek and scope replace the anchor immediately',()=>{
 assert.equal(progressPosition({...base,playing:false},1800),10);
 for(const position of [2,180,0])assert.equal(progressPosition({...base,position,at:1800},1800),position);
 assert.equal(progressPosition({...base,position:0,duration:99,playing:false,at:2000},2900),0);
});
test('stale mirrored/mini samples stop at a bounded horizon and never pass track end',()=>{
 assert.equal(progressPosition(base,900000),12);assert.equal(progressAdvancing(base,3001),false);
 assert.equal(progressPosition({...base,position:239.9},1800),240);assert.equal(progressAdvancing({...base,position:239.9},1800),false);
 assert.equal(progressPosition(base,0),10);assert.equal(progressPosition({...base,position:NaN},1000),0);
});
