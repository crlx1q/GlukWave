import {z} from 'zod';
import {asyncRoute,fail,id,now,parse,seal,unseal,mergeSettings} from './util.js';
import {planLimits} from './plans.js';
import {oauthSettings} from './oauth-config.js';

// OAuth-authorized headless transport. Discord does not publish a stable REST
// contract for this endpoint: keep it isolated from playback and account auth.
export const discordScopes='openid sdk.social_layer_presence';
const api='https://discord.com/api/v10';
const hasPresence=record=>String(record?.scope||'').split(/\s+/).some(s=>['sdk.social_layer_presence','activities.write'].includes(s));
const eligible=user=>!!user&&!user.blocked&&planLimits(user).discordPresence;
// New links share invitations by default. Preserve every saved opt-out.
const joinAllowed=record=>!!record&&record.allowJoin!==false;
const safeImage=(value,base=null)=>{if(!value)return null;try{const u=base?new URL(value,base):new URL(value);if(u.protocol==='https:'&&!u.username&&!u.password&&!/^(localhost|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|\[::1\])/.test(u.hostname))return u.href;}catch{}return null;};
const bounded=value=>String(value||'').replace(/[\u0000-\u001f]/g,' ').slice(0,128);

export function discordActivity(view,config,time=Date.now()){
 if(view.idle){
  const publicLogo=safeImage('/brand/logo.png',config.appUrl);
  const logo=(config.discord.logoAsset&&config.discord.logoAsset!=='logo')
    ?(safeImage(config.discord.logoAsset,config.appUrl)||config.discord.logoAsset)
    :publicLogo;
  const url=config.appUrl;
  const buttons=url?[{label:'Открыть в Wave',url}]:[];
  const activity={application_id:config.discord.id,type:2,name:'Gluk Wave',details:bounded(view.details||'В приложении'),state:bounded(view.state||'На главной'),platform:'desktop',supported_platforms:['desktop','android','ios'],assets:{...(logo?{large_image:logo,large_text:'Gluk Wave',large_url:url}:{})},buttons,metadata:{button_urls:buttons.map(b=>b.url)}};
  if(view.idleSince)activity.timestamps={start:String(view.idleSince)};
  return activity;
 }
 const urls=[view.joinUrl,view.trackUrl].filter(Boolean),buttons=urls.map(url=>({label:url===view.joinUrl?'Слушать вместе':'Открыть в Wave',url}));
 const cover=safeImage(view.cover,config.appUrl),publicLogo=safeImage('/brand/logo.png',config.appUrl);
 const logo=(config.discord.logoAsset&&config.discord.logoAsset!=='logo')
   ?(safeImage(config.discord.logoAsset,config.appUrl)||config.discord.logoAsset)
   :publicLogo;
 const hasAlbum=Boolean(view.album&&view.album.trim()&&view.album.trim().toLowerCase()!==view.title?.trim().toLowerCase());
 const activity={application_id:config.discord.id,type:2,name:'Gluk Wave',details:bounded(view.title),state:bounded((logo?'':'∿ ')+(view.artist||'Gluk Wave')),platform:'desktop',supported_platforms:['desktop','android','ios'],assets:{...(cover?{large_image:cover,...(hasAlbum?{large_text:bounded(view.album)}:{}),large_url:view.trackUrl}:{}),...(logo?{small_image:logo,small_text:'Gluk Wave',small_url:config.appUrl}:{})},buttons,metadata:{button_urls:urls}};
 // The headless wire format uses millisecond timestamps (unlike SDK seconds).
 activity.timestamps={start:String(Math.floor(time-view.position*1000)),...(view.duration>0?{end:String(Math.floor(time+(view.duration-view.position)*1000))}:{})};
 return activity;
}

