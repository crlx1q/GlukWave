import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {io} from 'socket.io-client';
import {config} from '../src/config.js';
import {createApp} from '../src/app.js';
import {initialState,applyTrackEnded} from '../src/rooms.js';

test('end notifications consume only the expected track/revision; repeat and final stop stay shared',()=>{
  const state={...initialState(),trackId:'a',queue:['a','b','c'],playing:true,position:29,updatedAt:1000,revision:7};
  const ended={command:'ended',trackId:'a',expectedRevision:7,repeat:'off'};
  assert.equal(applyTrackEnded(state,ended,30,1000).trackId,'b');
  const next=applyTrackEnded(state,ended,30,1000);assert.equal(next.revision,8);
  assert.deepEqual(applyTrackEnded(next,ended,30,1000),next);
  assert.deepEqual(applyTrackEnded({...state,position:1},ended,30,1000),{...state,position:1});
  const repeated=applyTrackEnded(state,{...ended,repeat:'one'},30,1000);assert.equal(repeated.trackId,'a');assert.equal(repeated.position,0);assert.equal(repeated.revision,8);
  const final={...state,trackId:'c'},stopped=applyTrackEnded(final,{...ended,trackId:'c'},30,1000);assert.equal(stopped.playing,false);assert.equal(stopped.position,30);
  assert.equal(applyTrackEnded(final,{...ended,trackId:'c',repeat:'all'},30,1000).trackId,'a');
});

