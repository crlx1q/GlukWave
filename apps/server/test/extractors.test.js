import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {config} from '../src/config.js';
import {createApp} from '../src/app.js';
import {audioMatch} from '../src/extractors/matching.js';
import {licensePermission,safeCdn,createBoundedCache} from '../src/extractors/service.js';
import {createExtractorRuntime} from '../src/extractors/runtime.js';

test('audio matching rejects other artists, live versions and unknown duration; rights and CDN policy do not infer permission from availability',()=>{
  const track={title:'Carefree',artist:'Kevin MacLeod',duration:205};
  assert(audioMatch(track,{...track}).accepted);
  assert(!audioMatch(track,{...track,artist:'Other artist'}).accepted);
  assert(!audioMatch(track,{...track,title:'Carefree live'}).accepted);
  assert(!audioMatch(track,{...track,duration:0}).accepted);
  assert(!audioMatch(track,{...track,duration:250}).accepted);
  assert(licensePermission('https://creativecommons.org/licenses/by/4.0/').download);
  assert.equal(licensePermission('all-rights-reserved'),null);assert.equal(licensePermission('cc-by-nc'),null);
  assert.equal(safeCdn('https://127.0.0.1/audio.mp3'),null);assert.equal(safeCdn('https://googlevideo.com.attacker.example/audio'),null);assert.equal(safeCdn('https://x.googlevideo.com/file.m3u8'),null);
  assert(safeCdn('https://cf-media.sndcdn.com/audio.mp3'));
  const cache=createBoundedCache(2);cache.set('a',1,1000);cache.set('b',2,1000);assert.equal(cache.get('a'),1);cache.set('c',3,1000);assert.equal(cache.get('b'),null);assert.equal(cache.size(),2);cache.set('expired',4,-1);assert.equal(cache.get('expired'),null);
});

test('extractor work is bounded and shared jobs release their worker slots on success and failure',async()=>{
  let count=0,maximum=0;const runtime=createExtractorRuntime({...config,env:'test',extractors:{enabled:true,concurrency:1}},{run:async()=>{count++;maximum=Math.max(maximum,count);await new Promise(resolve=>setTimeout(resolve,10));count--;return {ok:true};}});
  await Promise.all(Array.from({length:10},()=>runtime.execute('youtube',{action:'versions'})));assert.equal(maximum,1);assert.deepEqual(runtime.stats(),{active:0,queued:0,completed:10,failed:0,limit:1});await runtime.close();
  await assert.rejects(runtime.execute('youtube',{}));
});

