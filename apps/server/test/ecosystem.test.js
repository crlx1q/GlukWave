import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {io} from 'socket.io-client';
import {config} from '../src/config.js';
import {createApp} from '../src/app.js';
import {initialState} from '../src/rooms.js';
import {oauthSettings,oauthCredentials,oauthReturnBase} from '../src/oauth-config.js';
import {providerConfiguration} from '../src/providers.js';

test('OAuth callbacks are exact, server-owned and separate YouTube search from account login',()=>{
  const base={...config,production:false,appUrl:'http://127.0.0.1:5173',oauthBaseUrl:'',google:{id:'google-test',secret:'test',redirectUri:'https://wave.gluk.tech/api/auth/google/callback'},youtubeOAuth:{id:'',secret:''},spotify:{id:'spotify-test',secret:'test'},youtubeKey:''};
  assert.equal(oauthSettings(base,'spotify').redirectUri,'http://127.0.0.1:5173/api/integrations/spotify/callback');
  assert.equal(oauthSettings({...base,appUrl:'http://localhost:5173'},'spotify').loginAvailable,false);
  assert.equal(oauthSettings({...base,appUrl:'http://192.168.3.7:4000'},'spotify').loginAvailable,false);
  const exact='https://wave.gluk.tech/api/integrations/spotify/callback';
  assert.equal(oauthSettings({...base,spotify:{...base.spotify,redirectUri:exact}},'spotify').redirectUri,exact);
  for(const suffix of ['?redirect=bad','#bad','/'])assert.equal(oauthSettings({...base,spotify:{...base.spotify,redirectUri:exact+suffix}},'spotify').loginAvailable,false);
  assert.equal(oauthCredentials(base,'youtube').id,'google-test');
  assert.equal(oauthSettings(base,'youtube').redirectUri,'http://127.0.0.1:5173/api/integrations/youtube/callback');
  const keyOnly={...base,google:{id:'',secret:''},youtubeKey:'search-test'};
  const source=providerConfiguration(keyOnly).find(value=>value.id==='youtube');assert.equal(source.searchAvailable,true);assert.equal(source.configured,false);
  const oauthOnly=providerConfiguration(base).find(value=>value.id==='youtube');assert.equal(oauthOnly.searchAvailable,false);assert.equal(oauthOnly.configured,true);
  assert.equal(oauthReturnBase({...base,origins:['http://127.0.0.1:5173']},{headers:{origin:'http://127.0.0.1:5173'}}),'http://127.0.0.1:5173');
  assert.equal(oauthReturnBase(base,{headers:{origin:'https://attacker.example',host:'attacker.example'}}),base.appUrl);
});

