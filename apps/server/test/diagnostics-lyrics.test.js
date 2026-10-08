import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {config as defaults} from '../src/config.js';
import {createApp} from '../src/app.js';
import {scrubDiagnostic} from '../src/diagnostics.js';

test('diagnostics redact secrets, group concurrent repeats and protect admin workflow',async()=>{
 const dir=await fs.mkdtemp(path.join(defaults.root,'work/qa/diagnostics-'));
 const service=await createApp({...defaults,env:'test',storage:'sqlite',dataDir:dir,production:false,turnstileSecret:'',smtp:'',emailVerify:false,adminEmails:['owner@example.test'],objectStorage:'local'},{log:pino({level:'silent'})});
 await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}`;
 const request=async(route,body,token,method=body?'POST':'GET')=>{const response=await fetch(base+'/api'+route,{method,headers:{'Content-Type':'application/json','X-GlukWave-Client':'native',...(token?{Authorization:'Bearer '+token}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,body:await response.json()};};
 try{
  const owner=(await request('/auth/register',{email:'owner@example.test',username:'diag_owner',password:'long-test-password'})).body;
  const user=(await request('/auth/register',{email:'user@example.test',username:'diag_user',password:'long-test-password'})).body;
  const message='Failed token=secret-value email=user@example.test at https://wave.gluk.tech/app/?qr=private-qr';
  const stack='Error password=secret-password Bearer private-token\n C:\\Users\\Alice\\music.mp3 password="private words here" mongodb+srv://db-user:db-secret@host.test/database';
  assert(!scrubDiagnostic(message+stack).includes('secret-value'));assert(!scrubDiagnostic(message+stack).includes('private-token'));assert(!scrubDiagnostic(message+stack).includes('private-qr'));assert(!scrubDiagnostic(message+stack).includes('Alice'));
  const events=['web','android','windows'].map(platform=>({platform,kind:'runtime',message,stack,version:'test'}));
  assert.equal((await request('/diagnostics/events',{events})).status,202);
  const duplicate=events[0];await Promise.all(Array.from({length:5},()=>request('/diagnostics/events',{events:[duplicate]})));
  assert.equal((await request('/admin/errors')).status,401);assert.equal((await request('/admin/errors',null,user.token)).status,403);
  const result=(await request('/admin/errors',null,owner.token)).body;assert.equal(result.total,3);assert.equal(result.errors.find(e=>e.platform==='web').count,6);assert.equal(result.errors[0].message,scrubDiagnostic(message),'Admin evidence must not be replaced by a localized consumer message');
  const serialized=JSON.stringify(result);for(const secret of ['secret-value','secret-password','private-token','private-qr','user@example.test','Alice','private words','words here','db-user','db-secret'])assert(!serialized.includes(secret),secret+' persisted');
  const id=result.errors.find(e=>e.platform==='web').id;assert.equal((await request('/admin/errors/'+id,{state:'resolved'},owner.token,'PATCH')).body.error.state,'resolved');
  await request('/diagnostics/events',{events:[duplicate]});const reopened=(await request('/admin/errors?platform=web&state=open',null,owner.token)).body;assert.equal(reopened.total,1);assert.equal(reopened.errors[0].count,7);assert(reopened.errors[0].lastResolvedAt);
  assert.equal((await request('/diagnostics/events',{events:[{...duplicate,userId:'forged-owner'}]})).status,400);
  assert.equal((await request('/diagnostics/events',{events:Array(11).fill(duplicate)})).status,400);
  assert.equal((await request('/diagnostics/events',{events:[{...duplicate,platform:'server'}]})).status,400);
  service.ctx.log.error({message:'Background worker failed',stack:'Worker stack'},'Worker failed');await service.ctx.withLock('diagnostics:write',async()=>{});assert((await request('/admin/errors?platform=server',null,owner.token)).body.total>=1);
 }finally{await service.close();await fs.rm(dir,{recursive:true,force:true});}
});

test('LRCLIB access checks, coalesced matching, search, import and manual priority',async()=>{
 const dir=await fs.mkdtemp(path.join(defaults.root,'work/qa/lyrics-provider-'));let calls=0;
 const record={id:42,trackName:'Test Song',artistName:'Test Artist',albumName:'Test Album',duration:120,instrumental:false,syncedLyrics:'[00:01.25]Own test line\n[00:10.50]Second own line',plainLyrics:'Own test line\nSecond own line'};
 const service=await createApp({...defaults,env:'test',storage:'sqlite',dataDir:dir,production:false,turnstileSecret:'',smtp:'',emailVerify:false,adminEmails:[],objectStorage:'local'},{log:pino({level:'silent'}),lyricsFetch:async url=>{calls++;return Response.json(url.pathname.endsWith('/search')?[record]:record);}});
 await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}`;
 const request=async(route,body,token,method=body?'POST':'GET')=>{const response=await fetch(base+'/api'+route,{method,headers:{'Content-Type':'application/json','X-GlukWave-Client':'native',...(token?{Authorization:'Bearer '+token}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,body:await response.json()};};
 try{
  const owner=(await request('/auth/register',{email:'lyric@example.test',username:'lyric_owner',password:'long-test-password'})).body;
  const track={id:'lyrics-private',source:'local',public:false,uploadedBy:owner.user.id,title:'Test Song',artist:'Test Artist',album:'Test Album',duration:120};await service.ctx.store.put('tracks',track.id,track);
  assert.equal((await request('/tracks/'+track.id+'/lyrics')).status,404);assert.equal(calls,0);
  const result=await Promise.all(Array.from({length:3},()=>request('/tracks/'+track.id+'/lyrics',null,owner.token)));assert.equal(calls,1);assert(result.every(r=>r.body.source==='lrclib'&&r.body.synchronized));assert.equal(result[0].body.lines[0].time,1.25);
  await request('/tracks/'+track.id+'/lyrics',null,owner.token);assert.equal(calls,1);
  const search=await request('/tracks/'+track.id+'/lyrics/search',null,owner.token);assert.equal(search.body.candidates[0].providerId,42);
  const imported=await request('/tracks/'+track.id+'/lyrics/lrclib',{providerId:42},owner.token);assert.equal(imported.body.source,'lrclib');assert.equal(imported.body.providerId,42);
  await request('/tracks/'+track.id+'/lyrics',{text:'[00:02.00]My corrected line'},owner.token,'PUT');const previousCalls=calls;
  const manual=await request('/tracks/'+track.id+'/lyrics',null,owner.token);assert.equal(manual.body.source,'user');assert.equal(manual.body.lines[0].time,2);assert.equal(calls,previousCalls);
  await service.ctx.store.put('tracks','mismatch',{...track,id:'mismatch',title:'Another Song'});const mismatch=await request('/tracks/mismatch/lyrics',null,owner.token);assert.deepEqual(mismatch.body.lines,[]);
 }finally{await service.close();await fs.rm(dir,{recursive:true,force:true});}
});
