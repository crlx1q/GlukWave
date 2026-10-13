import test from 'node:test';
import assert from 'node:assert/strict';
import {AudioStreamLoader} from '../src/audio-stream.ts';

class FakeHls{
 static Events={MEDIA_ATTACHED:'attached',MANIFEST_PARSED:'parsed',ERROR:'error'};
 static ErrorTypes={NETWORK_ERROR:'network',MEDIA_ERROR:'media'};
 static instances=[];static isSupported(){return true;}
 constructor(options){this.options=options;this.events=new Map();this.destroyed=0;this.retries=0;this.recoveries=0;FakeHls.instances.push(this);}
 on(event,handler){this.events.set(event,handler);}
 emit(event,data={}){this.events.get(event)?.(event,data);}
 attachMedia(audio){this.audio=audio;this.emit('attached');}
 loadSource(url){this.url=url;}
 startLoad(){this.retries++;}
 recoverMediaError(){this.recoveries++;}
 destroy(){this.destroyed++;}
}
const element=()=>({src:'old-source',error:null,loads:0,removeAttribute(name){if(name==='src')this.src='';},load(){this.loads++;},canPlayType(){return 'probably';}});
const flush=()=>new Promise(resolve=>setImmediate(resolve));
const fixture=()=>({loader:new AudioStreamLoader(async()=>({default:FakeHls})),audio:element(),signal:new AbortController()});
test('progressive track replacement avoids an empty source and load reset between queue items',async()=>{
 const {loader,audio,signal}=fixture();await loader.attach(audio,'/next.wav',undefined,signal.signal,()=>{});assert.equal(audio.src,'/next.wav');assert.equal(audio.loads,0);signal.abort();assert.equal(audio.src,'');
});

test('MSE HLS owns a clean audio element even when native HLS is advertised',async()=>{
 const {loader,audio,signal}=fixture();let failures=0;
 const pending=loader.attach(audio,'/stream','hls',signal.signal,()=>failures++);await flush();const hls=FakeHls.instances.at(-1);
 assert.equal(audio.src,'');assert.equal(hls.url,'/stream');assert.equal(loader.handlesMediaErrors,true);
 hls.emit('parsed');await pending;signal.abort();assert.equal(hls.destroyed,1);assert.equal(loader.handlesMediaErrors,false);assert.equal(failures,0);
});
test('late events from an old track cannot stop the new stream or send errors',async()=>{
 const {loader,audio,signal}=fixture();let failures=0;
 const first=loader.attach(audio,'/first','hls',signal.signal,()=>failures++);await flush();const old=FakeHls.instances.at(-1);
 const nextSignal=new AbortController(),second=loader.attach(audio,'/second','hls',nextSignal.signal,()=>failures++);
 await assert.rejects(first,{name:'AbortError'});await flush();const next=FakeHls.instances.at(-1);next.emit('parsed');await second;
 signal.abort();old.emit('error',{fatal:true,type:'network',response:{code:403}});
 assert.equal(next.destroyed,0);assert.equal(failures,0);assert.equal(next.url,'/second');loader.destroy(audio);
});
test('fatal errors produce one renewal; expired URLs are not retried unchanged',async()=>{
 const {loader,audio,signal}=fixture();let renewals=0;
 const pending=loader.attach(audio,'/expired','hls',signal.signal,()=>renewals++);await flush();const hls=FakeHls.instances.at(-1);hls.emit('parsed');await pending;
 for(let i=0;i<8;i++)hls.emit('error',{fatal:true,type:'network',response:{code:403}});
 assert.equal(renewals,1);assert.equal(hls.retries,0);assert.equal(hls.destroyed,1);loader.destroy(audio);
});
test('initial incompatible source fails once without telling the player to request it forever',async()=>{
 const {loader,audio,signal}=fixture();let failures=0;audio.error={code:4};
 const pending=loader.attach(audio,'/incompatible','hls',signal.signal,()=>failures++);await flush();const hls=FakeHls.instances.at(-1);
 hls.emit('error',{fatal:true,type:'media'});await assert.rejects(pending,/interrupted/);
 assert.equal(hls.recoveries,0);assert.equal(hls.destroyed,1);assert.equal(failures,0);assert.equal(loader.handlesMediaErrors,false);
});
test('network recovery is bounded before a single fatal report',async()=>{
 const {loader,audio,signal}=fixture();let failures=0;
 const pending=loader.attach(audio,'/network','hls',signal.signal,()=>failures++);await flush();const hls=FakeHls.instances.at(-1);hls.emit('parsed');await pending;
 for(let i=0;i<7;i++)hls.emit('error',{fatal:true,type:'network',response:{code:503}});
 assert.equal(hls.retries,2);assert.equal(failures,1);loader.destroy(audio);
});