async function fixture(extra={},overrides={}){
  const qa=path.join(config.root,'work/qa');await fs.mkdir(qa,{recursive:true});const directory=await fs.mkdtemp(path.join(qa,'ecosystem-test-'));
  const service=await createApp({...config,env:'test',production:false,appUrl:'http://127.0.0.1:5177',storage:'sqlite',objectStorage:'local',dataDir:directory,emailVerify:false,turnstileSecret:'',turnstileSiteKey:'',smtp:'',soundcloudPublicSearch:false,google:{id:'',secret:''},youtubeOAuth:{id:'',secret:''},spotify:{id:'',secret:''},soundcloud:{id:'',secret:''},discord:{id:'',secret:''},youtubeKey:'',...extra},{log:pino({level:'silent'}),...overrides});
  await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}`,sockets=[];
  const request=async(route,token,body,method=body?'POST':'GET',deviceId)=>{const response=await fetch(base+'/api'+route,{method,headers:{'X-GlukWave-Client':'native',...(token?{Authorization:`Bearer ${token}`}:{ }),...(body?{'Content-Type':'application/json'}:{}),...(deviceId?{'X-GlukWave-Device':deviceId}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,data:await response.json()};};
  const ack=(socket,event,payload)=>socket.timeout(5000).emitWithAck(event,payload);
  const connect=async(token,did,surface,kind='web')=>{const socket=io(base,{auth:{token,deviceId:did,surfaceId:surface,name:did,kind},transports:['websocket'],reconnection:false});sockets.push(socket);await new Promise((resolve,reject)=>{socket.once('connect',resolve);socket.once('connect_error',reject);});assert.equal((await ack(socket,'locale:change',{language:'en'})).ok,true);return socket;};
  return {service,base,request,ack,connect,async close(){for(const socket of sockets)socket.disconnect();await service.close();assert(directory.startsWith(qa+path.sep));await fs.rm(directory,{recursive:true,force:true,maxRetries:5,retryDelay:100});}};
}

test('room listening has one account output, deduplicated tabs, accurate transfer, room cleanup and real session revocation',async()=>{
  const f=await fixture();try{
    const {service,request,ack,connect}=f,password='Ecosystem-session-test-2026';
    const owner=(await request('/auth/register',null,{email:'ecosystem-owner@example.test',username:'ecosystem_owner',password},'POST','browser')).data;
    await service.ctx.store.update('users',owner.user.id,value=>({...value,plan:'beta'}));
    const phoneAuth=(await request('/auth/login',null,{email:'ecosystem_owner',password},'POST','phone')).data;
    const pc=await connect(owner.token,'browser','tab-a'),tab=await connect(owner.token,'browser','tab-b'),phone=await connect(phoneAuth.token,'phone','phone-a','android');
    const commands=[];let rejectTarget=false;for(const socket of [pc,tab,phone])socket.on('device:command',async(command,reply)=>{commands.push({surface:socket.auth.surfaceId,...command});if(socket===phone&&command.command==='track'&&command.roomId)assert.equal((await ack(phone,'room:join',{roomId:command.roomId,adoptOnly:true})).ok,true);reply(rejectTarget&&socket===phone&&command.command==='track'?{error:{code:'PLAYBACK_FAILED',message:'Test player rejected'}}:{ok:true});});
    const track={id:'ecosystem-real-state',title:'State verification',artist:'QA',duration:100,public:false,uploadedBy:owner.user.id,source:'local',sourceId:'state',playback:{kind:'audio',url:'/unused',offline:false}};await service.ctx.store.put('tracks',track.id,track);
    const room=(await request('/rooms',owner.token,{name:'Ecosystem QA'})).data.room;
    assert.equal((await ack(pc,'room:join',{roomId:room.id})).connect.activeSurfaceId,'tab-a');
    const started=await ack(pc,'room:command',{roomId:room.id,command:'track',trackId:track.id,queue:[track.id]});assert.equal(started.ok,true,JSON.stringify(started));await ack(pc,'room:command',{roomId:room.id,command:'seek',position:25});
    const mirror=await ack(phone,'room:join',{roomId:room.id});assert.equal(mirror.connect.activeDeviceId,'browser');assert.equal(mirror.connect.roomId,room.id);assert.equal(mirror.connect.state.trackId,track.id);assert(mirror.connect.state.position>=25);
    await ack(tab,'room:join',{roomId:room.id,adoptOnly:true});
    await ack(pc,'device:state',{...initialState(),trackId:track.id,queue:[track.id],playing:true,position:25,roomId:room.id,outputActive:true});
    await ack(tab,'device:state',{...initialState(),roomId:room.id,outputActive:false});
    const devices=(await request('/devices',owner.token)).data.devices;assert.equal(devices.length,2);assert.equal(devices.find(d=>d.id==='browser').state.trackId,track.id);assert.equal(devices.find(d=>d.id==='browser').surfaceCount,2);
    const members=(await request('/rooms/'+room.id,owner.token)).data.room.members;assert.equal(members[0].devices.length,2);assert.equal(members[0].devices.filter(d=>d.outputActive).length,1);
    const originalUpdate=service.ctx.store.update;let heartbeatWrites=0;service.ctx.store.update=async(...args)=>{if(['connect','devices'].includes(args[0]))heartbeatWrites++;return originalUpdate(...args);};
    for(let tick=0;tick<12;tick++)await ack(pc,'device:state',{...initialState(),trackId:track.id,queue:[track.id],playing:true,position:25,roomId:room.id,outputActive:true});
    assert.equal(heartbeatWrites,0,'Routine room ticks neither rewrite output nor broadcast queue metadata');service.ctx.store.update=originalUpdate;
    rejectTarget=true;assert.equal((await request('/devices/command',owner.token,{deviceId:'phone',surfaceId:'phone-a',command:'transfer'})).status,409);assert.equal((await request('/connect',owner.token)).data.connect.activeSurfaceId,'tab-a');rejectTarget=false;
    const revision=(await request('/rooms/'+room.id,owner.token)).data.room.state.revision;
    assert.equal((await request('/devices/command',owner.token,{deviceId:'phone',surfaceId:'phone-a',command:'transfer'})).status,200);
    const transferred=(await request('/connect',phoneAuth.token)).data.connect;assert.equal(transferred.roomId,room.id);assert.equal(transferred.activeDeviceId,'phone');assert.equal(transferred.state.trackId,track.id);assert.equal((await request('/rooms/'+room.id,owner.token)).data.room.state.revision,revision);assert(commands.some(c=>c.surface==='phone-a'&&c.command==='track'&&c.roomId===room.id));
    assert.equal((await ack(phone,'room:leave',{roomId:room.id})).connect.roomId,null);assert.equal((await request('/connect',owner.token)).data.connect.roomId,null);assert((await request('/devices',owner.token)).data.devices.every(d=>d.roomId===null));
    const sessions=(await request('/account/sessions',owner.token)).data;assert.equal(sessions.sessions.length,2);assert.equal(sessions.sessions.filter(s=>s.current).length,1);assert.equal(sessions.sessions.find(s=>s.deviceId==='phone').kind,'android');assert(!JSON.stringify(sessions).includes(phoneAuth.token));
    const foreign=(await request('/auth/register',null,{email:'ecosystem-foreign@example.test',username:'ecosystem_foreign',password},'POST','foreign')).data;
    assert.equal((await request('/account/sessions/'+sessions.sessions.find(s=>!s.current).id,foreign.token,undefined,'DELETE')).status,404);
    assert.equal((await request('/account/sessions',owner.token,undefined,'DELETE')).status,200);assert.equal((await request('/auth/me',phoneAuth.token)).data.user,null);assert(!phone.connected);assert(pc.connected&&tab.connected);
    await assert.rejects(connect(owner.token,'stolen-installation','stolen-tab'),error=>error.data?.code==='AUTH_REQUIRED');
  }finally{await f.close();}
});

test('a late transfer ACK from an expired target session cannot acquire output ownership',async()=>{
  const f=await fixture();try{
    const password='Ecosystem-expiry-test-2026',owner=(await f.request('/auth/register',null,{email:'transfer-expiry@example.test',username:'transfer_expiry',password},'POST','source')).data;
    const targetAuth=(await f.request('/auth/login',null,{email:'transfer_expiry',password},'POST','target')).data;
    const source=await f.connect(owner.token,'source','source-surface'),target=await f.connect(targetAuth.token,'target','target-surface','android');
    const targetSession=(await f.request('/account/sessions',targetAuth.token)).data.currentSessionId;
    const track={id:'expiry-track',title:'Expiry test',artist:'QA',duration:100,public:false,uploadedBy:owner.user.id,source:'local',sourceId:'expiry',playback:{kind:'audio',url:'/unused',offline:false}};
    await f.service.ctx.store.put('tracks',track.id,track);
    source.on('device:command',(_command,reply)=>reply({ok:true}));
    target.on('device:command',async(command,reply)=>{if(command.command==='track')await f.service.ctx.store.update('sessions',targetSession,value=>({...value,expiresAt:Date.now()-1}));reply({ok:true});});
    await f.ack(source,'device:claim',{});await f.ack(source,'device:state',{...initialState(),trackId:track.id,queue:[track.id],playing:true,position:17,outputActive:true});
    const transfer=await f.request('/devices/command',owner.token,{deviceId:'target',command:'transfer'});
    assert.equal(transfer.status,401);assert.equal(transfer.data.error.code,'AUTH_REQUIRED');
    const current=(await f.request('/connect',owner.token)).data.connect;assert.equal(current.activeDeviceId,'source');assert.equal(current.state.trackId,track.id);assert.equal(current.state.playing,true);
    assert.equal((await f.request('/auth/me',targetAuth.token)).data.user,null);
  }finally{await f.close();}
});

test('own-device room controls cannot bypass listener permissions and volume stays local',async()=>{
  const f=await fixture();try{
    const password='Ecosystem-rights-test-2026',owner=(await f.request('/auth/register',null,{email:'room-rights-owner@example.test',username:'room_rights_owner',password},'POST','owner')).data;
    const listener=(await f.request('/auth/register',null,{email:'room-rights-listener@example.test',username:'room_rights_listener',password},'POST','listener')).data;
    const ownerSocket=await f.connect(owner.token,'owner','owner-surface'),listenerSocket=await f.connect(listener.token,'listener','listener-surface','android'),commands=[];
    ownerSocket.on('device:command',(_command,reply)=>reply({ok:true}));listenerSocket.on('device:command',(command,reply)=>{commands.push(command);reply({ok:true});});
    const room=(await f.request('/rooms',owner.token,{name:'Rights QA',visibility:'public'})).data.room;
    assert.equal((await f.request('/rooms/join',listener.token,{roomId:room.id})).status,200);
    await f.ack(ownerSocket,'room:join',{roomId:room.id});await f.ack(listenerSocket,'room:join',{roomId:room.id});
    const revision=(await f.request('/rooms/'+room.id,owner.token)).data.room.state.revision;
    const pause=await f.request('/devices/command',listener.token,{deviceId:'listener',command:'pause'});assert.equal(pause.status,403);
    assert.equal(commands.length,0);assert.equal((await f.request('/devices/command',listener.token,{deviceId:'listener',command:'volume',volume:0.23})).status,200);
    assert.equal(commands.length,1);assert.equal(commands[0].localOnly,true);assert.equal(commands[0].roomId,room.id);assert.equal(commands[0].volume,0.23);
    assert.equal((await f.request('/rooms/'+room.id,owner.token)).data.room.state.revision,revision);
  }finally{await f.close();}
});

test('OAuth browser state, exact redirect/token exchange, replay and revoked originating session are enforced',async()=>{
  const calls=[],f=await fixture({adminEmails:['oauth-owner@example.test'],spotify:{id:'test-client-id',secret:'test-client-secret',redirectUri:'https://wave.gluk.tech/api/integrations/spotify/callback'},google:{id:'test-google',secret:'test-google-secret'}},{providerRemoteJson:async(url,options)=>{calls.push({url:String(url),body:options?.body?.toString()});if(String(url).endsWith('/api/token'))return {access_token:'test-provider-access',refresh_token:'test-provider-refresh',expires_in:3600};if(String(url).endsWith('/v1/me'))return {id:'test-provider-user',display_name:'QA linked account'};throw new Error('Unexpected provider request');}});
  try{
    const auth=(await f.request('/auth/register',null,{email:'oauth-owner@example.test',username:'oauth_owner',password:'Ecosystem-oauth-test-2026'},'POST','oauth-web')).data;
    const start=await fetch(f.base+'/api/integrations/spotify/connect',{method:'POST',headers:{Authorization:`Bearer ${auth.token}`,'Content-Type':'application/json'},body:'{}'}),data=await start.json(),authorization=new URL(data.url),cookie=start.headers.getSetCookie()[0].split(';')[0];
    assert(cookie.startsWith('gw_oauth_spotify='));assert.equal(authorization.searchParams.get('redirect_uri'),'https://wave.gluk.tech/api/integrations/spotify/callback');assert.equal(authorization.searchParams.get('code_challenge_method'),'S256');
    const callback=`${f.base}/api/integrations/spotify/callback?${new URLSearchParams({state:authorization.searchParams.get('state'),code:'test-provider-code'})}`;
    const noCookie=await fetch(callback,{redirect:'manual'});assert(noCookie.headers.get('location').includes('integration_error=OAUTH_STATE'));assert.equal(calls.length,0);
    const complete=await fetch(callback,{headers:{Cookie:cookie},redirect:'manual'});assert(complete.headers.get('location').includes('/app/?connected=spotify#settings?section=connections'));assert.equal(new URLSearchParams(calls[0].body).get('redirect_uri'),authorization.searchParams.get('redirect_uri'));assert.equal((await f.request('/integrations',auth.token)).data.connections.find(c=>c.provider==='spotify').connected,true);
    const replay=await fetch(callback,{headers:{Cookie:cookie},redirect:'manual'});assert(replay.headers.get('location').includes('integration_error=OAUTH_STATE'));assert.equal(calls.length,2);
    const next=(await f.request('/integrations/spotify/connect',auth.token,{})).data.url,state=new URL(next).searchParams.get('state');await f.request('/auth/logout',auth.token,{});
    const revoked=await fetch(`${f.base}/api/integrations/spotify/callback?${new URLSearchParams({state,code:'test-late-code'})}`,{redirect:'manual'});assert(revoked.headers.get('location').includes('integration_error='));assert.equal(calls.length,2);
    const newAuth=(await f.request('/auth/login',null,{email:'oauth_owner',password:'Ecosystem-oauth-test-2026'},'POST','oauth-web')).data;
    const diagnostics=(await f.request('/admin/integrations/diagnostics',newAuth.token)).data;assert.equal(diagnostics.providers.find(p=>p.id==='spotify').redirectUri,authorization.searchParams.get('redirect_uri'));assert(!JSON.stringify(diagnostics).includes('test-client-secret'));
  }finally{await f.close();}
});

