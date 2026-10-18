import test from 'node:test';
import assert from 'node:assert/strict';
import {LocalMediaClock} from '../src/progress-clock.ts';
test('a 100ms quantized media source paints fractional forward frames rather than repeated steps',()=>{
 const clock=new LocalMediaClock(),positions=[];
 for(let at=0;at<1200;at+=16){positions.push(clock.read({position:Math.floor(at/100)/10,duration:180,playing:true,at},'track').position);}
 const deltas=positions.slice(1).map((value,index)=>value-positions[index]);
 assert(deltas.every(value=>value>0&&value<.05));
 assert(Math.abs(positions.at(-1)-1.184)<.12);
});
test('pause, seek, source change and stale media do not pretend playback is advancing',()=>{
 const clock=new LocalMediaClock();
 const read=(position,at,playing=true,scope='one')=>clock.read({position,duration:180,playing,at},scope);
 read(10,0);read(10,100);assert.equal(read(60,110).position,60);
 assert.equal(read(60,120,false).position,60);assert.equal(read(60,500,false).position,60);
 assert.equal(read(0,510,true,'two').position,0);read(0,600,true,'two');
 assert.equal(read(0,1200,true,'two').playing,false);assert(read(0,1220,true,'two').position<=.25);
 assert.equal(read(4,1230,true,'two').position,4);
});
