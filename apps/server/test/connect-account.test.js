import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {io} from 'socket.io-client';
import {createApp} from '../src/app.js';
import {config} from '../src/config.js';
import {initialState} from '../src/rooms.js';

test('account Connect mirrors a single output, retains tabs, revokes oldest devices and changes passwords safely',async()=>{
  const qa=path.join(config.root,'work/qa');await fs.mkdir(qa,{recursive:true});const directory=await fs.mkdtemp(path.join(qa,'connect-account-'));
  const service=await createApp({...config,env:'test',storage:'sqlite',objectStorage:'local',dataDir:directory,production:false,emailVerify:false,turnstileSecret:'',turnstileSiteKey:'',smtp:'',soundcloudPublicSearch:false},{log:pino({level:'silent'})});
  const sockets=[];
  try{
    await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}`;
    const request=async(route,token,body,method=body?'POST':'GET',deviceId)=>{const response=await fetch(base+'/api'+route,{method,headers:{...(token?{Authorization:`Bearer ${token}`}:{ }),...(body?{'Content-Type':'application/json'}:{}),'X-GlukWave-Client':'native',...(deviceId?{'X-GlukWave-Device':deviceId}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,data:await response.json()};};
    const password='Connect-password-2026',auth=(await request('/auth/register',null,{email:'connect@example.test',username:'connect_user',password},'POST','pc')).data;
    const ack=(socket,event,payload)=>socket.timeout(3000).emitWithAck(event,payload);
    const connect=async(token,did,surface)=>{const socket=io(base,{auth:{token,deviceId:did,surfaceId:surface,name:did,kind:'web'},transports:['websocket'],reconnection:false});sockets.push(socket);await new Promise((resolve,reject)=>{socket.once('connect',resolve);socket.once('connect_error',reject);});assert.equal((await ack(socket,'locale:change',{language:'en'})).ok,true);return socket;};
    let pc=await connect(auth.token,'pc','pc-one'),sibling=await connect(auth.token,'pc','pc-two');
    assert.equal((await request('/devices',auth.token)).data.devices.length,1);assert(pc.connected&&sibling.connected);
    const track={id:'connect-track',title:'Тест подключения',artist:'Артист',duration:300,source:'soundcloud',sourceId:'293',sourceUrl:'https://soundcloud.com/parser/track-293',artwork:'',album:'',public:true,playback:{kind:'soundcloud',offline:false}};await service.ctx.store.put('tracks',track.id,track);
    assert.equal((await ack(pc,'device:claim',{})).connect.independent,false);
    assert.equal((await ack(pc,'device:state',{...initialState(),trackId:track.id,queue:[track.id],position:42,playing:true,outputActive:true})).ok,true);
    sibling.disconnect();await new Promise(resolve=>setTimeout(resolve,40));assert.equal((await request('/connect',auth.token)).data.connect.state.playing,true);
    sibling=await connect(auth.token,'pc','pc-two');pc.disconnect();
    let disconnected;for(let attempt=0;attempt<30;attempt++){disconnected=(await request('/connect',auth.token)).data.connect;if(disconnected.activeDeviceId===null)break;await new Promise(resolve=>setTimeout(resolve,20));}
    assert.equal(disconnected.activeDeviceId,null);assert.equal(disconnected.state.playing,false);assert(sibling.connected);assert.equal((await request('/devices',auth.token)).data.devices[0].online,true);
    pc=await connect(auth.token,'pc','pc-one');await ack(pc,'device:claim',{});await ack(pc,'device:state',{...initialState(),trackId:track.id,queue:[track.id],position:42,playing:true,outputActive:true});
    const phoneAuth=(await request('/auth/login',null,{email:'@connect_user',password},'POST','phone')).data;assert(phoneAuth.token);
    const phone=await connect(phoneAuth.token,'phone','phone-one');let account=(await request('/connect',phoneAuth.token)).data.connect;
    assert.equal(account.activeDeviceId,'pc');assert.equal(account.activeSurfaceId,'pc-one');assert.equal(account.track.title,track.title);assert(account.state.position>=42);assert(account.state.playing);
    await ack(phone,'device:state',{...initialState(),outputActive:false});account=(await request('/connect',phoneAuth.token)).data.connect;assert.equal(account.state.trackId,track.id);assert.equal(account.activeDeviceId,'pc');
    const commands=[];let rejectTrack=false;pc.on('device:command',async(command,reply)=>{commands.push(command);reply({ok:true});});phone.on('device:command',(command,reply)=>{commands.push(command);reply(rejectTrack&&command.command==='track'?{error:{code:'PLAYBACK_FAILED',message:'Blocked playback'}}:{ok:true});});
    assert.equal((await request('/devices/command',phoneAuth.token,{deviceId:'pc',command:'seek',position:87})).status,200);assert.equal(commands.at(-1).position,87);
    assert.equal((await request('/devices/command',phoneAuth.token,{deviceId:'pc',surfaceId:'closed-tab',command:'play'})).status,409);
    rejectTrack=true;assert.equal((await request('/devices/command',phoneAuth.token,{deviceId:'phone',fromDeviceId:'pc',command:'transfer'})).status,409);assert.equal((await request('/connect',auth.token)).data.connect.activeDeviceId,'pc');assert.equal(commands.at(-1).command,'play');assert.equal(commands.at(-1).outputActive,true);rejectTrack=false;
    const transfer=await request('/devices/command',phoneAuth.token,{deviceId:'phone',fromDeviceId:'pc',command:'transfer'});assert.equal(transfer.status,200);account=(await request('/connect',auth.token)).data.connect;assert.equal(account.activeDeviceId,'phone');assert.equal(account.activeSurfaceId,'phone-one');assert(account.state.playing);assert.equal(commands.find(command=>command.outputActive===false).command,'pause');
    assert.equal((await request('/devices',auth.token)).data.devices.find(device=>device.id==='pc').state.playing,false);
    assert.equal((await request('/connect',phoneAuth.token,{independent:true},'PATCH')).data.connect.independent,true);
    assert.equal((await request('/connect',phoneAuth.token,{independent:false},'PATCH')).data.connect.independent,false);
    await Promise.all(['tablet','fourth'].map(async did=>{const session=(await request('/auth/login',null,{email:'connect_user',password},'POST',did)).data;await connect(session.token,did,did+'-one');}));
    assert.equal((await request('/auth/me',auth.token)).data.user,null);assert(!pc.connected&&!sibling.connected);
    const devices=(await request('/devices',phoneAuth.token)).data;assert.equal(devices.devices.length,3);assert.equal(devices.limit,3);assert(!devices.devices.some(device=>device.id==='pc'));
    assert.equal((await request('/devices/phone',phoneAuth.token,undefined,'DELETE')).status,200);assert.equal((await request('/auth/me',phoneAuth.token)).data.user,null);
    const fresh=(await request('/auth/login',null,{email:'connect@example.test',password},'POST','new')).data;
    const other=(await request('/auth/login',null,{email:'connect_user',password},'POST','other')).data;
    assert.equal((await request('/account/password',fresh.token,{currentPassword:'incorrect',password:'Next-password-2026'})).status,401);
    assert.equal((await request('/account/password',fresh.token,{currentPassword:password,password:'Next-password-2026'})).status,200);
    assert.equal((await request('/auth/me',other.token)).data.user,null);assert((await request('/auth/me',fresh.token)).data.user);
    assert.equal((await request('/auth/login',null,{email:'connect_user',password})).status,401);
    assert.equal((await request('/auth/login',null,{email:'connect_user',password:'Next-password-2026'})).status,200);
  }finally{for(const socket of sockets)socket.disconnect();await service.close();assert(directory.startsWith(qa+path.sep));await fs.rm(directory,{recursive:true,force:true,maxRetries:8,retryDelay:150});}
});
