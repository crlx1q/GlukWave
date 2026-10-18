import test from 'node:test';
import assert from 'node:assert/strict';
import {rankRecommendations,genreKey} from '../src/recommendations.js';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {config} from '../src/config.js';
import {createApp} from '../src/app.js';
import {io} from 'socket.io-client';
import {initialState} from '../src/rooms.js';
const track=(id,artist,genre,extra={})=>({id,title:'Song '+id,artist,genre,tags:[],duration:180,public:true,...extra});
const candidates=[track('rock','Rocker','Rock'),track('quiet','Calm artist','Ambient'),track('dance','Dancer','Dance'),track('jazz','Jazz artist','Jazz')];
test('wave respects explicit genres and artists with a genuine empty cold start',()=>{
 assert.equal(genreKey('Русский рэп'),'hip hop');
 assert.equal(rankRecommendations({tracks:candidates,taste:{genres:['эмбиент']}})[0].id,'quiet');
 assert.equal(rankRecommendations({tracks:candidates,taste:{artists:[{name:'Jazz artist'}]}})[0].id,'jazz');
 assert.deepEqual(rankRecommendations({tracks:[]}),[]);
});
test('favorites and unfamiliar are distinct filters, not shuffled copies',()=>{
 const library={likedIds:['quiet'],history:[{trackId:'rock'}]},stats=[{trackId:'dance',plays:1,seconds:40}];
 assert.deepEqual(rankRecommendations({tracks:candidates,library,stats,mode:'favorites'}).map(item=>item.id),['quiet']);
 assert.deepEqual(rankRecommendations({tracks:candidates,library,stats,mode:'discovery'}).map(item=>item.id),['jazz']);
 assert.deepEqual(rankRecommendations({tracks:candidates,mode:'favorites'}),[]);
 const duplicates=[track('heard','Same','Pop',{title:'Original'}),track('other-platform','Same','Pop',{title:'Original Official Audio'}),track('remix','Same','Pop',{title:'Original Remix'})];
 assert.deepEqual(rankRecommendations({tracks:duplicates,library:{history:[{trackId:'heard'}]},mode:'discovery'}).map(item=>item.id),['remix']);
});
test('accepted listening and quick skips change ranking, while learning can be disabled',()=>{
 const tracks=[track('listen','Known artist','Rock'),track('skip','Skipped artist','Rock')];
 const stats=[{trackId:'listen',plays:2,seconds:350},{trackId:'skip',plays:2,seconds:4,skips:2}];
 assert.equal(rankRecommendations({tracks,stats})[0].id,'listen');
 assert.equal(rankRecommendations({tracks,stats,taste:{automatic:false,artists:[{name:'Skipped artist'}]}})[0].id,'skip');
});
test('seed similarity, mood and exclusion apply independently',()=>{
 const seed=track('seed','Calm artist','Ambient');
 assert.equal(rankRecommendations({tracks:[seed,...candidates],seed})[0].id,'quiet');
 assert.equal(rankRecommendations({tracks:candidates,mood:'energy'})[0].genre!=='Ambient',true);
 assert(['quiet','jazz'].includes(rankRecommendations({tracks:candidates,mood:'calm'})[0].id));
 assert(!rankRecommendations({tracks:candidates,exclude:['quiet','dance']}).some(item=>['quiet','dance'].includes(item.id)));
});
test('popular ranks actual platform activity, and diversity avoids artist runs and duplicate songs',()=>{
 assert.equal(rankRecommendations({tracks:candidates,mode:'popular',popularity:new Map([['jazz',100]])})[0].id,'jazz');
 const duplicates=[track('one','Same artist','Rock',{title:'Original'}),track('duplicate','Same artist','Rock',{title:'Original Official Audio'}),track('two','Same artist','Rock'),track('other','Different artist','Rock')];
 const result=rankRecommendations({tracks:duplicates,taste:{artists:[{name:'Same artist'}]}});
 assert.equal(result.length,3);
 assert.equal(result[1].artist,'Different artist');
});
test('real recommendation API persists genres, protects private seeds and rejects stale output controls',async()=>{
 const directory=await fs.mkdtemp(path.join(config.root,'work/qa/wave18-api-'));
 const service=await createApp({...config,env:'test',production:false,storage:'sqlite',objectStorage:'local',dataDir:directory,emailVerify:false,turnstileSecret:'',smtp:'',soundcloudPublicSearch:false,soundcloud:{id:'',secret:''},spotify:{id:'',secret:''},youtubeKey:'',discord:{id:'',secret:''}},{log:pino({level:'silent'})});
 await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}`;let socket;
 const request=async(url,token,body,method=body?'POST':'GET')=>{const response=await fetch(base+'/api'+url,{method,headers:{'X-GlukWave-Client':'native',...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,data:await response.json()};};
 try{
  const account=(await request('/auth/register',null,{email:'wave18@test.example',username:'wave18_listener',password:'Wave18-test-password'})).data;
  for(const item of candidates)await service.ctx.store.put('tracks',item.id,{...item,source:'local',uploadedBy:account.user.id,playback:{kind:'audio',url:'/api/media/'+item.id}});
  await service.ctx.store.put('tracks','hidden',{...track('hidden','Private','Ambient'),public:false,uploadedBy:'another-account',source:'local'});
  const taste=await request('/taste',account.token,{genres:['эмбиент','Ambient','Русский рэп']},'PUT');assert.equal(taste.status,200);assert.deepEqual(taste.data.taste.genres,['ambient','hip hop']);
  assert.equal((await request('/recommendations',account.token)).data.tracks[0].id,'quiet');
  assert(!(await request('/recommendations',account.token)).data.tracks.some(item=>item.id==='hidden'));
  assert.equal((await request('/recommendations?seedTrackId=hidden',account.token)).status,404);
  assert.equal((await request('/library/likes/quiet',account.token,{liked:true},'PUT')).status,200);
  assert.deepEqual((await request('/recommendations?mode=favorites',account.token)).data.tracks.map(item=>item.id),['quiet']);
  socket=io(base,{auth:{token:account.token,deviceId:'wave18-browser',surfaceId:'main',name:'Browser',kind:'web'},transports:['websocket'],reconnection:false});
  await new Promise((resolve,reject)=>{socket.once('connect',resolve);socket.once('connect_error',reject);});
  await socket.timeout(3000).emitWithAck('device:claim',{});
  const state={...initialState(),trackId:'quiet',queue:['quiet'],repeat:'one',waveMode:'discovery',waveMood:'calm',waveActive:true};
  const accepted=await socket.timeout(3000).emitWithAck('device:state',{...state,sequence:2,confirm:true,outputActive:true});assert.equal(accepted.connect.state.repeat,'one');assert.equal(accepted.connect.state.waveMode,'discovery');
  const stale=await socket.timeout(3000).emitWithAck('device:state',{...state,repeat:'off',sequence:1,outputActive:true});assert.equal(stale.stale,true);
  assert.equal((await request('/connect',account.token)).data.connect.state.repeat,'one');
  const requireTrack=service.ctx.requireTrack;let release,entered;
  const delayed=new Promise(resolve=>{entered=resolve;});
  service.ctx.requireTrack=async(id,user)=>{if(id==='rock'){entered();await new Promise(resolve=>{release=resolve;});}return requireTrack(id,user);};
  const earlier=socket.timeout(3000).emitWithAck('device:state',{...state,trackId:'rock',queue:['rock'],repeat:'off',sequence:3,outputActive:true});
  await delayed;
  const later=await socket.timeout(3000).emitWithAck('device:state',{...state,repeat:'all',sequence:4,confirm:true,outputActive:true});
  release();assert.equal((await earlier).stale,true);assert.equal(later.connect.state.repeat,'all');
  service.ctx.requireTrack=requireTrack;
  assert.equal((await request('/connect',account.token)).data.connect.state.repeat,'all');
  assert.equal((await request('/recommendations?mode=discovery&exclude=rock,dance,jazz',account.token)).data.tracks.length,0);
 }finally{socket?.disconnect();await service.close();await fs.rm(directory,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
});

test('saved track and artist exclusions apply before every mode and override likes',()=>{const taste={excludedTrackIds:['rock'],excludedArtistNames:['calm artist']};for(const mode of ['personal','favorites','discovery','popular']){const result=rankRecommendations({tracks:candidates,taste,mode,library:{likedIds:mode==='favorites'?['quiet','rock','jazz']:[]}});assert(!result.some(x=>['rock','quiet'].includes(x.id)));}});
