import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {io} from 'socket.io-client';
import {createApp} from '../src/app.js';
import {config} from '../src/config.js';
import {initialState} from '../src/rooms.js';

test('independent device directory retains two tracks across alternating ticks, next, mirrors and refresh', async()=>{
  const qa=path.join(config.root,'work/qa'); await fs.mkdir(qa,{recursive:true});
  const directory=await fs.mkdtemp(path.join(qa,'independent23-'));
  const service=await createApp({...config,env:'test',storage:'sqlite',objectStorage:'local',dataDir:directory,production:false,emailVerify:false,turnstileSecret:'',turnstileSiteKey:'',smtp:'',soundcloudPublicSearch:false},{log:pino({level:'silent'})});
  const sockets=[];
  try {
    await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));
    const base=`http://127.0.0.1:${service.server.address().port}`;
    const request=async(route,token,body,deviceId,method=body?'POST':'GET')=>{
      const response=await fetch(base+'/api'+route,{method,headers:{'X-GlukWave-Client':'native',...(token?{Authorization:`Bearer ${token}`}:{ }),...(body?{'Content-Type':'application/json'}:{}),...(deviceId?{'X-GlukWave-Device':deviceId}:{})},...(body?{body:JSON.stringify(body)}:{})});
      assert(response.status===200||response.status===201); return response.json();
    };
    const auth=await request('/auth/register',null,{email:'independent23@example.test',username:'independent23',password:'Independent-password-23'},'pc');
    const phoneAuth=await request('/auth/login',null,{email:'independent23',password:'Independent-password-23'},'phone');
    const ack=(socket,event,payload)=>socket.timeout(3000).emitWithAck(event,payload);
    const connect=async(token,deviceId,surfaceId,name,kind)=>{
      const socket=io(base,{auth:{token,deviceId,surfaceId,name,kind},transports:['websocket'],reconnection:false}); sockets.push(socket);
      await new Promise((resolve,reject)=>{socket.once('connect',resolve);socket.once('connect_error',reject);});
      assert.equal((await ack(socket,'locale:change',{language:'en'})).ok,true); return socket;
    };
    const pc=await connect(auth.token,'pc','pc-output','Chrome · Windows','web');
    const phone=await connect(phoneAuth.token,'phone','phone-output','GlukWave · Android','android');
    for(const id of ['pc-song','phone-song','phone-next']) await service.ctx.store.put('tracks',id,{id,title:id,artist:'Test',duration:180,source:'soundcloud',sourceId:id,sourceUrl:`https://soundcloud.com/qa/${id}`,artwork:'',album:'',public:true,playback:{kind:'soundcloud',offline:false}});
    await request('/connect',auth.token,{independent:true},undefined,'PATCH');
    const tick=async(socket,id,position,outputActive=true)=>{
      const result=await ack(socket,'device:state',{...initialState(),trackId:id,queue:[id],position,playing:true,outputActive}); assert.equal(result.ok,true);
    };
    const expectRows=async(phoneSong)=>{
      const {devices}=await request('/devices',auth.token);
      assert.equal(devices.find(d=>d.id==='pc').track.id,'pc-song');
      assert.equal(devices.find(d=>d.id==='phone').track.id,phoneSong);
      assert(devices.every(d=>d.state.playing));
    };
    await tick(pc,'pc-song',20); await tick(phone,'phone-song',35); await expectRows('phone-song');
    for(let i=0;i<3;i++){await tick(pc,'pc-song',21+i);await expectRows('phone-song');await tick(phone,'phone-song',36+i);await expectRows('phone-song');}
    await tick(phone,'phone-next',0); await expectRows('phone-next');
    const snapshot=(await request('/connect',auth.token)).connect;
    assert.equal(snapshot.activeDeviceName,'GlukWave · Android'); assert.equal(snapshot.activeDeviceKind,'android');
    const mirror=await connect(auth.token,'pc','pc-mirror','Chrome · Windows','web');
    await tick(mirror,'phone-next',0,false); await expectRows('phone-next');
    await tick(pc,'pc-song',27); await expectRows('phone-next');
  } finally {
    for(const socket of sockets)socket.disconnect(); await service.close();
    assert(directory.startsWith(qa+path.sep)); await fs.rm(directory,{recursive:true,force:true,maxRetries:8,retryDelay:150});
  }
});
