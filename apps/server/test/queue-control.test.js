import test from 'node:test';
import assert from 'node:assert/strict';
import {applyCommand,applyTrackEnded,commandSchema,initialState,stateSchema} from '../src/rooms.js';

test('queue edits retain the current audio and timeline, including when current track is removed',()=>{
 const old={...initialState(),trackId:'b',queue:['a','b','c'],playing:true,position:17,updatedAt:1000,revision:4};
 const next=applyCommand(old,{command:'queue',queue:['c','a']},1000);
 assert.equal(next.trackId,'b');assert.equal(next.position,17);assert(next.playing);assert.equal(next.revision,5);
 assert.deepEqual(next.queue,['c','a']);assert.deepEqual(old.queue,['a','b','c']);
 const ordered=applyCommand(next,{command:'queue',queue:['a','c','a']},1000);assert.deepEqual(ordered.queue,['a','c']);
 const ended=applyTrackEnded(ordered,{command:'ended',trackId:'b',expectedRevision:ordered.revision},30,14000);assert.equal(ended.trackId,'a');assert(ended.playing);assert.equal(ended.position,0);
 const repeatRemoved=applyTrackEnded({...ordered,repeat:'one'},{command:'ended',trackId:'b',expectedRevision:ordered.revision},30,14000);assert.equal(repeatRemoved.trackId,'a');assert(repeatRemoved.playing);
 const empty=applyTrackEnded({...ordered,queue:[],repeat:'one'},{command:'ended',trackId:'b',expectedRevision:ordered.revision},30,14000);assert.equal(empty.playing,false);
});
test('shared shuffle rearranges only remaining tracks and repeat is authoritative on completion',()=>{
 const old={...initialState(),trackId:'b',queue:['a','b','c','d','e'],playing:true,position:30,updatedAt:1000,revision:4};
 const shuffled=applyCommand(old,commandSchema.parse({command:'shuffle',enabled:true}),1000);
 assert(shuffled.shuffle);assert.deepEqual(shuffled.queue.slice(0,2),['a','b']);assert.deepEqual([...shuffled.queue].sort(),[...old.queue].sort());
 assert.equal(shuffled.position,30);assert.equal(shuffled.trackId,'b');
 const repeated=applyCommand(shuffled,{command:'repeat',repeat:'one'},1000);
 assert.equal(repeated.repeat,'one');
 const ended=applyTrackEnded(repeated,{command:'ended',trackId:'b',expectedRevision:repeated.revision,repeat:'off'},30,1000);
 assert.equal(ended.trackId,'b');assert.equal(ended.position,0);
 assert.deepEqual(applyTrackEnded(ended,{command:'ended',trackId:'b',expectedRevision:repeated.revision},30,1000),ended);
 assert(stateSchema.safeParse({...ended}).success);
 assert.throws(()=>applyCommand(old,{command:'shuffle'},1000));
 assert.throws(()=>applyCommand(old,{command:'repeat'},1000));
 assert.throws(()=>applyCommand(old,{command:'queue'},1000));
});