test('permitted source audio uses native same-origin range/download endpoints, expires safely and unpermitted audio stays official',async()=>{
  const directory=await fs.mkdtemp(path.join(config.root,'work/qa/extractors-test-')),calls=[];let generation=0;
  const info={track_id:'test-source',title:'Carefree',artist:'Kevin MacLeod',duration:205,source:'soundcloud',license:'all-rights-reserved',audio_url:'https://cf-media.sndcdn.com/audio.mp3',ext:'mp3',http_headers:{}};
  const service=await createApp({...config,env:'test',production:false,storage:'sqlite',objectStorage:'local',dataDir:directory,emailVerify:false,turnstileSecret:'',smtp:'',adminEmails:['extractor-admin@example.test'],extractors:{enabled:true,concurrency:1},soundcloudPublicSearch:false},{log:pino({level:'silent'}),extractors:{run:async(_adapter,request)=>{calls.push(request);return {...info,audio_url:info.audio_url+'?generation='+(++generation)};},fetch:async(url,options)=>{
    if(options.headers.Range==='bytes=100-')return new Response('',{status:416,headers:{'Content-Range':'bytes */6'}});
    if(new URL(url).searchParams.get('generation')==='1')return new Response('',{status:403});
    return new Response(Buffer.from(options.headers.Range?'cd':'abcdef'),{status:options.headers.Range?206:200,headers:{'Content-Type':'audio/mpeg','Content-Length':options.headers.Range?'2':'6',...(options.headers.Range?{'Content-Range':'bytes 2-3/6'}:{})}});
  }}});
  await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}/api`;
  const request=async(route,token,body,method=body?'POST':'GET')=>{const response=await fetch(base+route,{method,headers:{'X-GlukWave-Client':'native',...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,data:await response.json()};};
  try{
    const admin=(await request('/auth/register',null,{email:'extractor-admin@example.test',username:'extractor_admin',password:'Extractor-test-2026'})).data;
    const user=(await request('/auth/register',null,{email:'extractor-user@example.test',username:'extractor_user',password:'Extractor-test-2026'})).data;
    const diagnostics=await request('/admin/extractors',admin.token);assert.equal(diagnostics.status,200);assert.equal(typeof diagnostics.data.pending,'number');assert.equal(diagnostics.data.adapters.length,3);
    const resources=await request('/admin/resources',admin.token);assert.equal(resources.status,200);assert.equal(typeof resources.data.extractors.pending,'number');assert.equal((await request('/admin/resources',user.token)).status,403);
    calls.length=0;generation=0;
    const track={id:'extractor-source-track',title:info.title,artist:info.artist,duration:info.duration,source:'soundcloud',sourceId:'test-source',sourceUrl:'https://soundcloud.com/test/source',artwork:'',public:true,playback:{kind:'soundcloud',embedUrl:'https://w.soundcloud.com/player/',offline:false}};
    await service.ctx.store.put('tracks',track.id,track);
    assert.equal((await request('/tracks/'+track.id+'/playback',user.token)).data.playback.kind,'soundcloud');
    const grant={stream:true,download:true,convert:false,basis:'owner-permission',evidenceUrl:'https://example.test/permission'};
    assert.equal((await request('/admin/tracks/'+track.id+'/audio-permission',user.token,grant,'PUT')).status,403);
    assert.equal((await request('/admin/tracks/'+track.id+'/audio-permission',admin.token,grant,'PUT')).status,200);
    const playback=(await request('/tracks/'+track.id+'/playback',user.token)).data.playback;assert.equal(playback.kind,'audio');assert.equal(playback.offline,true);assert.equal(playback.downloadUrl,'/api/external-audio/'+track.id+'/download');assert(!JSON.stringify(playback).includes('sndcdn'));
    const range=await fetch(base+'/external-audio/'+track.id,{headers:{Authorization:'Bearer '+user.token,Range:'bytes=2-3'}});assert.equal(range.status,206);assert.equal(range.headers.get('content-range'),'bytes 2-3/6');assert.equal(await range.text(),'cd');assert.equal(calls.length,2,'Expired URL refreshes once');
    const unavailable=await fetch(base+'/external-audio/'+track.id,{headers:{Authorization:'Bearer '+user.token,Range:'bytes=100-'}});assert.equal(unavailable.status,416);assert.equal(unavailable.headers.get('content-range'),'bytes */6');assert.equal((await fetch(base+'/external-audio/'+track.id,{headers:{Authorization:'Bearer '+user.token,Range:'bytes=0-1,3-4'}})).status,416);
    const download=await fetch(base+playback.downloadUrl.slice(4),{headers:{Authorization:'Bearer '+user.token}});assert.equal(download.status,200);assert.equal(await download.text(),'abcdef');assert.equal((await request('/external-audio/'+track.id+'/download?format=mp3',user.token)).status,403);
    assert.equal((await request('/external-audio/'+track.id)).status,401);
    await request('/admin/tracks/'+track.id+'/audio-permission',admin.token,{...grant,stream:false,download:false},'PUT');assert.equal((await request('/tracks/'+track.id+'/playback',user.token)).data.playback.kind,'soundcloud');
    assert.equal((await request('/external-audio/'+track.id,user.token)).status,403);
  }finally{await service.close();const qa=path.join(config.root,'work/qa');assert(directory.startsWith(qa+path.sep));await fs.rm(directory,{recursive:true,force:true});}
});
