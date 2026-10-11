import test from 'node:test';
import assert from 'node:assert/strict';
import childProcess from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {syncBuiltinESMExports} from 'node:module';
import {config} from '../src/config.js';
import {createExtractorRuntime} from '../src/extractors/runtime.js';
import {soundcloudAdapter} from '../src/extractors/soundcloud.js';
import {setupResources} from '../src/resources.js';
import {createApp} from '../src/app.js';

test('startup and repeated availability checks spawn no Python or dependency installer',async()=>{
 const originalSync=childProcess.spawnSync,originalSpawn=childProcess.spawn;let processes=0;
 childProcess.spawnSync=()=>{processes++;return {status:0};};childProcess.spawn=()=>{processes++;throw Error('Unexpected process');};syncBuiltinESMExports();
 let runtime;
 try{
  runtime=createExtractorRuntime({...config,env:'development',extractors:{enabled:true,python:process.execPath,spotdlPython:process.execPath}});
  for(let i=0;i<1000;i++){assert(runtime.available('youtube'));assert(runtime.available('spotify'));assert(runtime.hasPython('soundcloud'));}
  assert.equal(processes,0);assert.equal(runtime.stats().active,0);
  await runtime.close();assert.equal(runtime.available('soundcloud'),false);
 }finally{childProcess.spawnSync=originalSync;childProcess.spawn=originalSpawn;syncBuiltinESMExports();await runtime?.close();}
});

test('simultaneous version diagnostics share one bounded job',async()=>{
 let calls=0;
 const runtime=createExtractorRuntime({...config,env:'test',extractors:{enabled:true,python:process.execPath,spotdlPython:process.execPath,concurrency:1}},{run:async()=>{calls++;await new Promise(resolve=>setTimeout(resolve,20));return {'yt-dlp':'bundled','spotdl':null};}});
 try{const values=await Promise.all(Array.from({length:8},()=>runtime.versions()));assert.equal(calls,1);assert(values.every(value=>value.youtube['yt-dlp']==='bundled'));assert.equal(runtime.stats().queued,0);}finally{await runtime.close();}
});

test('missing module cooldown prevents repeated subprocess failures without disabling pure SoundCloud',async()=>{
 let calls=0;const runtime=createExtractorRuntime({...config,env:'test',extractors:{enabled:true,concurrency:1}},{run:async()=>{calls++;throw Object.assign(Error('Missing'),{code:'EXTRACTOR_MODULE'});}});
 try{await assert.rejects(runtime.execute('spotify',{}),{code:'EXTRACTOR_MODULE'});assert.equal(runtime.available('spotify'),false);await assert.rejects(runtime.execute('spotify',{}),{code:'EXTRACTOR_UNAVAILABLE'});assert.equal(calls,1);assert.equal(runtime.available('soundcloud'),true);assert.equal(runtime.stats().failed,1);}finally{await runtime.close();}
});

