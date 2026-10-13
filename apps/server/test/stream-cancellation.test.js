import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {config} from '../src/config.js';
import {createApp} from '../src/app.js';
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
test('closing HLS and progressive clients before source resolution never pipes into a destroyed response',async()=>{
 const directory=await fs.mkdtemp(path.join(config.root,'work/qa/wave18-cancel-')),errors=[];let upstream=0,hold=null,entered=null;
 const service=await createApp({...config,env:'test',production:false,storage:'sqlite',objectStorage:'local',dataDir:directory,emailVerify:false,turnstileSecret:'',smtp:'',soundcloudPublicSearch:false,soundcloud:{id:'',secret:''},discord:{id:'',secret:''},extractors:{enabled:true}},{log:pino({level:'error'},{write(line){errors.push(JSON.parse(line).msg);}}),extractors:{run:async(_adapter,request)=>request.action==='versions'?{}:{source:'soundcloud',source_url:request.url,title:'Cancel',artist:'Wave',duration:120,license:'cc-by',audio_url:'https://cf-media.sndcdn.com/audio.'+(request.url.endsWith('hls')?'m3u8':'mp3'),protocol:request.url.endsWith('hls')?'m3u8_native':'https',ext:'mp3'},fetch:async(url)=>{if(new URL(url).hostname.endsWith('sndcdn.com'))upstream++;return new Response('audio',{headers:{'Content-Type':'audio/mpeg'}});}}});
 await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}`;
 try{
  const account=await(await fetch(base+'/api/auth/register',{method:'POST',headers:{'Content-Type':'application/json','X-GlukWave-Client':'native'},body:JSON.stringify({email:'cancel18@test.example',username:'cancel18_user',password:'Cancel18-test-password'})})).json();
  const requireTrack=service.ctx.requireTrack;
  service.ctx.requireTrack=async(...args)=>{if(hold){entered?.();await hold;}return requireTrack(...args);};
  for(const kind of ['hls','mp3']){
   const id='cancel-'+kind;
   await service.ctx.store.put('tracks',id,{id,title:'Cancel',artist:'Wave',duration:120,source:'soundcloud',sourceUrl:'https://soundcloud.com/wave/'+kind,sourceId:id,public:true});
   const descriptor=await(await fetch(base+'/api/tracks/'+id+'/playback',{headers:{Authorization:'Bearer '+account.token}})).json();assert.equal(descriptor.playback.kind,'audio');
   let release;hold=new Promise(resolve=>{release=resolve;});const ready=new Promise(resolve=>{entered=resolve;});
   const abort=new AbortController(),request=fetch(base+descriptor.playback.url,{signal:abort.signal,headers:{Authorization:'Bearer '+account.token}});
   const rejected=request.catch(error=>error);await ready;abort.abort();assert.equal((await rejected).name,'AbortError');await delay(30);release();hold=null;await delay(100);
  }
  assert.equal(upstream,0);assert.deepEqual(errors,[]);assert.equal(service.ctx.extractorStats().streams,0);assert.equal(service.ctx.extractorStats().hls.transfers,0);
 }finally{await service.close();await fs.rm(directory,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
});
