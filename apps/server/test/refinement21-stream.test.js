import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {createServer} from 'node:http';
import {setupExtractedHls} from '../src/extractors/hls.js';
import {audioCapabilities} from '../src/audio-capabilities.js';
import {seal} from '../src/util.js';
import {setupSoundcloudAudio} from '../src/soundcloud-audio.js';

test('opaque HLS roots and segments survive another worker; tampering and revoked sessions remain denied',async()=>{
  const key='34'.repeat(32),track={id:'soundcloud-123',duration:180,artist:'Original'},user={id:'listener'},session={userId:user.id,expiresAt:Date.now()+3600000};
  const result={permission:{stream:true},info:{source:'soundcloud',audio_url:'https://cf-media.sndcdn.com/original.m3u8',source_url:'https://soundcloud.com/original',http_headers:{}}};
  let active=true,accessible=true,fetches=0;
  const create=async()=>{
    const app=express(),ctx={config:{encryptionKey:key,env:'test'},store:{get:async type=>type==='sessions'?(active?session:null):type==='users'?user:null},requireTrack:async id=>{assert.equal(id,track.id);if(!accessible)throw Object.assign(new Error('Track access revoked'),{status:404,code:'TRACK_NOT_FOUND'});return track;}};
    const hls=setupExtractedHls(app,ctx,{cdn:value=>{try{const u=new URL(value);return u.origin==='https://cf-media.sndcdn.com'?u:null;}catch{return null;}},resolve:async()=>result,fetcher:async url=>{fetches++;return url.pathname.endsWith('m3u8')?new Response('#EXTM3U\n#EXT-X-TARGETDURATION:3\n#EXTINF:3,\npart.ts\n#EXT-X-ENDLIST\n',{headers:{'content-type':'application/vnd.apple.mpegurl'}}):new Response('original segment',{headers:{'content-type':'video/mp2t'}});}});
    app.use((error,req,res,next)=>res.status(error.status||500).json({code:error.code,message:error.message}));
    const server=createServer(app);await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    return {hls,server,origin:`http://127.0.0.1:${server.address().port}`};
  };
  const first=await create(),second=await create();
  try{
    const descriptor=first.hls.issue(track,result,user,'session');
    const manifest=await fetch(first.origin+descriptor.url);assert.equal(manifest.status,200);
    const body=await manifest.text(),segment=body.split('\n').find(line=>line.startsWith('/api/'));
    assert(segment);assert(!body.includes('cf-media.sndcdn.com'));
    const otherWorker=await fetch(second.origin+segment);assert.equal(otherWorker.status,200);assert.equal(await otherWorker.text(),'original segment');
    const otherRoot=await fetch(second.origin+descriptor.url);assert.equal(otherRoot.status,200);
    const forged=new URL(second.origin+descriptor.url);forged.searchParams.set('grant',forged.searchParams.get('grant').slice(0,-5)+'xxxxx');
    assert.equal((await fetch(forged)).status,401);
    const before=fetches;accessible=false;assert.equal((await fetch(second.origin+segment)).status,404);assert.equal(fetches,before,'Revoked track access never reaches CDN');accessible=true;
    active=false;assert.equal((await fetch(second.origin+segment)).status,401);assert.equal(fetches,before,'Revoked capability never reaches CDN');
  }finally{for(const item of [first,second]){item.hls.close();await new Promise(resolve=>item.server.close(resolve));}}
});

test('capability purpose, root binding, expiry and URLs are authenticated',()=>{
  const key='45'.repeat(32),caps=audioCapabilities(key,'fixture'),other=audioCapabilities(key,'other'),root=caps.issueRoot({trackId:'a',userId:'b',sessionId:'c',expiresAt:Date.now()+60000});
  const part=caps.issuePart(root,'https://cdn.test/audio?signature=private',Date.now()+60000);
  assert.equal(caps.part(root,part),'https://cdn.test/audio?signature=private');assert(!part.includes('private'));assert.equal(other.root(root),null);
  assert.equal(caps.part(root+'x',part),null);assert.equal(caps.root(seal({purpose:'fixture:root',trackId:'a',userId:'b',sessionId:'c',expiresAt:Date.now()-1},key)),null);
});

test('official SoundCloud capabilities restore across workers without forwarding account credentials',async()=>{
  const key='56'.repeat(32),user={id:'listener'},track={id:'sc-track',source:'soundcloud',sourceId:'123',duration:180},session={userId:user.id,expiresAt:Date.now()+60000};
  let active=true,fetches=0;
  const create=async()=>{
    const app=express(),ctx={config:{encryptionKey:key,soundcloud:{id:'fixture',secret:'fixture'}},store:{get:async type=>type==='sessions'?(active?session:null):type==='users'?user:null},requireTrack:async()=>track,officialSoundcloudCall:async path=>path.endsWith('/streams')?{hls_aac_160_url:'https://cf-media.sndcdn.com/root.m3u8'}:{urn:'soundcloud:tracks:123',streamable:true,user:{username:'Original'},permalink_url:'https://soundcloud.com/original'}};
    setupSoundcloudAudio(app,ctx,async(url,options)=>{fetches++;assert(!options.headers?.Authorization);return url.pathname.endsWith('m3u8')?new Response('#EXTM3U\n#EXTINF:3,\npart.ts\n#EXT-X-ENDLIST\n',{headers:{'content-type':'application/vnd.apple.mpegurl'}}):new Response('official segment',{headers:{'content-type':'video/mp2t'}});});
    app.use((error,req,res,next)=>res.status(error.status||500).json({code:error.code}));
    const server=createServer(app);await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));return {ctx,server,origin:`http://127.0.0.1:${server.address().port}`};
  };
  const first=await create(),second=await create();
  try{
    const descriptor=await first.ctx.soundcloudPlayback(track,user,'session');
    const root=await fetch(first.origin+descriptor.url);assert.equal(root.status,200);
    const segment=(await root.text()).split('\n').find(line=>line.startsWith('/api/'));
    const restored=await fetch(second.origin+segment);assert.equal(restored.status,200);assert.equal(await restored.text(),'official segment');
    assert.equal((await fetch(second.origin+descriptor.url)).status,200);
    const before=fetches;active=false;assert.equal((await fetch(second.origin+segment)).status,401);assert.equal(fetches,before);
  }finally{for(const item of [first,second]){item.ctx.closeSoundcloudAudio();await new Promise(resolve=>item.server.close(resolve));}}
});
