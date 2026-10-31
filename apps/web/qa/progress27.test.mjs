import test from 'node:test';
import assert from 'node:assert/strict';
import {LocalMediaClock,PacketProgressClock,REMOTE_PROGRESS_HORIZON,progressPosition} from '../src/progress-clock.ts';
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
 assert.equal(read(0,2200,true,'two').playing,false);assert(read(0,2220,true,'two').position<=1.5);
 assert.equal(read(4,2230,true,'two').position,4);
});

test('one-second coarse decoder ticks keep every visual frame advancing, including detached500ms samples',()=>{for(const rate of [1,1.5,2]){const clock=new LocalMediaClock(),values=[];for(let at=0;at<3600;at+=16)values.push(clock.read({position:Math.floor(at/1000)*rate,duration:180,playing:true,rate,at},'one-second').position);const deltas=values.slice(1).map((v,i)=>v-values[i]);assert(deltas.every(v=>v>0&&v<.06),JSON.stringify(deltas.filter(v=>v<=0||v>=.06)));assert(Math.abs(values.at(-1)-3.584*rate)<.15);const mini=clock.read({position:3*rate,duration:180,playing:true,rate,at:3600},'one-second');assert(mini.horizon>500);assert.equal(clock.read({...mini,position:3.2,playing:false,at:3700},'one-second').position,3.2);}});

test('first coarse tick with an unknown200ms phase does not look like a seek; explicit small seek resets',()=>{for(const rate of [1,1.5,2]){const clock=new LocalMediaClock(),rows=[];for(let at=0;at<=1800;at+=16)rows.push(clock.read({position:(5+Math.floor((at+800)/1000))*rate,duration:180,playing:true,rate,at},'offset').position);assert(rows.slice(1).every((p,i)=>p>=rows[i]&&p-rows[i]<.05));clock.reset();assert.equal(clock.read({position:6.25,duration:180,playing:true,rate,at:1810},'offset').position,6.25);}});


test('detached packet corrections stay forward; explicit small seeks, pause and output changes reset',()=>{
 const clock=new PacketProgressClock();let packet={position:10,duration:180,playing:true,at:0,horizon:1500},previous=10;
 for(let now=0;now<=2200;now+=16){if(now>=packet.at+500)packet={...packet,at:now,position:10+now/1000-.12};const value=clock.read(packet,'output:0',now).position;assert(value>=previous);assert(value-previous<.05);previous=value;}
 const seek={...packet,position:previous-.02,at:2220};assert.equal(clock.read(seek,'output:1',2220).position,seek.position);
 assert.equal(clock.read({...seek,position:8,playing:false,at:2230},'output:1',2230).position,8);
 assert.equal(clock.read({...seek,position:20,at:2240},'other-output',2240).position,20);
 const stale=clock.read({...seek,position:20,at:2240,horizon:100},'other-output',2400);assert.equal(stale.playing,false);assert.equal(clock.read({...seek,position:20,at:2240,horizon:100},'other-output',2500).position,stale.position);
});


test('remote clock spans a10s server checkpoint but stays bounded and stops immediately on disconnect/pause',()=>{
 const sample={position:10,duration:180,playing:true,at:0,horizon:REMOTE_PROGRESS_HORIZON};
 for(const at of [16,5000,9000,10000,11000])assert.equal(progressPosition(sample,at),10+at/1000);
 assert.equal(progressPosition(sample,13000),22);
 assert.equal(progressPosition({...sample,position:18.2,playing:false,at:8200},9000),18.2);
});


test('directory2s checkpoints absorb ordinary alternating corrections for12s with two visible consumers',()=>{
 const clock=new PacketProgressClock();let packet={position:30,duration:180,playing:true,at:0,horizon:5000},last=30;
 for(let now=0;now<12000;now+=16){if(now-packet.at>=2000)packet={...packet,at:now,position:30+now/1000+(Math.floor(now/2000)%2?.12:-.12)};const value=clock.read(packet,'account/device/surface/track/0',now).position;assert(value>=last);assert(value-last<=.021);assert.equal(clock.read(packet,'account/device/surface/track/0',now).position,value);last=value;}
 const explicit={position:last-.02,duration:180,playing:false,at:12000};assert.equal(clock.read(explicit,'account/device/surface/track/1',12000).position,explicit.position);
 assert.equal(clock.read({...explicit,position:0},'account/device/surface/track/2',12010).position,0);
});
