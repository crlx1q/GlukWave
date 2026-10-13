import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {io} from 'socket.io-client';
import {createApp} from '../src/app.js';
import {config} from '../src/config.js';
import {initialState} from '../src/rooms.js';
import {containerCpuSample,readResourceLimits} from '../src/resources.js';

test('room directory reflects real listening, and moderators can join full private rooms without retaining privileges after demotion',async()=>{
 const qa=path.join(config.root,'work/qa'),directory=await fs.mkdtemp(path.join(qa,'moderation17-')),sockets=[];
 const service=await createApp({...config,env:'test',storage:'sqlite',objectStorage:'local',dataDir:directory,production:false,emailVerify:false,turnstileSecret:'',turnstileSiteKey:'',smtp:'',soundcloudPublicSearch:false},{log:pino({level:'silent'})});
 try{
  await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}`;
  const request=async(route,auth,body,method=body?'POST':'GET')=>{const response=await fetch(base+'/api'+route,{method,headers:{...(auth?{Authorization:`Bearer ${auth.token}`}:{ }),'X-GlukWave-Client':'native',...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,data:await response.json()};};
  const signup=async username=>(await request('/auth/register',null,{email:username+'@example.test',username,password:'Moderation-password-2026'})).data;
  const owner=await signup('roomhost'),admin=await signup('moderator'),viewer=await signup('roomviewer');await service.ctx.store.update('users',admin.user.id,user=>({...user,role:'admin'}));
  const publicRoom=(await request('/rooms',owner,{name:'Open listening',visibility:'public'})).data.room;
  const track={id:'directory-public',title:'Public song',artist:'Original artist',duration:200,source:'soundcloud',sourceId:'293',sourceUrl:'https://soundcloud.com/original/song',artwork:'',album:'',public:true,playback:{kind:'audio',url:'https://example.test/signed-secret',offline:false}};await service.ctx.store.put('tracks',track.id,track);
  const socket=io(base,{auth:{token:owner.token,deviceId:'pc',surfaceId:'pc-one',name:'Chrome · Windows',kind:'web'},transports:['websocket'],reconnection:false});sockets.push(socket);await new Promise((resolve,reject)=>{socket.once('connect',resolve);socket.once('connect_error',reject);});
  const ack=(event,payload)=>socket.timeout(4000).emitWithAck(event,payload);
  assert.equal((await ack('room:join',{roomId:publicRoom.id})).ok,true);await ack('room:command',{roomId:publicRoom.id,command:'track',trackId:track.id,queue:[track.id]});await ack('device:state',{...initialState(),trackId:track.id,queue:[track.id],playing:true,outputActive:true,roomId:publicRoom.id});
  let card=(await request('/rooms',viewer)).data.publicRooms[0];assert.equal(card.memberCount,1);assert.equal(card.onlineCount,1);assert.equal(card.listeningCount,1);assert.equal(card.currentTrack.title,track.title);assert.equal(card.members[0].playing,true);assert.equal(card.currentTrack.playback.url,undefined);assert.equal(card.members[0].devices,undefined);assert.equal(card.state,undefined);assert.equal(card.inviteCode,undefined);
  await ack('room:command',{roomId:publicRoom.id,command:'pause'});card=(await request('/rooms',viewer)).data.publicRooms[0];assert.equal(card.onlineCount,1);assert.equal(card.listeningCount,0);
  const joined=(await request('/rooms/join',viewer,{roomId:publicRoom.id})).data.room;assert.equal(joined.canControl,false);assert((await request('/rooms',viewer)).data.rooms.some(room=>room.id===publicRoom.id));assert.equal((await request('/rooms/'+publicRoom.id+'/command',viewer,{command:'shuffle',enabled:true})).status,403);
  await service.ctx.store.update('users',owner.user.id,user=>({...user,plan:'beta'}));const privateRoom=(await request('/rooms',owner,{name:'Full private',visibility:'private'})).data.room;
  await service.ctx.store.update('rooms',privateRoom.id,room=>({...room,members:[room.members[0],...Array.from({length:29},(_,i)=>({userId:'full-'+i,displayName:'Member',canControl:false,role:'member'}))]}));
  assert.equal((await request('/rooms/join',viewer,{roomId:privateRoom.id})).status,404);assert((await request('/rooms',admin)).data.moderationRooms.some(room=>room.id===privateRoom.id));
  assert.equal((await request('/rooms/'+privateRoom.id+'/command',admin,{command:'track',trackId:track.id})).status,200);
  assert.equal((await request('/rooms/join',admin,{roomId:privateRoom.id})).status,200);assert.equal((await request('/rooms/'+privateRoom.id+'/command',admin,{command:'repeat',repeat:'all'})).status,200);
  await service.ctx.store.update('users',admin.user.id,user=>({...user,role:'user'}));assert.equal((await request('/rooms/'+privateRoom.id+'/command',admin,{command:'pause'})).status,403);const demoted=(await request('/rooms/'+privateRoom.id,admin)).data.room;assert.equal(demoted.canControl,false);assert.equal(demoted.members.find(member=>member.userId===admin.user.id).canControl,false);assert.equal((await request('/rooms/'+privateRoom.id,admin,undefined,'DELETE')).status,403);
  await service.ctx.store.update('users',admin.user.id,user=>({...user,role:'admin'}));
  const jam=(await request('/jams',owner,{})).data.room;await service.ctx.store.update('rooms',jam.id,room=>({...room,members:[room.members[0],...Array.from({length:4},(_,i)=>({userId:'jam-'+i,displayName:'Friend',canControl:false,role:'member'}))]}));assert.equal((await request('/jams/'+jam.id+'/join',admin,{})).status,200);assert.equal((await request('/rooms/'+jam.id+'/command',admin,{command:'track',trackId:track.id})).status,200);assert.equal((await request('/rooms/'+jam.id,admin,undefined,'DELETE')).status,200);
  assert.equal((await request('/rooms/'+privateRoom.id,admin,undefined,'DELETE')).status,200);assert((await service.ctx.store.list('audit',event=>event.action==='admin.roomDelete')).length>=2);
 }finally{for(const socket of sockets)socket.disconnect();await service.close();assert(directory.startsWith(qa+path.sep));await fs.rm(directory,{recursive:true,force:true,maxRetries:8,retryDelay:150});}
});

test('service restart is owner-only, managed-only, single-flight and acknowledges before invoking the isolated callback',async()=>{
 const qa=path.join(config.root,'work/qa'),directory=await fs.mkdtemp(path.join(qa,'service17-'));let restarts=0;
 const service=await createApp({...config,env:'test',storage:'sqlite',objectStorage:'local',dataDir:directory,production:false,emailVerify:false,turnstileSecret:'',turnstileSiteKey:'',smtp:'',soundcloudPublicSearch:false,adminEmails:['owner17@example.test'],serviceRestartEnabled:true},{log:pino({level:'silent'}),restartService:()=>{restarts++;}});
 try{
  await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}`;
  const request=async(route,auth,body)=>{const response=await fetch(base+'/api'+route,{method:body?'POST':'GET',headers:{...(auth?{Authorization:`Bearer ${auth.token}`}:{ }),'X-GlukWave-Client':'native',...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,data:await response.json()};};
  const signup=async username=>(await request('/auth/register',null,{email:username+'@example.test',username,password:'Service-password-2026'})).data;
  const owner=await signup('owner17'),admin=await signup('admin17'),user=await signup('user17');await service.ctx.store.update('users',admin.user.id,user=>({...user,role:'admin'}));
  assert.equal((await request('/admin/service',user)).status,403);assert.equal((await request('/admin/service',admin)).data.service.canRestart,false);assert.equal((await request('/admin/service/restart',admin,{confirmation:'RESTART_GLUKWAVE'})).status,403);assert.equal((await request('/admin/service/restart',owner,{confirmation:'REBOOT_HOST'})).status,400);
  service.ctx.config.serviceRestartEnabled=false;assert.equal((await request('/admin/service/restart',owner,{confirmation:'RESTART_GLUKWAVE'})).status,409);assert.equal(restarts,0);service.ctx.config.serviceRestartEnabled=true;
  const result=await request('/admin/service/restart',owner,{confirmation:'RESTART_GLUKWAVE'});assert.equal(result.status,202);assert.equal(result.data.service.scope,'glukwave-service');await new Promise(resolve=>setImmediate(resolve));assert.equal(restarts,1);assert.equal((await request('/admin/service/restart',owner,{confirmation:'RESTART_GLUKWAVE'})).status,409);assert.equal(restarts,1);
  assert.equal((await service.ctx.store.list('audit',event=>event.action==='admin.serviceRestart')).length,1);const resources=(await request('/admin/resources',owner)).data;assert(Array.isArray(resources.history));assert(resources.history.length<=120);assert.equal(resources.resources.scope,'server-process');
 }finally{await service.close();assert(directory.startsWith(qa+path.sep));await fs.rm(directory,{recursive:true,force:true,maxRetries:8,retryDelay:150});}
});

test('aggregate cgroup CPU includes extractor workers and distinguishes unknown counters from idle',async()=>{
 const entries={'/sys/fs/cgroup/cpu.max':'100000 100000','/sys/fs/cgroup/memory.max':'4294967296','/sys/fs/cgroup/cpu.stat':'usage_usec 12000000\nuser_usec 9000000\nsystem_usec 3000000'};const limits=await readResourceLimits(async path=>{if(!(path in entries))throw Error('missing');return entries[path];});assert.equal(limits.containerCpuUsageMicros,12000000);assert.equal(containerCpuSample(7000000,12000000,5000),100);assert.equal(containerCpuSample(null,12000000,5000),null);assert.equal(containerCpuSample(12000000,12000000,5000),0);assert.equal(containerCpuSample(12000000,10,5000),null);
});
