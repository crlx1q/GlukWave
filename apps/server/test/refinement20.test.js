import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {createActionJobs} from '../src/action-jobs.js';
import {applyTrackFailed,commandSchema,initialState} from '../src/rooms.js';
import {rankRecommendations} from '../src/recommendations.js';
import {createApp} from '../src/app.js';
import {config} from '../src/config.js';
import {seal} from '../src/util.js';
import {soundcloudAdapter} from '../src/extractors/soundcloud.js';
test('slow actions poll one intent, retain failures, isolate sessions and remain bounded',async()=>{
 const jobs=createActionJobs({waitMs:2,limit:2});let calls=0;
 const work=async()=>{calls++;await new Promise(resolve=>setTimeout(resolve,15));return {ok:true};};
 try{
  const values=await Promise.all([jobs.wait('sessionA:intent',work),jobs.wait('sessionA:intent',work)]);
  assert(values.every(value=>value.pending));assert.equal(calls,1);
  await new Promise(resolve=>setTimeout(resolve,20));
  assert.deepEqual(await jobs.wait('sessionA:intent',work),{ok:true,pending:false});assert.equal(calls,1);
  await assert.rejects(jobs.wait('sessionB:intent',()=>{throw Object.assign(Error('unavailable'),{code:'AUDIO_UNAVAILABLE'});}),{code:'AUDIO_UNAVAILABLE'});
  await assert.rejects(jobs.wait('sessionB:intent',work),{code:'AUDIO_UNAVAILABLE'});assert.equal(calls,1);
  await assert.rejects(jobs.wait('third:intent',work),{code:'ACTION_BUSY'});
 }finally{jobs.close();}
});
test('failed room tracks advance once, preserve Wave, bypass repeat-one, and stop an exhausted queue',()=>{
 const state={...initialState(),trackId:'bad',playing:true,queue:['old','bad','good'],repeat:'one',waveActive:true,revision:8};
 const command={command:'failed',trackId:'bad',expectedRevision:8};
 assert(commandSchema.safeParse(command).success);assert(!commandSchema.safeParse({command:'failed',trackId:'bad'}).success);
 const next=applyTrackFailed(state,command);assert.equal(next.trackId,'good');assert.equal(next.waveActive,true);assert.equal(next.revision,9);
 assert.deepEqual(next.queue,['old','good']);assert.equal(applyTrackFailed(next,command),next);
 const stale=applyTrackFailed(state,{...command,expectedRevision:7});assert.equal(stale,state);
 const stop=applyTrackFailed({...state,queue:['bad']},command);assert.equal(stop.playing,false);assert.deepEqual(stop.queue,[]);
});
test('imported taste is weak and resettable, related items rank across artists without becoming heard',()=>{
 const tracks=['a','b','c'].map((id,i)=>({id,title:id,artist:'Artist'+i,genre:i===0?'Rock':'Ambient',public:true,duration:180}));
 const taste={importedTrackIds:['b'],importedAt:'2026-10-13',automatic:true};
 assert.equal(rankRecommendations({tracks,taste})[0].id,'b');
 const disabled=rankRecommendations({tracks,taste:{...taste,automatic:false}});
 assert.deepEqual(disabled,rankRecommendations({tracks}));
 assert.deepEqual(rankRecommendations({tracks,taste:{...taste,learnedResetAt:'2026-10-14'}}),rankRecommendations({tracks}));
 assert.equal(rankRecommendations({tracks,seed:tracks[0],related:['c']})[0].id,'c');
 assert.equal(rankRecommendations({tracks,taste,mode:'discovery'}).length,3);
});
test('SoundCloud falls back between full encodings and rejects preview/foreign endpoints',async()=>{
 const client='a'.repeat(32),seen=[];
 const transcodings=[{url:'https://evil.example/aac',preset:'aac',format:{protocol:'hls'}},
  {url:'https://api-v2.soundcloud.com/preview',preset:'aac',snipped:true,format:{protocol:'hls'}},
  {url:'https://api-v2.soundcloud.com/aac',preset:'aac',format:{protocol:'hls'}},
  {url:'https://api-v2.soundcloud.com/mp3',preset:'mp3',format:{protocol:'progressive'}}];
 const adapter=soundcloudAdapter(null,async input=>{const url=new URL(input);seen.push(url.href);
  if(url.hostname==='soundcloud.com')return new Response(`<script>window.__sc_hydration = [{"hydratable":"apiClient","data":{"id":"${client}"}}];</script>`,{headers:{'Content-Type':'text/html'}});
  if(url.pathname==='/resolve')return Response.json({id:1,title:'Original',duration:100000,media:{transcodings},user:{username:'Artist'}});
  if(url.pathname==='/aac')return new Response(null,{status:403});
  return Response.json({url:'https://cf-media.sndcdn.com/original.mp3'});
 });
 const result=await adapter.metadata('https://soundcloud.com/artist/original');assert.equal(result.protocol,'https');
 assert(!seen.some(url=>url.includes('evil.example')||url.includes('/preview')));assert(seen.some(url=>url.includes('/mp3')));
});
test('connected import follows opaque SoundCloud cursors, merges likes once, seeds taste and guards account changes',async()=>{
 const directory=await fs.mkdtemp(path.join(config.root,'work/qa/refinement20-import-'));
 let repeated=false,calls=0;
 const service=await createApp({...config,env:'test',production:false,storage:'sqlite',objectStorage:'local',dataDir:directory,releasesDir:directory,emailVerify:false,turnstileSecret:'',smtp:'',soundcloudPublicSearch:false,soundcloud:{id:'fixture',secret:'fixture'},spotify:{id:'fixture',secret:'fixture'}},
 {log:pino({level:'silent'}),providerRemoteJson:async input=>{
   const url=new URL(input);calls++;
   if(url.pathname!=='/me/likes/tracks')throw Error('Unexpected provider path');
   const more=url.searchParams.get('cursor')==='opaque';
   const id=more?'2':'1';return {collection:[{track:{id,urn:'soundcloud:tracks:'+id,title:'Original '+id,genre:'Rock',user:{username:'Artist '+id},duration:180000,permalink_url:'https://soundcloud.com/artist/song-'+id}}],
     next_href:!more||repeated?'https://api.soundcloud.com/me/likes/tracks?cursor=opaque&limit=50':null};
 }});
 await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}/api`;
 const request=async(route,token,body,headers={})=>{const response=await fetch(base+route,{method:body?'POST':'GET',headers:{'X-GlukWave-Client':'native',...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{}),...headers},...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,data:await response.json()};};
 try{
  const account=(await request('/auth/register',null,{email:'refinement20@qa.test',username:'refinement20',password:'Fixture-password-2026'})).data;
  const uid=account.user.id;await service.ctx.store.update('users',uid,user=>({...user,plan:'beta'}));
  await service.ctx.store.put('connections',uid+':soundcloud',{id:uid+':soundcloud',userId:uid,provider:'soundcloud',token:seal({access_token:'fixture-token',expiresAt:Date.now()+3600000},config.encryptionKey)});
  const body={playlistId:'liked',destination:'likes',requestId:'refinement20-likes'};
  const first=await request('/integrations/soundcloud/import',account.token,body);
  assert.equal(first.status,201,JSON.stringify(first.data));assert.equal(first.data.imported,2);assert.equal(calls,2);
  const again=await request('/integrations/soundcloud/import',account.token,body);assert.equal(again.data.imported,2);assert.equal(calls,2,'Same intent returns original result without refetching');
  const library=await service.ctx.store.get('libraries',uid),taste=await service.ctx.store.get('taste',uid);
  assert.equal(library.likedIds.length,2);assert.deepEqual(library.history,[]);assert.equal(taste.importedTrackIds.length,2);
  const second=await request('/integrations/soundcloud/import',account.token,{...body,requestId:'refinement20-merge'});assert.equal(second.data.imported,0);assert.equal(second.data.deduplicated,2);
  const mismatch=await request('/integrations/soundcloud/import',account.token,body,{'X-GlukWave-Account':'other-user'});assert.equal(mismatch.data.error.code,'ACCOUNT_CHANGED');
  repeated=true;const broken=await request('/integrations/soundcloud/import',account.token,{playlistId:'liked',requestId:'refinement20-repeat'});assert.equal(broken.data.error.code,'INVALID_CURSOR');
  assert.equal((await service.ctx.store.list('playlists',value=>value.ownerId===uid)).length,0,'Failed pagination commits no playlist');
  const unknown=await request('/stream-audio/missing?grant=missing',account.token);assert.equal(unknown.data.error.code,'AUDIO_EXPIRED');
 }finally{await service.close();assert(directory.startsWith(path.join(config.root,'work/qa')+path.sep));await fs.rm(directory,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
});
