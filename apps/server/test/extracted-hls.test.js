import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {config} from '../src/config.js';
import {createApp} from '../src/app.js';

test('unofficial extraction accepts licensed HLS, rewrites keys and segments, refreshes expiry and enforces session/permission limits',async()=>{
  const directory=await fs.mkdtemp(path.join(config.root,'work/qa/hls-extracted-'));
  let generation=0,license='cc-by',escape=false;
  const info={track_id:'licensed',title:'Evening',artist:'Wave artist',duration:120,source:'soundcloud',source_url:'https://soundcloud.com/wave/track',ext:'m4a',protocol:'m3u8_native',http_headers:{}};
  const service=await createApp({...config,env:'test',production:false,storage:'sqlite',objectStorage:'local',dataDir:directory,emailVerify:false,turnstileSecret:'',smtp:'',soundcloudPublicSearch:false,soundcloud:{id:'',secret:''},extractors:{enabled:true}},{log:pino({level:'silent'}),extractors:{run:async(_adapter,request)=>request.action==='versions'?{}:{...info,license,audio_url:`https://cf-media.sndcdn.com/master.m3u8?g=${++generation}`},fetch:async(url)=>{
    const value=new URL(url);
    if(value.pathname==='/master.m3u8'){
      if(value.searchParams.get('g')==='1')return new Response('',{status:403});
      return new Response('#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n#EXTINF:10,\n'+(escape?'https://127.0.0.1/private':'segment.aac')+'\n#EXT-X-ENDLIST',{headers:{'Content-Type':'application/vnd.apple.mpegurl'}});
    }
    return new Response(Buffer.from(value.pathname==='/key.bin'?'abcdefghijklmnop':'original-audio'),{headers:{'Content-Type':'audio/aac'}});
  }}});
  await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}`;
  const call=async(route,token,body)=>{const response=await fetch(base+'/api'+route,{method:body?'POST':'GET',headers:{'X-GlukWave-Client':'native',...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,data:await response.json()};};
  try{
    const user=(await call('/auth/register',null,{email:'hls@qa.test',username:'hls_listener',password:'Fixture-password-2026'})).data;
    const other=(await call('/auth/register',null,{email:'other@qa.test',username:'hls_other',password:'Fixture-password-2026'})).data;
    const track={id:'licensed-hls',...info,sourceId:'licensed',sourceUrl:info.source_url,public:true,playback:{kind:'soundcloud'}};await service.ctx.store.put('tracks',track.id,track);
    const descriptor=(await call('/tracks/'+track.id+'/playback',user.token)).data.playback;
    assert.equal(descriptor.kind,'audio');assert.equal(descriptor.format,'hls');assert.equal(descriptor.offline,false);assert(!JSON.stringify(descriptor).includes('sndcdn.com'));
    const stream=await fetch(base+descriptor.url);assert.equal(stream.status,200);const manifest=await stream.text();assert(!manifest.includes('sndcdn.com'));assert.equal(generation,2,'Expired manifest URL refreshed once');
    const key=manifest.match(/URI="([^"]+)"/)[1],segment=manifest.split('\n').find(line=>line.startsWith('/api/'));
    assert.equal(await (await fetch(base+key)).text(),'abcdefghijklmnop');assert.equal(await (await fetch(base+segment)).text(),'original-audio');
    assert.equal((await fetch(base+segment,{headers:{Authorization:'Bearer '+other.token}})).status,403);
    assert.equal((await fetch(base+segment,{headers:{Range:'bytes=1-2,4-5'}})).status,416);
    assert.equal((await fetch(base+descriptor.url+'&part=unknown')).status,404);
    escape=true;assert.equal((await fetch(base+descriptor.url)).status,502,'Embedded manifest URLs cannot access local addresses');escape=false;
    await service.ctx.store.put('audioPermissions',track.id,{id:track.id,stream:false});assert.equal((await fetch(base+segment)).status,403,'Revocation blocks existing segment grants');
    await service.ctx.store.remove('audioPermissions',track.id);
    const sessions=await service.ctx.store.list('sessions',session=>session.userId===user.user.id);
    await service.ctx.store.remove('sessions',sessions[0].id);assert.equal((await fetch(base+segment)).status,401,'Session revoke blocks grant');
    assert.equal(service.ctx.extractorStats().hls.transfers,0);
  }finally{await service.close();await fs.rm(directory,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
});

test('Spotify and Yandex metadata automatically find exact licensed audio; mismatches and unlicensed candidates remain unavailable',async()=>{
  const directory=await fs.mkdtemp(path.join(config.root,'work/qa/audio-matches-'));let licensed=true;
  const target={title:'Evening',artist:'Wave artist',duration:120};
  const service=await createApp({...config,env:'test',production:false,storage:'sqlite',objectStorage:'local',dataDir:directory,emailVerify:false,turnstileSecret:'',smtp:'',soundcloudPublicSearch:false,soundcloud:{id:'',secret:''},extractors:{enabled:true}},{log:pino({level:'silent'}),extractors:{run:async(_adapter,request)=>{
    if(request.action==='versions')return {};
    if(request.action==='spotify-candidates')return {candidates:[]};
    const url='https://www.youtube.com/watch?v='+(licensed?'original123':'badlicense1');
    if(request.action==='music-search')return [{...target,source:'youtube',source_url:url}];
    return {...target,source:'youtube',source_url:url,audio_url:'https://rr1.googlevideo.com/audio.m4a',ext:'m4a',license:licensed?'cc-by':'all-rights-reserved'};
  }}});
  await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}/api`;
  try{
    const response=await fetch(base+'/auth/register',{method:'POST',headers:{'Content-Type':'application/json','X-GlukWave-Client':'native'},body:JSON.stringify({email:'match@qa.test',username:'audio_match',password:'Fixture-password-2026'})});const user=await response.json();
    for(const source of ['spotify','yandex']){
      const track={id:'auto-'+source,...target,source,sourceUrl:source==='spotify'?'https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT':'https://music.yandex.ru/album/1/track/2',public:true,playback:{kind:source}};await service.ctx.store.put('tracks',track.id,track);
      const r=await fetch(base+'/tracks/'+track.id+'/playback',{headers:{Authorization:'Bearer '+user.token}}),result=await r.json();assert.equal(r.status,200,JSON.stringify(result));assert.equal(result.playback.kind,'audio');assert.equal(result.playback.audioSource,'youtube');assert.equal(result.playback.offline,true);
    }
    licensed=false;const track={id:'bad-match',...target,artist:'Unrelated',source:'spotify',sourceUrl:'https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT',public:true};await service.ctx.store.put('tracks',track.id,track);
    const r=await fetch(base+'/tracks/'+track.id+'/playback',{headers:{Authorization:'Bearer '+user.token}});assert.equal((await r.json()).error.code,'AUDIO_UNAVAILABLE');
    const unlicensed={...track,id:'unlicensed-match',artist:target.artist};await service.ctx.store.put('tracks',unlicensed.id,unlicensed);
    const blocked=await fetch(base+'/tracks/'+unlicensed.id+'/playback',{headers:{Authorization:'Bearer '+user.token}});assert.equal((await blocked.json()).error.code,'AUDIO_UNAVAILABLE','Exact metadata alone does not authorize a stream');
  }finally{await service.close();await fs.rm(directory,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
});
