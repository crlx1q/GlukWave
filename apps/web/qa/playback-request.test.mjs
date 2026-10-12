import test from 'node:test';
import assert from 'node:assert/strict';
import {playbackRequest,abortableDelay} from '../src/playback-request.ts';

test('pending playback polls one endpoint until ready, honoring bounded Retry-After',async()=>{
 const calls=[],waits=[],responses=[new Response('{}',{status:202,headers:{'Retry-After':'99'}}),new Response('{}',{status:202}),Response.json({playback:{kind:'audio',url:'/audio'}})];
 const response=await playbackRequest('/api/tracks/test/playback',{headers:{'X-GlukWave-Playback-Wait':'poll'}},async(url,init)=>{calls.push([url,init.headers]);return responses.shift();},async ms=>{waits.push(ms);});
 assert.equal((await response.json()).playback.url,'/audio');assert.equal(calls.length,3);assert(calls.every(([url])=>url==='/api/tracks/test/playback'));assert.deepEqual(waits,[4000,2000]);
});
test('edge timeout and transient network failures recover with bounded retries',async()=>{
 let calls=0;const waits=[];
 const response=await playbackRequest('/playback',{},async()=>{calls++;if(calls===1)throw new TypeError('Network disconnected');return calls===2?new Response('',{status:504}):Response.json({ok:true});},async ms=>waits.push(ms));
 assert.equal(response.status,200);assert.equal(calls,3);assert.deepEqual(waits,[600,1200]);
});
test('permanent access failures are returned without retry',async()=>{
 let calls=0;const response=await playbackRequest('/playback',{},async()=>{calls++;return new Response('',{status:401});});
 assert.equal(response.status,401);assert.equal(calls,1);
});
test('switching tracks cancels the polling wait without another network request',async()=>{
 const controller=new AbortController();let calls=0;
 const pending=playbackRequest('/playback',{signal:controller.signal},async()=>{calls++;queueMicrotask(()=>controller.abort());return new Response('{}',{status:202});});
 await assert.rejects(pending,{name:'AbortError'});assert.equal(calls,1);
 const wait=abortableDelay(60000,controller.signal);await assert.rejects(wait,{name:'AbortError'});
});
test('an unavailable server cannot create an endless retry loop',async()=>{
 let calls=0;const response=await playbackRequest('/playback',{},async()=>{calls++;return new Response('',{status:503});},async()=>{});
 assert.equal(response.status,503);assert.equal(calls,3);
});