test('real sockets keep two playback surfaces online, reconnect at live position and deduplicate concurrent room endings',async()=>{
  const qa=path.resolve(config.root,'work/qa');await fs.mkdir(qa,{recursive:true});const directory=await fs.mkdtemp(path.join(qa,'playback-sync-'));
  const service=await createApp({...config,env:'test',production:false,storage:'sqlite',dataDir:directory,turnstileSecret:'',turnstileSiteKey:'',smtp:'',emailVerify:false,objectStorage:'local',soundcloudPublicSearch:false},{log:pino({level:'silent'})});
  const sockets=[];
  try{
    await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}`;
    async function request(route,token,body,method=body?'POST':'GET'){const response=await fetch(base+'/api'+route,{method,headers:{'Content-Type':'application/json','X-GlukWave-Client':'native',...(token?{Authorization:`Bearer ${token}`}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,data:await response.json()};}
    const auth=(await request('/auth/register',null,{email:'sync@example.test',username:'sync_qa',password:'local-sync-test-passphrase'})).data;
    const other=(await request('/auth/register',null,{email:'listener@example.test',username:'listener_qa',password:'local-sync-test-passphrase'})).data;
    async function connect(token,deviceId){const socket=io(base,{auth:{token,deviceId,name:deviceId,kind:'web'},transports:['websocket'],reconnection:false});sockets.push(socket);await new Promise((resolve,reject)=>{socket.once('connect',resolve);socket.once('connect_error',reject);});return socket;}
    const a=await connect(auth.token,'tab-one'),b=await connect(auth.token,'tab-two');
    const ack=(socket,event,payload)=>socket.timeout(3000).emitWithAck(event,payload);
    await ack(a,'device:state',initialState());await ack(b,'device:state',initialState());
    const devices=(await request('/devices',auth.token)).data.devices;assert.equal(devices.filter(device=>device.online).length,2);assert(a.connected&&b.connected);
    const commandsA=[],commandsB=[];a.on('device:command',(command,ack)=>{commandsA.push(command);ack({ok:true});});b.on('device:command',(command,ack)=>{commandsB.push(command);ack({ok:true});});
    const room=(await request('/rooms',auth.token,{name:'Sync verification'})).data.room;
    await request('/rooms/join',other.token,{inviteCode:room.inviteCode});
    const c=await connect(other.token,'listener-tab');await ack(c,'room:join',{roomId:room.id});
    const tracks=['qa-first','qa-second','qa-third'];for(const id of tracks)await service.ctx.store.create('tracks',id,{id,title:id,artist:'QA',album:'',artwork:'',duration:30,public:false,uploadedBy:auth.user.id,source:'local',sourceId:id,playback:{kind:'audio',url:'/unused',offline:false}});
    const started=await ack(a,'room:command',{roomId:room.id,command:'track',trackId:tracks[0],queue:tracks});assert.equal(started.ok,true,JSON.stringify(started));let state=started.state;
    const denied=await ack(c,'room:command',{roomId:room.id,command:'ended',trackId:tracks[0],expectedRevision:state.revision});assert.equal(denied.error.code,'ROOM_PERMISSION');
    const settings=await request('/settings',auth.token,{equalizer:{enabled:true,bands:[5,4,3,1,0,0,0,0,-1,-1]},playbackRate:1.25},'PATCH');assert.equal(settings.status,200);
    const preamp=await request('/settings',auth.token,{equalizer:{preamp:-5}},'PATCH');assert.equal(preamp.data.settings.equalizer.enabled,true);assert.equal(preamp.data.settings.equalizer.bands[0],5);assert.equal(preamp.data.settings.playbackRate,1.25);
    for(const equalizer of [{bands:[1]},{preamp:13},{bands:Array(10).fill(NaN)}])assert.equal((await request('/settings',auth.token,{equalizer},'PATCH')).status,400);
    assert.equal((await request('/settings',auth.token,{playbackRate:3},'PATCH')).status,400);
    const oled=await request('/settings',auth.token,{theme:'amoled',appearance:{amoled:{accent:'#91d2b6'}}},'PATCH');assert.equal(oled.status,200);assert.equal(oled.data.settings.appearance.amoled.bg,'#000000');
    const oledBackground=await request('/settings',auth.token,{appearance:{amoled:{surface:'#101010'}}},'PATCH');assert.equal(oledBackground.data.settings.appearance.amoled.accent,'#91d2b6');assert.equal(oledBackground.data.settings.appearance.dark.bg,'#141517');assert.equal(oledBackground.data.settings.theme,'amoled');
    state=(await ack(a,'room:command',{roomId:room.id,command:'seek',position:29})).state;
    const command={roomId:room.id,command:'ended',trackId:tracks[0],expectedRevision:state.revision,repeat:'off'};
    const endings=await Promise.all([ack(a,'room:command',command),ack(b,'room:command',command)]);assert(endings.every(result=>result.ok));assert(endings.every(result=>result.state.trackId===tracks[1]));assert(endings.every(result=>result.state.revision===state.revision+1));
    state=(await request('/rooms/'+room.id,auth.token)).data.room.state;
    const fresh=await ack(b,'room:join',{roomId:room.id});assert.equal(fresh.room.state.revision,state.revision);assert.equal(fresh.room.state.trackId,tracks[1]);assert(fresh.room.state.updatedAt>=state.updatedAt);
    const permission=await request(`/rooms/${room.id}/members/${other.user.id}`,auth.token,{canControl:true},'PATCH');assert.equal(permission.data.room.state.revision,state.revision);assert.equal(permission.data.room.state.trackId,tracks[1]);
    await ack(a,'device:state',{...state,position:4,playing:true,updatedAt:Date.now()});
    const transferred=await request('/devices/command',auth.token,{deviceId:'tab-two',fromDeviceId:'tab-one',command:'transfer'});assert.equal(transferred.status,200);
    assert.equal(commandsA.at(-1).command,'pause');assert.equal(commandsA.at(-1).localOnly,true);assert.equal(commandsA.at(-1).outputActive,false);
    assert.equal(commandsB.at(-1).trackId,tracks[1]);assert.equal(commandsB.at(-1).localOnly,true);assert.equal(commandsB.at(-1).outputActive,true);
    assert.equal((await request('/rooms/'+room.id,auth.token)).data.room.state.revision,state.revision);
    const incomplete=await ack(a,'room:command',{roomId:room.id,command:'ended',trackId:tracks[1]});assert.equal(incomplete.error.code,'VALIDATION');
  }finally{for(const socket of sockets)socket.disconnect();await service.close();assert(directory.startsWith(qa+path.sep));await fs.rm(directory,{recursive:true,force:true});}
});
