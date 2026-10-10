import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {createApp} from '../src/app.js';
import {config} from '../src/config.js';
import {soundcloudCdn,rewriteSoundcloudManifest} from '../src/soundcloud-audio.js';
import {mergeSettings} from '../src/util.js';

test('HLS rewrites variants, encryption keys and segments; CDN targets are fixed HTTPS origins',()=>{
 assert.equal(soundcloudCdn('https://cf-hls-media.sndcdn.com/audio.m3u8').hostname,'cf-hls-media.sndcdn.com');
 for(const value of ['http://sndcdn.com/x','https://sndcdn.com.evil.test/x','https://127.0.0.1/x','https://a:b@sndcdn.com/x','https://sndcdn.com:444/x','file:///x'])assert.equal(soundcloudCdn(value),null);
 const urls=[];const result=rewriteSoundcloudManifest('#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n#EXTINF:2,\npart.aac\n','https://cf-hls-media.sndcdn.com/a/main.m3u8',url=>{urls.push(url);return '/proxy/'+urls.length;});
 assert.match(result,/URI="\/proxy\/1"/);assert.match(result,/\/proxy\/2/);assert.deepEqual(urls,['https://cf-hls-media.sndcdn.com/a/key.bin','https://cf-hls-media.sndcdn.com/a/part.aac']);
 assert.throws(()=>rewriteSoundcloudManifest('not audio','https://sndcdn.com/',x=>x),{code:'AUDIO_FORMAT_UNAVAILABLE'});
 assert.deepEqual(mergeSettings().seasonalEffects,{enabled:false,mode:'auto',intensity:'subtle'});
 assert.deepEqual(mergeSettings({seasonalEffects:{mode:'leaves'}},{seasonalEffects:{enabled:true}}).seasonalEffects,{enabled:true,mode:'leaves',intensity:'subtle'});
});

