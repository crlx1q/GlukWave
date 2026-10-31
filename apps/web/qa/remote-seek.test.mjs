import test from 'node:test';
import assert from 'node:assert/strict';
import {deviceSeekStatus,deviceSeekSample} from '../src/remote-seek.ts';
import {progressPosition} from '../src/progress-clock.ts';
const intent={position:84.636,revision:1,scope:'account/device/surface/track',sourceAt:1000,at:0,deadline:8000,playing:false};
const snapshot={position:84.736,duration:180,playing:false,updatedAt:1000,online:true,at:0,horizon:5000};
test('paused0.1s seek survives ACK and stale immediate GET until a newer matching output packet',()=>{
 assert.equal(deviceSeekStatus(intent,intent.scope,snapshot,100),'pending');
 const acked={...intent,ackAt:150};
 for(const now of [160,280,800,1500]){assert.equal(deviceSeekStatus(acked,intent.scope,{...snapshot,at:now},now),'pending');assert.equal(progressPosition(deviceSeekSample(acked,180),now),84.636);}
 assert.equal(deviceSeekStatus(acked,intent.scope,{...snapshot,updatedAt:1100,at:280},280),'pending','newer timestamp alone does not confirm the old target');
 assert.equal(deviceSeekStatus(acked,intent.scope,{...snapshot,position:84.636,updatedAt:2000,at:1502},1502),'confirmed');
 assert.equal(deviceSeekStatus(acked,intent.scope,{...snapshot,position:84.636,updatedAt:1000,at:1502},1502),'pending','target alone cannot confirm an older packet');
});
test('playing seek projects one intent while dispatch and heartbeat lag, then confirms the new target interval',()=>{
 const seek={...intent,position:0,playing:true},old={...snapshot,position:60,playing:true};
 assert.equal(deviceSeekStatus({...seek,ackAt:100},seek.scope,{...old,updatedAt:1100,at:280},280),'pending');
 assert.equal(progressPosition(deviceSeekSample(seek,180),1500),1.5);
 assert.equal(deviceSeekStatus({...seek,ackAt:100},seek.scope,{...old,position:1.41,updatedAt:2000,at:1500},1500),'confirmed');
 assert.equal(deviceSeekStatus(seek,seek.scope,{...old,position:1.41,updatedAt:2000,at:1500},1500),'pending','packet cannot confirm before dispatch ACK');
});
test('seek presentation is bounded and releases on account, output, track, pause, loading or offline changes',()=>{
 const acked={...intent,ackAt:100};assert.equal(deviceSeekStatus(acked,intent.scope,snapshot,8000),'cancelled');
 for(const scope of ['other-account/device/surface/track','account/other-output/surface/track','account/device/surface/next-track'])assert.equal(deviceSeekStatus(acked,scope,snapshot,200),'cancelled');
 for(const change of [{online:false},{loading:true},{playing:true}])assert.equal(deviceSeekStatus(acked,intent.scope,{...snapshot,...change},200),'cancelled');
});