export async function setupDiscord(app,ctx,fetchImpl=fetch,options={}){
 const {store,config,requireAuth}=ctx,clock=options.clock||Date.now;
 const allowIdle=options.idlePresence??Boolean(config.discord?.idlePresence&&config.env!=='test');
 const workers=new Map();let closed=false,tickTask=null,cleanupAt=0,globalRetryUntil=0;
 const configured=()=>oauthSettings(config,'discord').loginAvailable&&config.discord.headless!==false;
 async function request(path,access,options={}){
  let response;try{response=await fetchImpl(api+path,{...options,headers:{...(options.body instanceof URLSearchParams?{'Content-Type':'application/x-www-form-urlencoded'}:{'Content-Type':'application/json'}),...(access?{Authorization:`Bearer ${access}`}:{})},signal:AbortSignal.timeout(10000)});}catch{throw Object.assign(new Error('Discord request failed'),{code:'DISCORD_NETWORK',retryAfter:15000});}
  let body={};try{const raw=await response.text();if(raw.length>262144)throw new Error();body=raw?JSON.parse(raw):{};}catch{if(response.ok)throw Object.assign(new Error('Discord response invalid'),{code:'DISCORD_PROTOCOL',retryAfter:30000});}
  if(!response.ok){const code=response.status===429?'DISCORD_RATE_LIMIT':response.status===401||body.error==='invalid_grant'?'DISCORD_RECONNECT':response.status===403?'DISCORD_SCOPE_UNAVAILABLE':response.status===404?'DISCORD_UNSUPPORTED':'DISCORD_PROVIDER_ERROR',retryAfter=Math.min(3600000,Math.max(12000,(Number(body.retry_after||response.headers?.get('retry-after'))||15)*1000));if(body.global&&response.status===429)globalRetryUntil=clock()+retryAfter;throw Object.assign(new Error(code),{code,status:response.status,retryAfter});}
  return body;
 }
 ctx.discordRequest=request;
 ctx.discordExchange=body=>request('/oauth2/token',null,{method:'POST',body:new URLSearchParams({...body,client_id:config.discord.id,client_secret:config.discord.secret})});
 async function access(record,force=false){
  let token=unseal(record.token,config.encryptionKey);if(!force&&token.expiresAt>clock()+60000)return token.access_token;
  if(!token.refresh_token)throw Object.assign(new Error('Reconnect required'),{code:'DISCORD_RECONNECT'});
  const fresh=await ctx.discordExchange({grant_type:'refresh_token',refresh_token:token.refresh_token});
  if(typeof fresh.access_token!=='string'||!fresh.access_token||!Number.isFinite(Number(fresh.expires_in)))throw Object.assign(new Error('Token response invalid'),{code:'DISCORD_PROTOCOL'});
  token={...token,...fresh,expiresAt:clock()+Number(fresh.expires_in)*1000};
  record.token=seal(token,config.encryptionKey);record.scope=token.scope||record.scope;
  await store.put(record.provider==='discord-cleanup'?'discordCleanup':'connections',record.id,record);return token.access_token;
 }
 async function authorized(record,path,body){
  let token=await access(record);try{return await request(path,token,{method:'POST',body:JSON.stringify(body)});}catch(error){if(error.status!==401)throw error;token=await access(record,true);return request(path,token,{method:'POST',body:JSON.stringify(body)});}
 }
 const saved=async(record,changes)=>{Object.assign(record,changes);await store.put(record.provider==='discord-cleanup'?'discordCleanup':'connections',record.id,record);};
 async function clear(record){
  if(!record?.headlessToken)return;
  const token=unseal(record.headlessToken,config.encryptionKey);
  try{await authorized(record,'/users/@me/headless-sessions/delete',{token});}
  catch(error){if(![400,404].includes(error.status))throw error;}
  await saved(record,{headlessToken:null,publishedAt:null});
 }
 async function cleanupDetached(record){
  await clear(record);
  const token=unseal(record.token,config.encryptionKey);
  if(record.revoke!==false)await request('/oauth2/token/revoke',null,{method:'POST',body:new URLSearchParams({client_id:config.discord.id,client_secret:config.discord.secret,token:token.refresh_token||token.access_token,token_type_hint:token.refresh_token?'refresh_token':'access_token'})});
 }
 async function retire(record,revoke=true){
  // Keep only encrypted credentials in a bounded, expiring retry queue. Never
  // republish from it. This also survives process failure during unlink.
  const key=id(),entry={id:key,provider:'discord-cleanup',token:record.token,headlessToken:record.headlessToken||null,scope:record.scope,revoke,expiresAt:clock()+86400000};
  await store.put('discordCleanup',key,entry);
  try{await cleanupDetached(entry);await store.remove('discordCleanup',key);}catch(error){ctx.log.warn({code:error.code||'DISCORD_CLEANUP'},'Discord cleanup queued');}
 }
 const worker=uid=>{let value=workers.get(uid);if(!value){value={due:0,lastSent:0,anchor:null,key:null};workers.set(uid,value);}return value;};
 async function view(uid){
  const output=await ctx.discordOutput?.(uid),connect=output?.connect,track=connect?.track,state=connect?.state;
  const isOnline=Boolean(ctx.userOnline?.(uid)||connect?.activeDeviceId);
  if(!track||!state||!connect.activeDeviceId){
   if(allowIdle&&isOnline)return {device:output?.device||null,activity:{idle:true,playing:false,details:'В приложении',state:'На главной'}};
   return {activity:null,device:null};
  }
  let duration=Math.max(0,Number(track.duration)||0);
  if(duration<=0&&track.source==='youtube'&&track.sourceId&&config.youtubeKey){
    try{
      const remote=ctx.providerRemoteJson||fetchImpl;
      const vr=await remote(`https://www.googleapis.com/youtube/v3/videos?${new URLSearchParams({part:'contentDetails',id:track.sourceId,key:config.youtubeKey})}`).then(r=>r?.json?r.json():r).catch(()=>null);
      const m=String(vr?.items?.[0]?.contentDetails?.duration||'').match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/);
      const d=m?Number(m[1]||0)*3600+Number(m[2]||0)*60+Number(m[3]||0):0;
      if(d>0){duration=d;await store.update('tracks',track.id,v=>v?{...v,duration:d}:v);}
    }catch{}
  }
  const position=Math.min(duration||86400,Math.max(0,state.position||0));
  const record=await store.get('connections',`${uid}:discord`),user=await store.get('users',uid),playing=!!state.playing&&(!duration||position<duration);
  const trackUrl=new URL(`/app/?track=${encodeURIComponent(track.id)}`,config.appUrl).href;
  const canHost=!connect.roomId||connect.room?.type==='jam'&&connect.room.ownerId===uid;
  if(!playing&&allowIdle&&isOnline)return {device:output.device,activity:{idle:true,playing:false,details:'В приложении',state:'На главной'}};
  return {device:output.device,activity:{trackId:track.id,title:track.title,artist:track.artist,album:track.album||'',cover:track.artwork||'',position,duration,playing,trackUrl,joinUrl:playing&&canHost&&eligible(user)&&joinAllowed(record)?new URL(`/app/?listen=${encodeURIComponent(uid)}`,config.appUrl).href:null}};
 }
 async function status(uid){
  const user=await store.get('users',uid),record=await store.get('connections',`${uid}:discord`),settings=mergeSettings(await store.get('settings',uid)||{}),allowed=eligible(user);
  const needsReconnect=!!record&&(!hasPresence(record)||record.presenceStatus==='reconnect_required');
  const live=allowed?await view(uid):{activity:null,device:null};
  const isIdleActive=Boolean(allowIdle&&live.activity?.idle);
  const state=!allowed?'locked':!configured()?'unavailable':!record?'disconnected':needsReconnect?'reconnect_required':!settings.discordPresence?'disabled':!live.activity?.playing&&!isIdleActive?'idle':!record.presenceStatus||record.presenceStatus==='idle'?'publishing':record.presenceStatus;
  return {eligible:allowed,configured:configured(),connected:!!record,needsReconnect,identity:record?{id:record.providerUserId,username:record.username||'',displayName:record.displayName||'',avatarUrl:record.avatarUrl||''}:null,enabled:settings.discordPresence,allowJoin:record?joinAllowed(record):true,status:state,lastPublishedAt:record?.publishedAt||null,lastError:record?.lastError||null,...live};
 }
 async function notify(uid){if(!closed)ctx.io?.to(`user:${uid}`).emit('discord:changed',await status(uid));}
 async function sync(uid){
  if(closed)return;
  await ctx.withLock('discord:'+uid,async()=>{
   const w=worker(uid),record=await store.get('connections',`${uid}:discord`);if(!record){workers.delete(uid);return;}
   if(w.due>clock()||w.retryUntil>clock()||globalRetryUntil>clock())return;
   const user=await store.get('users',uid),settings=mergeSettings(await store.get('settings',uid)||{});
   const next=eligible(user)&&settings.discordPresence&&configured()&&hasPresence(record)&&record.presenceStatus!=='reconnect_required'&&record.presenceStatus!=='unsupported'?await view(uid):{activity:null};
   try{
    const hasActivity=Boolean(next.activity&&(next.activity.playing||(allowIdle&&next.activity.idle)));
    if(!hasActivity){
     if(options.scheduler!==false){
      if(!w.pausedSince){w.pausedSince=clock();w.due=clock()+2500;return;}
      if(clock()-w.pausedSince<2500){w.due=w.pausedSince+2500;return;}
     }
     w.pausedSince=null;
     await clear(record);w.key=null;w.anchor=null;w.trackId=null;w.idleStart=null;w.due=clock()+25000;await saved(record,{presenceStatus:!eligible(user)?'locked':!configured()?'unavailable':!hasPresence(record)||record.presenceStatus==='reconnect_required'?'reconnect_required':record.presenceStatus==='unsupported'?'unsupported':!settings.discordPresence?'disabled':'idle',lastError:null});await notify(uid);return;
    }
    w.pausedSince=null;
    const isIdle=Boolean(next.activity.idle);
    if(isIdle){if(!w.idleStart)w.idleStart=clock();}else{w.idleStart=null;}
    const anchor=isIdle?(w.idleStart||0):(clock()-next.activity.position*1000);
    const key=isIdle
      ?'idle:online'
      :JSON.stringify([next.activity.trackId,next.activity.title,next.activity.artist,next.activity.album,next.activity.cover,next.activity.duration,next.activity.joinUrl,next.device]);
    const trackChanged=Boolean(!isIdle&&w.trackId&&w.trackId!==next.activity.trackId);
    const stateChanged=Boolean(w.key!==key);
    const changed=trackChanged||stateChanged||w.anchor===null||(!isIdle&&Math.abs(anchor-w.anchor)>2500);
    const minInterval=(trackChanged||stateChanged)?1500:(options.minInterval??12000);
    const maxInterval=isIdle?300000:25000;
    if(w.lastSent&&clock()-w.lastSent<minInterval){w.due=w.lastSent+minInterval;return;}
    if(!changed&&clock()-w.lastSent<maxInterval){w.due=w.lastSent+maxInterval;return;}
    const activityPayload=isIdle&&w.idleStart?{...next.activity,idleSince:w.idleStart}:next.activity;
    const payload={activities:[discordActivity(activityPayload,config,clock())],...(record.headlessToken?{token:unseal(record.headlessToken,config.encryptionKey)}:{})};
    let result;
    try{result=await authorized(record,'/users/@me/headless-sessions',payload);}catch(error){if(!record.headlessToken||![400,404].includes(error.status))throw error;await saved(record,{headlessToken:null});delete payload.token;result=await authorized(record,'/users/@me/headless-sessions',payload);}
    if(!result?.token&&!record.headlessToken)throw Object.assign(new Error('No headless session'),{code:'DISCORD_PROTOCOL'});
    await saved(record,{headlessToken:result.token?seal(String(result.token),config.encryptionKey):record.headlessToken,presenceStatus:'active',publishedAt:new Date(clock()).toISOString(),lastError:null});
    w.lastSent=clock();w.anchor=anchor;w.key=key;w.trackId=isIdle?null:next.activity.trackId;w.retryUntil=0;w.due=clock()+maxInterval;await notify(uid);
   }catch(error){
    const code=error.code||'DISCORD_PROVIDER_ERROR',permanent=['DISCORD_RECONNECT','DISCORD_SCOPE_UNAVAILABLE','DISCORD_UNSUPPORTED'].includes(code);
    await saved(record,{presenceStatus:code==='DISCORD_RECONNECT'?'reconnect_required':permanent?'unsupported':'retrying',lastError:code});
    w.due=clock()+(permanent?300000:error.retryAfter||30000);w.retryUntil=w.due;ctx.log.warn({code},'Discord presence unavailable');await notify(uid);
   }
  });
 }
 ctx.discordPlaybackChanged=uid=>{if(closed)return;const w=worker(uid);w.due=Math.min(w.due,clock());void sync(uid).catch(error=>ctx.log.warn({code:error.code||'DISCORD_SYNC'},'Discord presence sync failed'));};
 ctx.discordSync=sync;ctx.discordStatus=status;
 ctx.discordReplaceConnection=async(uid,record)=>ctx.withLock('discord-link',()=>ctx.withLock('discord:'+uid,async()=>{
  const user=await store.get('users',uid);if(!eligible(user))fail(403,'PLAN_LIMIT','Discord доступен в Beta и Unbound.');
  for(const other of await store.list('connections',r=>r.provider==='discord'&&r.providerUserId===record.providerUserId&&r.userId!==uid))if(other)fail(409,'DISCORD_ALREADY_LINKED','Этот Discord уже привязан к другому аккаунту Gluk Wave.');
  const old=await store.get('connections',record.id);if(old)await retire(old,false);
  await store.put('connections',record.id,{...record,allowJoin:old?.allowJoin!==false,presenceStatus:'idle'});workers.delete(uid);worker(uid);
 }));
 ctx.discordDisconnect=async uid=>{await ctx.withLock('discord:'+uid,async()=>{const record=await store.get('connections',`${uid}:discord`);if(record)await retire(record);await store.remove('connections',`${uid}:discord`);workers.delete(uid);});await notify(uid);};
 app.get('/api/discord',requireAuth,asyncRoute(async(req,res)=>res.set('Cache-Control','no-store').json(await status(req.auth.user.id))));
 app.patch('/api/discord',requireAuth,asyncRoute(async(req,res)=>{
  if(!eligible(req.auth.user))fail(403,'PLAN_LIMIT','Discord доступен в Beta и Unbound.');
  const body=parse(z.object({enabled:z.boolean().optional(),allowJoin:z.boolean().optional()}).strict(),req.body),uid=req.auth.user.id;
  await ctx.withLock('discord:'+uid,async()=>{
   if(body.allowJoin!==undefined){const record=await store.get('connections',`${uid}:discord`);if(!record)fail(409,'CONNECT_REQUIRED','Сначала подключи Discord.');await saved(record,{allowJoin:body.allowJoin});}
   if(body.enabled!==undefined)await ctx.withLock('settings:'+uid,async()=>{const settings=await store.update('settings',uid,value=>({...mergeSettings(value||{},{discordPresence:body.enabled}),revision:(value?.revision||0)+1}));ctx.io?.to(`user:${uid}`).emit('settings:changed',{settings,revision:settings.revision});});
  });worker(uid).due=0;await sync(uid);res.set('Cache-Control','no-store').json(await status(uid));
 }));
 app.post('/api/discord/listen/:userId',requireAuth,asyncRoute(async(req,res)=>ctx.withLock('discord:'+req.params.userId,async()=>{
  parse(z.object({}).strict(),req.body||{});const hostId=req.params.userId,host=await store.get('users',hostId),record=await store.get('connections',`${hostId}:discord`),settings=mergeSettings(await store.get('settings',hostId)||{});
  if(!eligible(host)||!settings.discordPresence||!joinAllowed(record)||!await ctx.areFriends(req.auth.user.id,hostId)||(await view(hostId)).activity?.playing!==true)fail(404,'JAM_NOT_FOUND','Совместное прослушивание недоступно.');
  const connect=await ctx.accountConnect(hostId);if(connect.roomId&&connect.room?.type!=='jam')fail(409,'ROOM_PERMISSION','Ведущий сейчас слушает в другой комнате.');
  for(const tid of [...new Set([connect.state.trackId,...connect.state.queue].filter(Boolean))])await ctx.requireTrack(tid,req.auth.user);
  const room=await ctx.ensureJam(host);await ctx.attachDiscordJam(hostId,room);res.set('Cache-Control','no-store').json({room:await ctx.joinJam(req.auth.user,room.id)});
 })));
 app.get('/api/admin/discord/diagnostics',ctx.requireAdmin,asyncRoute(async(req,res)=>{const records=await store.list('connections',r=>r.provider==='discord');res.set('Cache-Control','no-store').json({adapter:'oauth-headless-http-v1',documentedREST:false,configured:configured(),redirectUri:oauthSettings(config,'discord').redirectUri,scopes:discordScopes,linked:records.length,active:records.filter(r=>r.presenceStatus==='active').length,reconnect:records.filter(r=>r.presenceStatus==='reconnect_required'||!hasPresence(r)).length,cleanupPending:(await store.list('discordCleanup')).length});}));
 function tick(){
  if(closed)return Promise.resolve();if(tickTask)return tickTask;
  tickTask=(async()=>{
   // A slow provider must not create overlapping scans or an unbounded queue.
   for(const [uid] of [...workers].filter(([,w])=>w.due<=clock()).sort((a,b)=>a[1].due-b[1].due).slice(0,20)){if(closed)break;await sync(uid);}
   if(!closed&&clock()-cleanupAt>60000){cleanupAt=clock();for(const entry of (await store.list('discordCleanup')).slice(0,20)){if(closed)break;if(entry.expiresAt<clock()){await store.remove('discordCleanup',entry.id);continue;}try{await cleanupDetached(entry);await store.remove('discordCleanup',entry.id);}catch{}}}
  })().finally(()=>{tickTask=null;});return tickTask;
 }
 ctx.discordTick=tick;
 // On restart, clear any durable prior headless session before observing new
 // output. A stored Connect row is never evidence that a device is still live.
 for(const record of await store.list('connections',r=>r.provider==='discord'))worker(record.userId);
 const timer=options.scheduler===false?null:setInterval(()=>{void tick().catch(()=>{});},5000);timer?.unref();
 ctx.closeDiscord=async()=>{closed=true;if(timer)clearInterval(timer);await tickTask?.catch(()=>{});for(const uid of [...workers.keys()])await ctx.withLock('discord:'+uid,async()=>{const record=await store.get('connections',`${uid}:discord`);if(record)try{await clear(record);}catch{}});workers.clear();};
}
