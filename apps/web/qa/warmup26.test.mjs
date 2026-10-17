import test from 'node:test';
import assert from 'node:assert/strict';
import {PlaybackWarmup} from '../src/playback-warmup.ts';
const descriptor={kind:'audio',url:'/api/stream-audio/own',offline:true};
test('obsolete preparation cancels I/O while a foreground selection adopts the same job',async()=>{
 const warmup=new PlaybackWarmup();warmup.reset('first');let sourceSignal,finish,calls=0;
 const cancellation=new AbortController();
 const pending=warmup.prepare('song',signal=>{sourceSignal=signal;calls++;return new Promise(resolve=>finish=resolve);},cancellation.signal);
 const selected=warmup.get('song',()=>assert.fail('foreground must share prepared work'));
 cancellation.abort();assert.equal(sourceSignal.aborted,false);finish(descriptor);
 assert.deepEqual(await pending,descriptor);assert.deepEqual(await selected,descriptor);assert.equal(calls,1);
 const old=new AbortController();let obsolete;
 const speculative=warmup.prepare('next',signal=>{obsolete=signal;return new Promise((_,reject)=>signal.addEventListener('abort',()=>reject(new DOMException('Aborted','AbortError'))));},old.signal);
 const rejected=assert.rejects(speculative,{name:'AbortError'});old.abort();await rejected;assert.equal(obsolete.aborted,true);
});
test('changing account cancels all prepared requests and cannot populate the new account',async()=>{
 const warmup=new PlaybackWarmup();warmup.reset('one');let signal,finish;
 const pending=warmup.prepare('same',value=>{signal=value;return new Promise(resolve=>finish=resolve);},new AbortController().signal);
 warmup.reset('two');assert.equal(signal.aborted,true);finish(descriptor);await pending;
 let calls=0;await warmup.get('same',async()=>{calls++;return descriptor;});assert.equal(calls,1);
});