function fixture(transcodings){
 let homes=0,streams=0;const id='a'.repeat(32);
 const sound={id:123,title:'Original song',duration:60000,user:{username:'Wave Artist'},media:{transcodings},license:'cc-by'};
 const fetcher=async input=>{const url=new URL(input);if(url.hostname==='soundcloud.com'){homes++;await new Promise(resolve=>setTimeout(resolve,5));return new Response(`<script>window.__sc_hydration = [{"hydratable":"apiClient","data":{"id":"${id}"}}];</script>`,{headers:{'Content-Type':'text/html'}});}if(url.pathname==='/resolve')return Response.json(sound);streams++;return Response.json({url:'https://cf-media.sndcdn.com/'+(url.pathname.includes('aac')?'original.m3u8':'original.mp3')});};
 return {adapter:soundcloudAdapter(null,fetcher),stats:()=>({homes,streams})};
}
test('SoundCloud progressive MP3 keeps its real format and concurrent tracks share client discovery',async()=>{
 const f=fixture([{url:'https://api-v2.soundcloud.com/mp3',preset:'mp3_0_1',format:{protocol:'progressive',mime_type:'audio/mpeg'}}]);
 const results=await Promise.all(Array.from({length:8},(_,i)=>f.adapter.metadata(`https://soundcloud.com/wave/original-${i}`)));
 assert.equal(f.stats().homes,1);assert.equal(f.stats().streams,8);
 assert(results.every(info=>info.protocol==='https'&&info.ext==='mp3'&&info.codec==='mp3'&&!info.audio_url.includes('m3u8')));
});
test('SoundCloud AAC HLS is selected over unsupported codecs and labelled HLS',async()=>{
 const f=fixture([{url:'https://api-v2.soundcloud.com/opus',preset:'opus_0',format:{protocol:'hls',mime_type:'audio/ogg'}},{url:'https://api-v2.soundcloud.com/aac',preset:'aac_160',format:{protocol:'hls',mime_type:'audio/mp4'}}]);
 const result=await f.adapter.metadata('https://soundcloud.com/wave/original');assert.equal(result.protocol,'m3u8_native');assert.equal(result.codec,'mp4a.40.2');assert.match(result.audio_url,/m3u8$/);
 const unsupported=fixture([{url:'https://api-v2.soundcloud.com/opus',preset:'opus',format:{protocol:'hls',mime_type:'audio/ogg'}}]);await assert.rejects(unsupported.adapter.metadata('https://soundcloud.com/wave/unsupported'),/stream not found/);
});
test('resource CPU samples warm up for a real interval instead of reporting a startup spike',async()=>{
 const ctx={};setupResources({get(){}},ctx);
 try{const first=ctx.resourceSnapshot();assert.equal(first.cpuOneCorePercent,null);assert(first.rssMB>0);await new Promise(resolve=>setTimeout(resolve,1100));const next=ctx.resourceSnapshot();assert(Number.isFinite(next.cpuOneCorePercent));assert(next.intervalMs>=1000);assert.equal(next.scope,'server-process');}finally{ctx.closeResources();}
});

test('configured YouTube metadata search avoids Python, preserves artists and falls back on quota failure',async()=>{
 const directory=await fs.mkdtemp(path.join(config.root,'work/qa/youtube-search-stability-'));let searches=0,quota=false;
 const info={track_id:'original123',source_url:'https://www.youtube.com/watch?v=original123',title:'Original recording',artist:'Wave artist',duration:8};
 const service=await createApp({...config,env:'test',production:false,storage:'sqlite',objectStorage:'local',dataDir:directory,releasesDir:directory,emailVerify:false,turnstileSecret:'',smtp:'',soundcloudPublicSearch:false,youtubeKey:'fixture-youtube-key',extractors:{enabled:true,concurrency:1}},
 {log:pino({level:'silent'}),extractors:{run:async(_adapter,request)=>{assert.equal(request.action,'music-search');searches++;return [info];}},providerRemoteJson:async input=>{
  const url=new URL(input);if(url.pathname.endsWith('/search')){if(quota)throw Error('Fixture quota exhausted');assert.equal(url.searchParams.get('q'),'оригинальная запись');return {items:[{id:{videoId:info.track_id},snippet:{title:info.title,channelTitle:info.artist,thumbnails:{}}},{id:{channelId:'artist123'},snippet:{title:info.artist,thumbnails:{}}}]};}
  return {items:[{id:info.track_id,snippet:{title:info.title,channelTitle:info.artist,thumbnails:{}},contentDetails:{duration:'PT8S'}}]};
 }});
 try{const official=await service.ctx.searchProvider('youtube','оригинальная запись');assert.equal(official.length,1);assert.equal(official[0].duration,8);assert.equal(official.artists[0].name,info.artist);assert.equal(searches,0);quota=true;const fallback=await service.ctx.searchProvider('youtube','оригинальная запись');assert.equal(fallback[0].title,info.title);assert.equal(searches,1);}finally{await service.close();const qa=path.join(config.root,'work/qa');assert(directory.startsWith(qa+path.sep));await fs.rm(directory,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
});