test('Own-player SoundCloud streams are session bound, renewed, attributed, range capable and never offline downloads',async()=>{
 const qa=path.join(config.root,'work/qa');await fs.mkdir(qa,{recursive:true});const directory=await fs.mkdtemp(path.join(qa,'soundcloud-audio-test-'));
 let metadataCalls=0,searchCalls=0,rootExpired=true,malicious=false,preview=false;
 const fetched=[];
 const service=await createApp({...config,env:'test',production:false,storage:'sqlite',objectStorage:'local',dataDir:directory,releasesDir:directory,emailVerify:false,turnstileSecret:'',turnstileSiteKey:'',smtp:'',adminEmails:[],soundcloudPublicSearch:false,google:{id:'',secret:''},spotify:{id:'',secret:''},youtubeOAuth:{id:'',secret:''},soundcloud:{id:'test-id',secret:'test-secret'},discord:{id:'',secret:''},youtubeKey:'',stripe:{secret:'',webhook:'',price:''},extractors:{...config.extractors,enabled:false}},
 {log:pino({level:'silent'}),soundcloudAudioFetch:async(url,options)=>{
   fetched.push({url:String(url),headers:options.headers});
   if(String(url).includes('expired.m3u8')&&rootExpired){rootExpired=false;return new Response(null,{status:403});}
   if(String(url).includes('.m3u8'))return new Response('#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n#EXTINF:2,\n'+(malicious?'https://127.0.0.1/private':'part.aac')+'\n#EXT-X-ENDLIST\n',{headers:{'Content-Type':'application/vnd.apple.mpegurl'}});
   return new Response(new Uint8Array([1,2,3,4]),{status:options.headers.Range?206:200,headers:{'Content-Type':'audio/aac','Content-Length':'4',...(options.headers.Range?{'Content-Range':'bytes 0-3/10','Accept-Ranges':'bytes'}:{})}});
 }});
 service.ctx.officialSoundcloudCall=async route=>{
  if(route.includes('/streams'))return {hls_aac_160_url:'https://cf-hls-media.sndcdn.com/a/'+(rootExpired?'expired':'main')+'.m3u8',preview_mp3_128_url:'https://sndcdn.com/preview.mp3'};
  const data={urn:'soundcloud:tracks:123',id:123,title:'Original Test',metadata_artist:'Wave Tests',user:{username:'Wave Tests',permalink_url:'https://soundcloud.com/wave-tests'},duration:180000,permalink_url:'https://soundcloud.com/wave-tests/original',streamable:true,access:preview?'preview':'playable'};
  if(route.startsWith('tracks?')){searchCalls++;return {collection:[{...data,title:'Original Test Remix'},data]};}
  metadataCalls++;return data;
 };
 try{
  await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const origin=`http://127.0.0.1:${service.server.address().port}`;
  const req=async(route,token,body,method=body?'POST':'GET')=>{const r=await fetch(origin+'/api'+route,{method,headers:{'X-GlukWave-Client':'native',...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:r.status,data:await r.json()};};
  const register=async name=>(await req('/auth/register',null,{username:name,email:name+'@example.test',password:'Original-private-test-password-2026'})).data;
  const owner=await register('hls_owner'),viewer=await register('hls_viewer'),store=service.ctx.store;
  const track={id:'sc-123',source:'soundcloud',sourceId:'123',sourceUrl:'https://soundcloud.com/wave-tests/original',title:'Original Test',artist:'Wave Tests',duration:180,public:true,playback:{kind:'soundcloud',offline:false}};
  await store.put('tracks',track.id,track);await store.put('tracks','spotify-original',{...track,id:'spotify-original',source:'spotify',sourceId:'abc',playback:{kind:'spotify',offline:false}});
  const one=(await req('/tracks/sc-123/playback',owner.token)).data.playback;
  assert.equal(one.kind,'audio');assert.equal(one.format,'hls');assert.equal(one.offline,false);assert.equal(one.attribution.artist,'Wave Tests');assert.equal(metadataCalls,1);
  assert.equal((await req('/tracks/sc-123/playback',owner.token)).data.playback.url,one.url);assert.equal(metadataCalls,1);
  const manifest=await fetch(origin+one.url);assert.equal(manifest.status,200);assert.match(manifest.headers.get('content-security-policy'),/worker-src 'self' blob:/);const raw=await manifest.text();assert.equal(metadataCalls,2);assert(!raw.includes('sndcdn.com'));
  const segment=raw.split('\n').find(x=>x.startsWith('/api/'));const result=await fetch(origin+segment,{headers:{Range:'bytes=0-3'}});assert.equal(result.status,206);assert.deepEqual([...new Uint8Array(await result.arrayBuffer())],[1,2,3,4]);
  const denied=await fetch(origin+segment,{headers:{Authorization:'Bearer '+viewer.token}});assert.equal(denied.status,403);
  assert.equal((await fetch(origin+segment+'&part=unknown')).status,404);assert.equal((await fetch(origin+segment,{headers:{Range:'bytes=0-2,4-8'}})).status,416);
  assert(fetched.every(x=>!('Authorization' in x.headers)));
  const match=(await req('/tracks/spotify-original/playback',owner.token)).data.playback;assert.equal(match.provider,'soundcloud');assert.equal(searchCalls,1);
  await store.put('tracks','sc-preview',{...track,id:'sc-preview'});preview=true;
  assert.equal((await req('/tracks/sc-preview/playback',owner.token)).data.playback.kind,'soundcloud');preview=false;
  await store.put('tracks','private',{...track,id:'private',public:false,uploadedBy:owner.user.id});assert.equal((await req('/tracks/private/playback',viewer.token)).status,404);
  const settings=(await req('/settings',owner.token)).data.settings;assert.equal(settings.seasonalEffects.enabled,false);
  const season=await req('/settings',owner.token,{seasonalEffects:{enabled:true,mode:'snow'}},'PATCH');assert.equal(season.status,200);assert.equal(season.data.settings.seasonalEffects.mode,'snow');assert.equal(season.data.settings.seasonalEffects.intensity,'subtle');
  assert.equal((await req('/settings',owner.token,{seasonalEffects:{mode:'bad'}},'PATCH')).status,400);
  malicious=true;const evil=await fetch(origin+one.url);assert.equal(evil.status,502);assert(!fetched.some(x=>x.url.includes('127.0.0.1')));
  await req('/auth/logout',owner.token,{});assert.equal((await fetch(origin+segment)).status,401);
 }finally{await service.close();assert(directory.startsWith(qa+path.sep));await fs.rm(directory,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
});
