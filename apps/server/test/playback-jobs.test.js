import test from 'node:test';
import assert from 'node:assert/strict';
import {createPlaybackJobs} from '../src/playback-jobs.js';
import {createExtractorRuntime} from '../src/extractors/runtime.js';
import {config} from '../src/config.js';
import {decodedDeviceName} from '../src/auth.js';

test('slow playback returns pending, coalesces polls and isolates sessions',async()=>{
 const jobs=createPlaybackJobs({waitMs:5,limit:2});let finish,calls=0;
 const operation=()=>{calls++;return new Promise(resolve=>finish=resolve);};
 const keep=setTimeout(()=>{},1000);
 try{
  assert.equal((await jobs.wait('session-a:track',operation)).pending,true);
  assert.equal((await jobs.wait('session-a:track',operation)).pending,true);assert.equal(calls,1);
  assert.equal((await jobs.wait('session-b:track',async()=>({url:'/b'}))).playback.url,'/b');
  await assert.rejects(jobs.wait('session-c:track',operation),{code:'EXTRACTOR_BUSY'});
  finish({kind:'audio',url:'/a'});assert.equal((await jobs.wait('session-a:track',operation)).playback.url,'/a');assert.equal(calls,1);
 }finally{clearTimeout(keep);jobs.close();}
 await assert.rejects(jobs.wait('new',operation),{code:'EXTRACTOR_BUSY'});
});
test('extractor queue expires waiting requests without starting another child or losing its slot',async()=>{
 let finish,calls=0;const runtime=createExtractorRuntime({...config,env:'test',extractors:{enabled:true,concurrency:1,queueTimeout:15}},{run:async()=>{calls++;return new Promise(resolve=>finish=resolve);}});
 const keep=setTimeout(()=>{},1000);
 try{
  const running=runtime.execute('youtube',{});await new Promise(resolve=>setImmediate(resolve));
  await assert.rejects(runtime.execute('youtube',{}),{code:'EXTRACTOR_BUSY'});assert.equal(calls,1);assert.equal(runtime.stats().queued,0);assert.equal(runtime.stats().active,1);
  finish({ok:true});await running;assert.equal(runtime.stats().active,0);assert.equal(runtime.stats().failed,1);
 }finally{clearTimeout(keep);await runtime.close();}
});
test('native device names decode safely for account sessions',()=>{
 assert.equal(decodedDeviceName(encodeURIComponent('GlukWave · Android — Алишер')),'GlukWave · Android — Алишер');
 assert.equal(decodedDeviceName('%E0%A4%A'),'%E0%A4%A');assert.equal(decodedDeviceName('phone%0Ahidden'),'phonehidden');assert.equal(decodedDeviceName('a'.repeat(300)).length,150);
});
