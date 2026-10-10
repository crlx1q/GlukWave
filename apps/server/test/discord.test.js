import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {io} from 'socket.io-client';
import {config} from '../src/config.js';
import {createApp} from '../src/app.js';
import {seal,unseal} from '../src/util.js';
import {discordActivity,discordScopes} from '../src/discord-presence.js';
import {initialState} from '../src/rooms.js';

async function fixture(opts={}){
 const qa=path.join(config.root,'work/qa'),directory=await fs.mkdtemp(path.join(qa,'discord-test-')),calls=[],sockets=[];
 let time=Date.now(),failure=null,tokenFailure=null,hold=null,identity='12345678901234567';
 const fake=async(url,options={})=>{
  const body=options.body instanceof URLSearchParams?Object.fromEntries(options.body):options.body?JSON.parse(options.body):null;
  calls.push({url,method:options.method||'GET',authorization:options.headers?.Authorization,body});
  if(hold)await hold;
  if(failure&&url.includes('headless-sessions'))return new Response(JSON.stringify(failure.body||{}),{status:failure.status});
  if(url.endsWith('/oauth2/token'))return tokenFailure?new Response(JSON.stringify(tokenFailure.body),{status:tokenFailure.status}):new Response(JSON.stringify({access_token:'oauth-access-refreshed',refresh_token:'oauth-refresh-rotated',expires_in:3600,scope:discordScopes}));
  if(url.endsWith('/oauth2/token/revoke'))return new Response(null,{status:204});
  if(url.endsWith('/headless-sessions/delete'))return new Response(null,{status:204});
  return new Response(JSON.stringify({token:'headless-session-secret'}));
 };
 const service=await createApp({...config,env:'test',production:false,storage:'sqlite',objectStorage:'local',dataDir:directory,releasesDir:directory,emailVerify:false,turnstileSecret:'',turnstileSiteKey:'',smtp:'',adminEmails:['admin@example.test'],soundcloudPublicSearch:false,google:{id:'',secret:''},spotify:{id:'',secret:''},youtubeOAuth:{id:'',secret:''},soundcloud:{id:'',secret:''},discord:{id:'22222222222222222',secret:'qa-discord-client-secret'},youtubeKey:'',stripe:{secret:'',webhook:'',price:''},appUrl:'https://wave.example.test'},
  {log:pino({level:'silent'}),discordFetch:fake,discordOptions:{clock:()=>time,scheduler:false,minInterval:12000,...(opts.discordOptions||{})},providerRemoteJson:async(url,options)=>{if(url==='https://discord.com/api/users/@me')return {id:identity,username:'discord_listener',global_name:'Discord Listener',avatar:'a_picture'};throw new Error('Unexpected provider '+url);}});
 await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}`;
 const request=async(route,auth,body,method=body?'POST':'GET')=>{const response=await fetch(base+'/api'+route,{method,redirect:'manual',headers:{'X-GlukWave-Client':'native',...(auth?{Authorization:'Bearer '+auth.token}:{}),...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,location:response.headers.get('location'),data:response.headers.get('content-type')?.includes('json')?await response.json():null};};
 const register=async username=>{const r=await request('/auth/register',null,{email:username+'@example.test',username,password:'Discord-private-QA-test-2026'});assert.equal(r.status,201);return r.data;};
 const paid=async auth=>{await service.ctx.store.update('users',auth.user.id,u=>({...u,plan:'beta'}));};
 const linked=async(auth,extra={})=>{const record={id:auth.user.id+':discord',userId:auth.user.id,provider:'discord',providerUserId:identity,username:'listener',displayName:'A listener',avatarUrl:'https://cdn.discordapp.com/embed/avatars/1.png',scope:discordScopes,token:seal({access_token:'oauth-access',refresh_token:'oauth-refresh',scope:discordScopes,expiresAt:time+3600000},config.encryptionKey),...extra};await service.ctx.discordReplaceConnection(auth.user.id,record);};
 const connect=async(auth,kind='web')=>{const socket=io(base,{auth:{token:auth.token,deviceId:auth.user.id+'-'+kind,surfaceId:'main',name:'QA '+kind,kind},transports:['websocket'],reconnection:false});sockets.push(socket);await new Promise((resolve,reject)=>{socket.once('connect',resolve);socket.once('connect_error',reject);});assert((await socket.timeout(3000).emitWithAck('locale:change',{language:'en'})).ok);socket.on('device:command',(command,ack)=>ack({ok:true}));return socket;};
 const track=async(id='track',changes={})=>{const t={id,title:'Трек '+id,artist:'Artist',album:'Album',artwork:'https://images.example.test/cover.png',duration:180,source:'soundcloud',sourceUrl:'https://soundcloud.com/qa/'+id,public:true,createdAt:new Date().toISOString(),playback:{kind:'soundcloud',url:'https://soundcloud.com/qa/'+id},...changes};await service.ctx.store.put('tracks',id,t);return t;};
 const play=async(socket,changes={})=>{assert((await socket.timeout(3000).emitWithAck('device:state',{...initialState(),trackId:'track',queue:['track'],playing:true,position:25,outputActive:true,...changes})).ok);await service.ctx.discordSync(socket.auth.token===undefined?'':(await service.ctx.authenticate(socket.auth.token)).user.id);};
 return {service,calls,request,register,paid,linked,connect,track,play,base,advance:ms=>{time+=ms;},failure:value=>{failure=value;},tokenFailure:value=>{tokenFailure=value;},identity:value=>{identity=value;},hold:promise=>{hold=promise;},async close(){hold=null;failure=null;tokenFailure=null;for(const socket of sockets)socket.disconnect();await service.close();assert(directory.startsWith(qa+path.sep));await fs.rm(directory,{recursive:true,force:true,maxRetries:5,retryDelay:100});}};
}

test('Discord activity is OAuth headless Listening with real metadata, two URLs and progress',()=>{
 const activity=discordActivity({title:'Monster',artist:'Skillet',album:'Awake',position:25,duration:178,cover:'https://images.example/awake.png',trackUrl:'https://wave.example/app/?track=one',joinUrl:'https://wave.example/app/?listen=host'},config,1000000);
 assert.equal(activity.type,2);assert.equal(activity.name,'Gluk Wave');assert.equal(activity.details,'Monster');assert.deepEqual(activity.timestamps,{start:'975000',end:'1153000'});assert.equal(activity.buttons.length,2);assert.deepEqual(activity.metadata.button_urls,activity.buttons.map(b=>b.url));
 assert.equal(discordActivity({title:'x',artist:'a',position:0,duration:0,cover:'http://127.0.0.1/private',trackUrl:'https://wave.example/app/?track=x'},config,1000).assets.large_image,undefined);
 const single=discordActivity({title:'Alone',artist:'Alan Walker',album:'',cover:'https://images.example/alone.png',trackUrl:'https://wave.example/app/?track=alone'},config,1000);
 assert.equal(single.assets.large_text,undefined);
 const logoFallback=discordActivity({title:'x',artist:'a',trackUrl:'https://wave.example/app/?track=x'},{...config,appUrl:'https://wave.example.test',discord:{...config.discord,logoAsset:'logo'}},1000);
 assert.equal(logoFallback.assets.small_image,'https://wave.example.test/brand/logo.png');
 const withoutLogo=discordActivity({title:'x',artist:'a',position:0,duration:0,trackUrl:'https://wave.example/app/?track=x'},{...config,appUrl:'http://127.0.0.1:4000',discord:{...config.discord,logoAsset:''}},1000);
 assert.equal(withoutLogo.assets.small_image,undefined);assert.equal(withoutLogo.state,'∿ a');
 const idle=discordActivity({idle:true},config,1000);
 assert.equal(idle.type,2);assert.equal(idle.details,'В приложении');assert.equal(idle.state,'На главной');
 assert.equal(idle.buttons[0].label,'Открыть в Wave');
});

test('Free cannot start OAuth, opt in through either settings endpoint or join host presence',async()=>{const f=await fixture();try{
 const free=await f.register('free');assert.equal((await f.request('/integrations/discord/connect',free,{})).status,403);
 assert.equal((await f.request('/discord',free,{enabled:true},'PATCH')).status,403);assert.equal((await f.request('/settings',free,{discordPresence:true},'PATCH')).status,403);
 assert.equal((await f.request('/discord',free)).data.status,'locked');assert.equal(f.calls.length,0);
}finally{await f.close();}});

test('OAuth uses PKCE and one-use session-bound state, stores identity and encrypted tokens, disallows duplicate link',async()=>{const f=await fixture();try{
 const user=await f.register('oauth');await f.paid(user);const start=await f.request('/integrations/discord/connect',user,{});assert.equal(start.status,200);const auth=new URL(start.data.url);assert.equal(auth.searchParams.get('scope'),discordScopes);assert.equal(auth.searchParams.get('code_challenge_method'),'S256');
 const callback='/integrations/discord/callback?'+new URLSearchParams({state:auth.searchParams.get('state'),code:'discord-approved-code'}),result=await f.request(callback);assert.equal(result.status,302);assert.match(result.location,/connected=discord/);
 const status=(await f.request('/discord',user)).data;assert.equal(status.identity.username,'discord_listener');assert.equal(status.identity.displayName,'Discord Listener');assert.match(status.identity.avatarUrl,/a_picture.gif/);assert.equal(status.needsReconnect,false);assert(!JSON.stringify(status).includes('oauth-access'));
 const record=await f.service.ctx.store.get('connections',user.user.id+':discord');assert(!record.token.includes('oauth-access'));assert.equal(unseal(record.token,config.encryptionKey).access_token,'oauth-access-refreshed');
 assert(f.calls.find(c=>c.url.endsWith('/oauth2/token')).body.code_verifier);assert.match((await f.request(callback)).location,/OAUTH_STATE/);
 const other=await f.register('other');await f.paid(other);await assert.rejects(()=>f.linked(other),error=>error.code==='DISCORD_ALREADY_LINKED');
}finally{await f.close();}});

test('Canonical output publishes once, coalesces seeks, clears pause and resumes without client Discord',async()=>{const f=await fixture();try{
 const user=await f.register('output');await f.paid(user);await f.linked(user);await f.track();const socket=await f.connect(user);await f.play(socket);
 let writes=f.calls.filter(c=>c.url.endsWith('/headless-sessions'));assert.equal(writes.length,1);assert.equal(writes[0].authorization,'Bearer oauth-access');assert.equal(writes[0].body.activities[0].details,'Трек track');
 assert.equal((await f.request('/discord',user)).data.status,'active');await f.play(socket,{position:80});assert.equal(f.calls.filter(c=>c.url.endsWith('/headless-sessions')).length,1);
 f.advance(13000);await f.service.ctx.discordSync(user.user.id);writes=f.calls.filter(c=>c.url.endsWith('/headless-sessions'));assert.equal(writes.length,2);assert.equal(writes[1].body.token,'headless-session-secret');
 await f.play(socket,{position:80,playing:false});assert(f.calls.some(c=>c.url.endsWith('/headless-sessions/delete')));assert.equal((await f.request('/discord',user)).data.status,'idle');
 f.advance(13000);await f.play(socket,{position:85});assert.equal((await f.request('/discord',user)).data.status,'active');
 const record=await f.service.ctx.store.get('connections',user.user.id+':discord');assert(record.headlessToken&&!record.headlessToken.includes('headless-session-secret'));
}finally{await f.close();}});

test('Refresh rotates encrypted OAuth token and revoke/unlink cannot be resurrected by pending publish',async()=>{const f=await fixture();try{
 const user=await f.register('refresh');await f.paid(user);await f.linked(user,{token:seal({access_token:'expired',refresh_token:'refresh',expiresAt:0},config.encryptionKey)});await f.track();const socket=await f.connect(user);await f.play(socket);assert(f.calls.some(c=>c.url.endsWith('/oauth2/token')&&c.body.grant_type==='refresh_token'));
 let resolve;const deferred=new Promise(r=>{resolve=r;});f.hold(deferred);f.advance(26000);const pending=f.service.ctx.discordSync(user.user.id);await new Promise(r=>setTimeout(r,20));const unlink=f.request('/integrations/discord',user,null,'DELETE');resolve();await pending;assert.equal((await unlink).status,200);assert.equal(await f.service.ctx.store.get('connections',user.user.id+':discord'),null);assert(f.calls.some(c=>c.url.endsWith('/oauth2/token/revoke')));
 assert.equal((await f.service.ctx.store.list('discordCleanup')).length,0);assert.equal((await f.service.ctx.store.list('connections')).length,0);
}finally{await f.close();}});

test('Rate limits back off, invalid grants require reconnect, and old identify grants cannot publish',async()=>{const f=await fixture();try{
 const user=await f.register('limits');await f.paid(user);await f.linked(user,{scope:'identify'});await f.track();const socket=await f.connect(user);await f.play(socket);assert.equal((await f.request('/discord',user)).data.status,'reconnect_required');assert.equal(f.calls.length,0);
 await f.linked(user);f.failure({status:429,body:{retry_after:45}});await f.service.ctx.discordSync(user.user.id);const count=f.calls.length;assert.equal((await f.request('/discord',user)).data.status,'retrying');f.advance(30000);await f.service.ctx.discordSync(user.user.id);assert.equal(f.calls.length,count);f.advance(16000);f.failure(null);await f.service.ctx.discordSync(user.user.id);assert.equal((await f.request('/discord',user)).data.status,'active');
 f.tokenFailure({status:400,body:{error:'invalid_grant'}});await f.service.ctx.store.update('connections',user.user.id+':discord',r=>({...r,token:seal({access_token:'expired',refresh_token:'revoked',expiresAt:0},config.encryptionKey)}));f.advance(26000);await f.service.ctx.discordSync(user.user.id);assert.equal((await f.request('/discord',user)).data.status,'reconnect_required');const attempts=f.calls.length;await f.play(socket,{position:90});assert.equal(f.calls.length,attempts);
}finally{await f.close();}});

test('Only the selected output wins across controllers; independent mode does not publish two activities',async()=>{const f=await fixture();try{
 const user=await f.register('devices');await f.paid(user);await f.linked(user);await f.track();await f.track('phone');const web=await f.connect(user,'web');await f.play(web);const second=await f.request('/auth/login',null,{email:'devices',password:'Discord-private-QA-test-2026'});assert.equal(second.status,200);const phone=await f.connect(second.data,'android');
 await f.play(phone,{trackId:'phone',queue:['phone'],outputActive:false,playing:false});assert.equal((await f.request('/discord',user)).data.activity.trackId,'track');
 assert.equal((await f.request('/connect',user,{independent:true},'PATCH')).status,200);f.advance(13000);await f.play(phone,{trackId:'phone',queue:['phone'],position:30});assert.equal((await f.request('/discord',user)).data.activity.trackId,'phone');
 assert.equal(f.calls.filter(c=>c.url.endsWith('/headless-sessions')).at(-1).body.activities.length,1);await f.service.ctx.store.update('users',user.user.id,u=>({...u,plan:'free'}));f.service.ctx.discordPlaybackChanged(user.user.id);await f.service.ctx.discordSync(user.user.id);assert.equal((await f.request('/discord',user)).data.status,'locked');assert(f.calls.some(c=>c.url.endsWith('/headless-sessions/delete')));
 assert.equal((await f.request('/integrations/discord',user,null,'DELETE')).status,200);
}finally{await f.close();}});

test('Failed unlink cleanup persists encrypted, retries after restart-style tick, never resurrects a connection',async()=>{const f=await fixture();try{
 const user=await f.register('cleanup');await f.paid(user);await f.linked(user);await f.track();const socket=await f.connect(user);await f.play(socket);f.failure({status:503});assert.equal((await f.request('/integrations/discord',user,null,'DELETE')).status,200);
 const cleanup=await f.service.ctx.store.list('discordCleanup');assert.equal(cleanup.length,1);assert(!JSON.stringify(cleanup).includes('oauth-access'));assert(!JSON.stringify(cleanup).includes(user.user.id));assert.equal((await f.request('/discord',user)).data.connected,false);
 f.failure(null);f.advance(61000);await f.service.ctx.discordTick();assert.equal((await f.service.ctx.store.list('discordCleanup')).length,0);assert.equal((await f.service.ctx.store.list('connections')).length,0);
}finally{await f.close();}});

test('Selected-device session expiry and plan downgrade clear the server activity',async()=>{const f=await fixture();try{
 const user=await f.register('expired');await f.paid(user);await f.linked(user);await f.track();const socket=await f.connect(user);await f.play(socket);
 const sessions=await f.service.ctx.store.list('sessions',s=>s.userId===user.user.id);await f.service.ctx.store.update('sessions',sessions[0].id,s=>({...s,expiresAt:Date.now()-1}));f.advance(26000);await f.service.ctx.discordSync(user.user.id);assert(f.calls.some(c=>c.url.endsWith('/headless-sessions/delete')));
 await f.service.ctx.store.update('users',user.user.id,u=>({...u,plan:'free'}));assert.equal((await f.service.ctx.discordStatus(user.user.id)).status,'locked');
}finally{await f.close();}});

test('Listen together defaults on but still requires friends and live host; opt-out keeps ordinary Jam permissions',async()=>{const f=await fixture();try{
 const host=await f.register('host'),guest=await f.register('guest');await f.paid(host);await f.linked(host);await f.track();const socket=await f.connect(host);await f.play(socket);const url='/discord/listen/'+host.user.id;
 const status=(await f.request('/discord',host)).data;assert.equal(status.allowJoin,true);assert(status.activity.joinUrl);
 assert.equal((await f.request(url,guest,{})).status,404);
 const request=await f.request('/friends/requests',guest,{userId:host.user.id});assert.equal((await f.request('/friends/requests/'+request.data.request.id,host,{accept:true},'PUT')).status,200);
 const ready=await f.request(url,guest,{});assert.equal(ready.status,200);assert.equal(ready.data.room.type,'jam');assert.equal((await f.request('/connect',host)).data.connect.roomId,ready.data.room.id);assert.equal(ready.data.room.state.trackId,'track');
 assert(ready.data.room.members.some(member=>member.userId===guest.user.id));const guestSocket=await f.connect(guest);assert((await guestSocket.timeout(3000).emitWithAck('room:join',{roomId:ready.data.room.id})).ok);
 assert.equal((await f.request('/jams/'+ready.data.room.id+'/join',guest,{})).status,200);
 await f.request('/discord',host,{allowJoin:false},'PATCH');assert.equal((await f.request(url,guest,{})).status,404);assert.equal((await f.request('/discord',host)).data.activity.joinUrl,null);
}finally{await f.close();}});

test('Discord join default handles missing preference without overwriting a saved opt-out on relink',async()=>{const f=await fixture();try{
 const user=await f.register('joinpref');await f.paid(user);await f.linked(user);
 assert.equal((await f.request('/discord',user)).data.allowJoin,true);
 await f.request('/discord',user,{allowJoin:false},'PATCH');await f.linked(user);
 assert.equal((await f.request('/discord',user)).data.allowJoin,false);
 f.identity('23456789012345678');await f.linked(user);
 assert.equal((await f.request('/discord',user)).data.allowJoin,false);
 await f.service.ctx.store.update('connections',user.user.id+':discord',record=>{const {allowJoin,...legacy}=record;return legacy;});
 assert.equal((await f.request('/discord',user)).data.allowJoin,true);
}finally{await f.close();}});

test('Device state reports detected track duration and publishes end timestamp to Discord',async()=>{const f=await fixture();try{
 const user=await f.register('ytuser');await f.paid(user);await f.linked(user);
 await f.track('yt-1',{duration:0,source:'youtube'});
 const socket=await f.connect(user);
 await socket.timeout(3000).emitWithAck('device:state',{...initialState(),trackId:'yt-1',queue:['yt-1'],playing:true,position:10,duration:240,outputActive:true});
 await f.service.ctx.discordSync(user.user.id);
 const stored=await f.service.ctx.store.get('tracks','yt-1');
 assert.equal(stored.duration,240);
 const publishCalls=f.calls.filter(c=>c.url.endsWith('/headless-sessions'));
 assert(publishCalls.length>0);
 const act=publishCalls.at(-1).body.activities[0];
 assert.ok(act.timestamps.end);
}finally{await f.close();}});

test('Idle presence displays in-app status when track is not playing and clears on disconnect',async()=>{const f=await fixture({discordOptions:{idlePresence:true}});try{
 const user=await f.register('idleuser');await f.paid(user);await f.linked(user);
 const socket=await f.connect(user);
 await f.service.ctx.discordSync(user.user.id);
 let writes=f.calls.filter(c=>c.url.endsWith('/headless-sessions'));
 assert.equal(writes.length,1);
 assert.equal(writes[0].body.activities[0].details,'В приложении');
 assert.equal(writes[0].body.activities[0].state,'На главной');
 f.advance(13000);
 await f.track();await f.play(socket);
 writes=f.calls.filter(c=>c.url.endsWith('/headless-sessions'));
 assert.equal(writes.length,2);
 assert.equal(writes[1].body.activities[0].details,'Трек track');
 f.advance(13000);
 await f.play(socket,{playing:false});
 writes=f.calls.filter(c=>c.url.endsWith('/headless-sessions'));
 assert.equal(writes.length,3);
 assert.equal(writes[2].body.activities[0].details,'В приложении');
 assert.equal(writes[2].body.activities[0].state,'На главной');
 socket.disconnect();
 await new Promise(r=>setTimeout(r,50));
 f.advance(13000);
 await f.service.ctx.discordSync(user.user.id);
 assert(f.calls.some(c=>c.url.endsWith('/headless-sessions/delete')));
}finally{await f.close();}});
