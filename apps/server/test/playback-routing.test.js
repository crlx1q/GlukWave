import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {config} from '../src/config.js';
import {createApp} from '../src/app.js';
import {digest} from '../src/util.js';

test('playback rechecks a revoked session after extraction; mini-player CSP permits the same origin',async()=>{
 const directory=await fs.mkdtemp(path.join(config.root,'work/qa/playback-routing-'));
 const service=await createApp({...config,env:'test',production:false,storage:'sqlite',objectStorage:'local',dataDir:directory,emailVerify:false,turnstileSecret:'',smtp:'',soundcloudPublicSearch:false,youtubeKey:'',spotify:{id:'',secret:''}},{log:pino({level:'silent'})});
 await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));
 const root=`http://127.0.0.1:${service.server.address().port}`;
 let release;
 try{
  const configuration=await fetch(root+'/api/config');
  assert.match(configuration.headers.get('content-security-policy'),/frame-src 'self'(?:;| )/);
  assert.match(configuration.headers.get('content-security-policy'),/object-src 'none'/);
  assert.equal(configuration.headers.get('x-frame-options'),'SAMEORIGIN');
  const registration=await fetch(root+'/api/auth/register',{method:'POST',headers:{'Content-Type':'application/json','X-GlukWave-Client':'native','X-GlukWave-Kind':'windows','X-GlukWave-Device-Name':encodeURIComponent('GlukWave · Windows — Алишер')},body:JSON.stringify({email:'routing@example.test',username:'routing_fixture',password:'long-routing-password'})});
  const owner=await registration.json();assert.equal(registration.status,201);
  assert.equal((await service.ctx.store.get('sessions',digest(owner.token))).deviceName,'GlukWave · Windows — Алишер');
  const track={id:'routing-track',title:'Own test',artist:'Fixture',source:'youtube',sourceUrl:'https://www.youtube.com/watch?v=fixture123',public:true,duration:3};
  await service.ctx.store.put('tracks',track.id,track);
  let started;const entered=new Promise(resolve=>started=resolve);
  service.ctx.extractorExpected=async()=>true;
  service.ctx.extractorPlayback=async()=>{started();return new Promise(resolve=>release=()=>resolve({kind:'audio',url:'/api/fixture-audio'}));};
  const pending=fetch(root+'/api/tracks/routing-track/playback',{headers:{Authorization:'Bearer '+owner.token,'X-GlukWave-Playback-Wait':'poll'}});
  await entered;await service.ctx.store.remove('sessions',digest(owner.token));release();
  const response=await pending;assert.equal(response.status,401);assert.equal((await response.json()).error.code,'AUTH_REQUIRED');
 }finally{release?.();await service.close();assert(directory.startsWith(path.join(config.root,'work/qa')+path.sep));await fs.rm(directory,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
});
