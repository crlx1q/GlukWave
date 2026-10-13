import test from 'node:test';
import assert from 'node:assert/strict';
import {actionRequest} from '../src/action-request.ts';
import {unavailableAudio} from '../src/playback-recovery.ts';
test('an action retains account, body and intent through preparation and an edge retry',async()=>{
 const requests=[],statuses=[202,504,202,201];
 const response=await actionRequest('/api/import',{method:'POST',headers:{'X-GlukWave-Account':'account-A'},body:JSON.stringify({requestId:'library-intent-20',destination:'likes'})},async(url,init)=>{
  requests.push({url,body:init.body,headers:new Headers(init.headers)});return Response.json({}, {status:statuses.shift()});
 },async()=>{});
 assert.equal(response.status,201);assert.equal(requests.length,4);
 assert(requests.every(r=>r.headers.get('X-GlukWave-Intent')==='library-intent-20'&&r.headers.get('X-GlukWave-Account')==='account-A'&&r.headers.get('X-GlukWave-Command-Wait')==='poll'));
 assert.equal(new Set(requests.map(r=>r.body)).size,1);
});
test('permanent action failure does not repeat a mutation; cancellation ends polling',async()=>{
 let calls=0;const response=await actionRequest('/api/action',{},async()=>{calls++;return Response.json({},{status:401});},async()=>{});
 assert.equal(response.status,401);assert.equal(calls,1);
 const controller=new AbortController();calls=0;
 await assert.rejects(actionRequest('/api/action',{signal:controller.signal},async()=>{calls++;controller.abort();return Response.json({},{status:202});},async()=>{}),{name:'AbortError'});
 assert.equal(calls,1);
});
test('auto skip recognizes unavailable audio without consuming auth, autoplay or networking failures',()=>{
 assert(unavailableAudio({code:'AUDIO_UNAVAILABLE'}));assert(unavailableAudio({code:'AUDIO_FORMAT_UNAVAILABLE'}));
 for(const code of ['AUTH_REQUIRED','AUDIO_EXPIRED','AUTOPLAY_BLOCKED','NETWORK','DEVICE_TIMEOUT'])assert.equal(unavailableAudio({code}),false);
});
