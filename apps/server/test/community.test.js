import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {io} from 'socket.io-client';
import {config} from '../src/config.js';
import {createApp} from '../src/app.js';
import {initialState} from '../src/rooms.js';
const password='Parity-actual-account-test-2026';
async function fixture(){
 const qa=path.join(config.root,'work/qa'),directory=await fs.mkdtemp(path.join(qa,'parity-server-'));
 const service=await createApp({...config,env:'test',production:false,storage:'sqlite',objectStorage:'local',dataDir:directory,releasesDir:directory,emailVerify:false,turnstileSecret:'',turnstileSiteKey:'',smtp:'',adminEmails:['owner@example.test'],soundcloudPublicSearch:false,google:{id:'',secret:''},spotify:{id:'',secret:''},youtubeOAuth:{id:'',secret:''},soundcloud:{id:'',secret:''},discord:{id:'',secret:''},youtubeKey:'',stripe:{secret:'',webhook:'',price:''}},{log:pino({level:'silent'})});
 await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}`,sockets=[];
 const request=async(route,auth,body,method=body?'POST':'GET')=>{const multipart=body instanceof FormData,response=await fetch(base+'/api'+route,{method,headers:{'X-GlukWave-Client':'native',...(auth?{Authorization:'Bearer '+auth.token}:{}),...(body&&!multipart?{'Content-Type':'application/json'}:{})},...(body?{body:multipart?body:JSON.stringify(body)}:{})});return {status:response.status,data:response.headers.get('content-type')?.includes('json')?await response.json():await response.arrayBuffer()};};
 const register=async username=>{const result=await request('/auth/register',null,{email:username+'@example.test',username,password});assert.equal(result.status,201);return result.data;};
 const connect=async auth=>{const socket=io(base,{auth:{token:auth.token,deviceId:auth.user.id,surfaceId:'main',name:auth.user.username,kind:'web'},transports:['websocket'],reconnection:false});sockets.push(socket);await new Promise((resolve,reject)=>{socket.once('connect',resolve);socket.once('connect_error',reject);});assert((await socket.timeout(3000).emitWithAck('locale:change',{language:'en'})).ok);socket.on('device:command',(command,ack)=>ack({ok:true}));return socket;};
 return {service,directory,request,register,connect,async close(){for(const socket of sockets)socket.disconnect();await service.close();assert(directory.startsWith(qa+path.sep));await fs.rm(directory,{recursive:true,force:true,maxRetries:5,retryDelay:100});}};
}
async function track(f,id='one',extra={}){const value={id,title:'Тёплый вечер '+id,artist:'Actual catalogue artist',album:'',artwork:'https://images.example.test/'+id+'.png',duration:120,source:'soundcloud',sourceUrl:'https://soundcloud.com/qa/'+id,public:true,playback:{kind:'soundcloud',url:'https://soundcloud.com/qa/'+id},createdAt:new Date().toISOString(),genre:'Ambient',...extra};await f.service.ctx.store.create('tracks',id,value);return value;}

test('taste uses known artists, resumes across sessions and recommendations follow real listening',async()=>{const f=await fixture();try{
 const a=await f.register('taste_user'),t=await track(f),artists=await f.request('/artists?source=local',a);assert.deepEqual(artists.data.artists,[]);
 const actual=await f.request('/artists?q='+encodeURIComponent('Actual'),a);assert.equal(actual.data.artists.length,1);assert(actual.data.genres.includes('Ambient'));
 assert.equal((await f.request('/taste',a,{artists:[{id:'invented',name:'Fake',source:'local'}]},'PUT')).status,400);
 const saved=await f.request('/taste',a,{artists:actual.data.artists,onboardingStep:2},'PUT');assert.equal(saved.data.taste.onboardingCompleted,false);
 const second=(await f.request('/auth/login',null,{email:'taste_user',password})).data;assert.equal((await f.request('/taste',second)).data.taste.onboardingStep,2);
 assert.equal((await f.request('/recommendations',a)).data.reason,'taste');assert.equal((await f.request('/recommendations',a)).data.tracks[0].id,t.id);
 const observe=f.service.ctx.observeListening,state={...initialState(),trackId:t.id,playing:true};observe(a.user.id,'output',state,100000);observe(a.user.id,'output',{...state,position:10},110000);observe(a.user.id,'output',{...state,position:100},111000);observe(a.user.id,'mirror',{...state,position:101},112000);observe(a.user.id,'mirror',{...state,position:103},114000);observe(a.user.id,'mirror',{...state,position:103,playing:false},115000);
 const stats=(await f.request('/account/stats',a)).data.stats;assert.equal(stats.plays,1);assert.equal(stats.listeningSeconds,12);assert.equal(stats.topArtists[0].name,t.artist);
 assert.equal((await f.request('/profile/'+a.user.id)).data.stats,null);await f.request('/account/privacy',a,{profileStats:true},'PATCH');assert.equal((await f.request('/profile/'+a.user.id)).data.stats.listeningSeconds,12);
 await track(f,'private-artist',{source:'local',public:false,uploadedBy:a.user.id,artist:'My private session'});const hidden=(await f.request('/artists?q='+encodeURIComponent('My private'),a)).data.artists[0];assert(hidden);assert.equal((await f.request('/artists/'+hidden.id)).status,404);
 const skipped=await track(f,'skipped',{artist:'Skipped artist'});observe(a.user.id,'mirror',{...state,trackId:skipped.id,position:0},116000);observe(a.user.id,'mirror',{...state,trackId:skipped.id,position:4},120000);observe(a.user.id,'mirror',{...state,position:0},121000);await f.service.ctx.flushListening();assert.equal((await f.service.ctx.store.get('listeningStats',a.user.id+':skipped')).skips,1);
 assert.equal((await f.request('/taste',a)).data.learnedArtists.length,1);assert.equal((await f.request('/taste/learned',a,null,'DELETE')).data.learnedArtists.length,0);
 }finally{await f.close();}});

test('friends are recipient-bound, jams are hidden and listener pause never changes host transport',async()=>{const f=await fixture();try{
 const host=await f.register('jam_host'),guest=await f.register('jam_guest'),stranger=await f.register('jam_stranger'),t=await track(f);
 const request=(await f.request('/friends/requests',host,{userId:guest.user.id})).data.request;
 assert.equal((await f.request('/friends/requests/'+request.id,stranger,{accept:true},'PUT')).status,404);
 assert.equal((await f.request('/friends/requests/'+request.id,guest,{accept:true},'PUT')).status,200);
 assert.equal((await f.request('/friends',host)).data.friends[0].user.email,undefined);
 const h=await f.connect(host),g=await f.connect(guest),ack=(s,event,data)=>s.timeout(3000).emitWithAck(event,data),state={...initialState(),trackId:t.id,queue:[t.id],playing:true,outputActive:true};
 assert((await ack(h,'device:state',state)).ok);assert.equal((await f.request('/account/stats',host)).data.stats.plays,1);const jam=(await f.request('/jams',host,{})).data.room;
 assert.equal((await f.request('/jams/'+jam.id+'/join',stranger,{})).status,404);
 assert.equal((await f.request('/rooms',host)).data.rooms.length,0);assert.equal((await f.request('/rooms/join',guest,{roomId:jam.id})).status,404);
 await f.request('/jams/'+jam.id+'/join',guest,{});assert((await ack(h,'room:join',{roomId:jam.id})).ok);assert((await ack(g,'room:join',{roomId:jam.id})).ok);
 assert.equal((await f.request('/rooms/'+jam.id+'/members/'+guest.user.id,host,{canControl:true},'PATCH')).status,403);
 const paused=await f.request('/jams/'+jam.id+'/pause',guest,{paused:true});assert.equal(paused.status,200);assert.equal(paused.data.connect.jamPaused,true);assert.equal(paused.data.connect.state.playing,false);
 assert.equal((await f.service.ctx.store.get('rooms',jam.id)).state.playing,true);assert.equal((await f.request('/connect',host)).data.connect.state.playing,true);
 assert.equal((await f.request('/friends',guest)).data.friends[0].activity.jamId,jam.id);
 await f.request('/account/privacy',host,{showActivity:false},'PATCH');assert.equal((await f.request('/friends',guest)).data.friends[0].activity,undefined);
 await f.request('/rooms/'+jam.id+'/leave',host,{});assert.equal(await f.service.ctx.store.get('rooms',jam.id),null);assert.equal((await f.request('/connect',guest)).data.connect.roomId,null);
 }finally{await f.close();}});

test('public playlist validation, collage, paid imports and uploaded-cover replacement clean actual assets',async()=>{const f=await fixture();try{
 const a=await f.register('playlist_user'),b=await f.register('playlist_other'),one=await track(f,'one'),two=await track(f,'two');await track(f,'private',{public:false,uploadedBy:a.user.id});
 assert.equal((await f.request('/playlists',a,{name:'Private leak',public:true,trackIds:['private']})).status,403);
 const p=(await f.request('/playlists',a,{name:'Actual public playlist',public:true,trackIds:[one.id,two.id]})).data.playlist;assert.equal(p.artwork,'');assert.equal(p.coverArtworks.length,2);
 assert.equal((await f.request('/playlists/'+p.id)).data.tracks.length,2);assert.equal((await f.request('/playlists/discover?q=Actual')).data.playlists.length,1);
 assert.equal((await f.request('/playlists/'+p.id,a,{trackIds:['private']},'PATCH')).status,403);
 assert.equal((await f.request('/integrations/import-file',a,new FormData())).status,403);assert.equal((await f.request('/integrations/spotify/import',a,{playlistId:'x'})).status,403);
 assert.equal((await f.request('/settings',a,{theme:'amoled',fontScale:1.2,appearance:{dark:{accent:'#112233'}}},'PATCH')).status,200);
 assert.equal((await f.request('/settings',a,{appearance:{radius:12}},'PATCH')).status,403);
 const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==','base64');
 const image=()=>{const form=new FormData();form.append('file',new Blob([png],{type:'image/png'}),'cover.png');return form;};
 assert.equal((await f.request('/playlists/'+p.id+'/cover',b,image())).status,404);
 const first=(await f.request('/playlists/'+p.id+'/cover',a,image())).data.playlist;assert(first.artwork.startsWith('/api/profile-assets/'));await f.request('/playlists/'+p.id+'/cover',a,image());assert.equal(await f.service.ctx.store.get('assets',first.artwork.split('/').at(-1)),null);
 assert.equal((await f.service.ctx.store.list('assets')).length,1);await f.request('/playlists/'+p.id+'/cover',a,null,'DELETE');assert.equal((await f.service.ctx.store.list('assets')).length,0);
 await f.request('/playlists/'+p.id,a,{public:false},'PATCH');assert.equal((await f.request('/playlists/'+p.id,b)).status,404);
 }finally{await f.close();}});

test('email confirmation is one-use and account purge, bans, registration and release upload enforce authority',async()=>{const f=await fixture();try{
 const owner=await f.register('owner'),a=await f.register('account_user'),b=await f.register('account_other');
 assert.equal((await f.request('/account/email',a,{email:'changed@example.test',currentPassword:'wrong'})).status,401);
 await f.request('/account/email',a,{email:'changed@example.test',currentPassword:password});const mails=await fs.readdir(path.join(f.directory,'mailbox'));const mail=JSON.parse(await fs.readFile(path.join(f.directory,'mailbox',mails.at(-1)),'utf8')),token=new URL(mail.text.split('\n')[0].split(' ').at(-1)).searchParams.get('emailConfirm');
 assert.equal((await f.request('/account/email/confirm',b,{token})).status,400);assert.equal((await f.request('/account/email/confirm',a,{token})).status,200);assert.equal((await f.request('/account/email/confirm',a,{token})).status,400);
 const old=(await f.request('/auth/login',null,{email:'account_other',password})).data;await f.request('/admin/users/'+b.user.id,owner,{blocked:true},'PATCH');await f.request('/admin/users/'+b.user.id,owner,{blocked:false},'PATCH');assert.equal((await f.request('/account/privacy',old)).status,401);
 await f.request('/admin/users/'+b.user.id,owner,{role:'admin'},'PATCH');const delegated=(await f.request('/auth/login',null,{email:'account_other',password})).data;
 assert.equal((await f.request('/admin/users/'+owner.user.id,delegated,{blocked:true},'PATCH')).status,403);assert.equal((await f.request('/admin/users/'+owner.user.id,delegated,{confirmation:owner.user.username},'DELETE')).status,403);
 assert.equal((await f.request('/admin/registration',a,{enabled:false},'PATCH')).status,403);await f.request('/admin/registration',owner,{enabled:false},'PATCH');assert.equal((await f.request('/config')).data.registration.enabled,false);assert.equal((await f.request('/auth/register',null,{email:'closed@example.test',username:'closed_user',password})).status,403);
 const bad=new FormData();bad.append('file',new Blob([Buffer.alloc(1500)]),'bad.exe');bad.append('version','1.0.0+6');bad.append('channel','beta');bad.append('signature','debug');assert.equal((await f.request('/admin/releases/windows',owner,bad)).status,415);
 const pe=Buffer.alloc(1500);pe.write('MZ');pe.writeUInt32LE(128,0x3c);pe.write('PE\0\0',128);const form=new FormData();form.append('file',new Blob([pe]),'qa.exe');form.append('version','1.0.0+6');form.append('channel','beta');form.append('signature','debug');const release=await f.request('/admin/releases/windows',owner,form);assert.equal(release.status,201);assert.equal(release.data.release.bytes,1500);assert.equal((await f.request('/downloads/windows')).data.byteLength,1500);
 await track(f,'owned',{public:false,uploadedBy:a.user.id});await f.request('/playlists',a,{name:'To delete',trackIds:['owned']});
 assert.equal((await f.request('/account',a,{currentPassword:password,confirmation:'wrong'},'DELETE')).status,400);
 assert.equal((await f.request('/account',a,{currentPassword:password,confirmation:a.user.username},'DELETE')).status,200);assert.equal(await f.service.ctx.store.get('users',a.user.id),null);assert.equal(await f.service.ctx.store.get('tracks','owned'),null);assert.equal((await f.request('/account/stats',a)).status,401);assert.equal((await f.service.ctx.store.list('playlists',value=>value.ownerId===a.user.id)).length,0);assert(await f.service.ctx.store.get('users',owner.user.id));
 }finally{await f.close();}});

test('media cleanup preserves failed deletes and still clears later assets',async()=>{const f=await fixture();try{
 const media=path.join(f.directory,'media','images');await fs.mkdir(path.join(media,'busy'),{recursive:true});await fs.writeFile(path.join(media,'ready.png'),'qa-own-data');
 for(const [id,key] of [['busy','images/busy'],['ready','images/ready.png']]){await f.service.ctx.store.put('assets',id,{id,key,ownerId:'qa'});await f.service.ctx.store.put('mediaCleanup',id,{id,key,ownerId:'qa'});}
 await f.service.ctx.retryMediaCleanup();assert(await f.service.ctx.store.get('mediaCleanup','busy'));assert(await f.service.ctx.store.get('assets','busy'));assert.equal(await f.service.ctx.store.get('mediaCleanup','ready'),null);assert.equal(await f.service.ctx.store.get('assets','ready'),null);
 await fs.rmdir(path.join(media,'busy'));await fs.writeFile(path.join(media,'busy'),'qa-own-data');await f.service.ctx.retryMediaCleanup();assert.equal((await f.service.ctx.store.list('mediaCleanup')).length,0);assert.equal((await f.service.ctx.store.list('assets')).length,0);
 }finally{await f.close();}});

test('deleting a playing own track publishes the cleared account transport',async()=>{const f=await fixture();try{
 const a=await f.register('delete_playing'),t=await track(f,'playing-own',{public:false,uploadedBy:a.user.id}),s=await f.connect(a);
 assert((await s.timeout(3000).emitWithAck('device:state',{...initialState(),trackId:t.id,queue:[t.id],playing:true,outputActive:true})).ok);
 const cleared=new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('Cleared transport was not broadcast')),3000);s.on('account:state',value=>{if(value.state.trackId===null){clearTimeout(timer);resolve(value);}});});
 assert.equal((await f.request('/tracks/'+t.id,a,null,'DELETE')).status,200);const next=await cleared;assert.equal(next.state.playing,false);assert.deepEqual(next.state.queue,[]);assert.equal(next.track,null);
 }finally{await f.close();}});
