import {Server} from 'socket.io';
import {z} from 'zod';
import {parse,text,fail,asyncRoute} from './util.js';
import {stateSchema,commandSchema,initialState,liveState} from './rooms.js';
import {languageCodes,browserLanguage} from './locale.js';
import {localizedError} from './messages.js';
import {planLimits} from './plans.js';

export function setupRealtime(server,app,ctx){
  const {store,config,requireAuth}=ctx;
  const io=new Server(server,{cors:{origin:config.origins,credentials:true},maxHttpBufferSize:64*1024,allowRequest:(req,cb)=>cb(null,!req.headers.origin||config.origins.includes(req.headers.origin))});ctx.io=io;
  const live=new Map(),primary=new Map(),transferring=new Set(),disconnects=new Set();
  const keyFor=(uid,did)=>`${uid}:${did}`;
  const socketsFor=key=>[...(live.get(key)||[])].map(sid=>io.sockets.sockets.get(sid)).filter(socket=>socket?.connected);
  const outputSocket=(key,surface)=>surface?socketsFor(key).find(socket=>socket.data.device.surfaceId===surface):socketsFor(key).find(socket=>socket.id===primary.get(key))||socketsFor(key)[0];
  const changes=uid=>io.to(`user:${uid}`).emit('devices:changed',{});
  const tokenFrom=socket=>{if(socket.handshake.auth.token)return socket.handshake.auth.token;const raw=socket.handshake.headers.cookie?.split(';').map(x=>x.trim()).find(x=>x.startsWith('gw_session='));try{return raw?decodeURIComponent(raw.slice(11)):null;}catch{return null;}};
  io.use(async(socket,next)=>{
    const language=languageCodes.includes(socket.handshake.auth.language)?socket.handshake.auth.language:browserLanguage(socket.handshake.headers['accept-language'])||'en';
    try{const rawToken=tokenFrom(socket),auth=await ctx.authenticate(rawToken);if(!auth)fail(401,'AUTH_REQUIRED','Войди в GlukWave.');
      const device=parse(z.object({deviceId:text(100),surfaceId:text(100).optional(),name:text(100),kind:z.enum(['web','windows','android','ios','macos','linux']).default('web'),token:z.string().optional(),language:z.enum(languageCodes).optional()}),socket.handshake.auth);
      device.surfaceId||=socket.id;socket.data={userId:auth.user.id,rawToken,device,sessionId:auth.session.id,language};next();
    }catch(err){const body=localizedError({code:err.code||'AUTH_REQUIRED',message:err.message},language),error=new Error(body.message);error.data={code:body.code};next(error);}
  });
  async function ensure(socket){const auth=await ctx.authenticate(socket.data.rawToken);if(!auth){socket.emit('session:revoked',{reason:'session_expired'});socket.disconnect(true);fail(401,'AUTH_REQUIRED','Сессия завершена.');}return auth;}
  const defaultConnect=uid=>({id:uid,independent:false,activeDeviceId:null,activeSurfaceId:null,state:initialState()});
  async function snapshot(uid){
    const value=await store.get('connect',uid)||defaultConnect(uid),serverTime=Date.now(),user=await store.get('users',uid),owner=value.activeDeviceId&&outputSocket(keyFor(uid,value.activeDeviceId),value.activeSurfaceId),state={...liveState(value.state,owner?serverTime:value.state.updatedAt),playing:!!owner&&value.state.playing,updatedAt:serverTime};
    const tracks=await Promise.all([...new Set([state.trackId,...state.queue].filter(Boolean))].map(tid=>store.get('tracks',tid)));
    const visible=[];for(const track of tracks)if(track&&await ctx.canAccessTrack(track,user))visible.push(ctx.publicTrack(track,user));
    const byId=new Map(visible.map(track=>[track.id,track]));
    return {independent:value.independent,activeDeviceId:owner?value.activeDeviceId:null,activeSurfaceId:owner?value.activeSurfaceId:null,state,track:byId.get(state.trackId)||null,queueTracks:state.queue.map(tid=>byId.get(tid)).filter(Boolean),serverTime};
  }
  const publish=async uid=>{const connect=await snapshot(uid);io.to(`user:${uid}`).emit('account:state',connect);return connect;};
  async function dispatch(socket,command){
    if(!socket?.connected)fail(409,'DEVICE_OFFLINE','Устройство отключено.');
    try{const result=await socket.timeout(10000).emitWithAck('device:command',command);if(result?.error)fail(409,result.error.code||'PLAYBACK_FAILED',result.error.message||'Устройство не начало воспроизведение.');return result;}
    catch(err){if(err.status)throw err;fail(504,'DEVICE_TIMEOUT','Устройство не подтвердило команду. Открой приложение и разреши воспроизведение.');}
  }
  async function revokeDevice(uid,did,reason){
    const key=keyFor(uid,did),sessions=await store.list('sessions',session=>session.userId===uid&&(session.deviceId===did||session.deviceIds?.includes(did)));
    for(const session of sessions){await store.remove('sessions',session.id);io.to(`session:${session.id}`).emit('session:revoked',{reason});io.in(`session:${session.id}`).disconnectSockets(true);}
    for(const socket of socketsFor(key)){socket.emit('session:revoked',{reason});socket.disconnect(true);}
    live.delete(key);primary.delete(key);await store.remove('devices',key);
    await store.update('connect',uid,value=>value?.activeDeviceId===did?{...value,activeDeviceId:null,activeSurfaceId:null,state:{...liveState(value.state),playing:false,updatedAt:Date.now(),revision:(value.state.revision||0)+1}}:value||defaultConnect(uid));
  }
  ctx.revokeDevice=(uid,did,reason='device_removed')=>ctx.withLock('devices:'+uid,async()=>{await revokeDevice(uid,did,reason);changes(uid);await publish(uid);});
  async function register(socket){
    const {userId,device,sessionId}=socket.data,key=keyFor(userId,device.deviceId);
    await ctx.withLock('devices:'+userId,async()=>{
      const auth=await ensure(socket),existing=await store.get('devices',key);
      const records=(await store.list('devices',record=>record.userId===userId&&record.deviceId!==device.deviceId)).sort((a,b)=>(a.createdAt||a.lastSeen||0)-(b.createdAt||b.lastSeen||0));
      while(records.length>=planLimits(auth.user).devices){const oldest=records.shift();await revokeDevice(userId,oldest.deviceId,'device_limit');}
      await ensure(socket);if(!socket.connected)return;
      await store.update('sessions',sessionId,value=>value?{...value,deviceId:value.deviceId||device.deviceId,deviceIds:[...new Set([...(value.deviceIds||[]),device.deviceId])]}:undefined);
      await store.update('devices',key,value=>({id:key,deviceId:device.deviceId,userId,name:device.name,kind:device.kind,createdAt:value?.createdAt||Date.now(),lastSeen:Date.now(),online:true,state:value?.state||initialState()}));
      const surfaces=live.get(key)||new Set();surfaces.add(socket.id);live.set(key,surfaces);if(!primary.has(key))primary.set(key,socket.id);
      socket.join(`user:${userId}`);socket.join(`session:${sessionId}`);
      await store.update('connect',userId,value=>{value||=defaultConnect(userId);if(value.activeDeviceId===device.deviceId&&!socketsFor(key).some(s=>s.id!==socket.id&&s.data.device.surfaceId===value.activeSurfaceId))return {...value,activeSurfaceId:device.surfaceId,state:{...value.state,playing:false,updatedAt:Date.now(),revision:(value.state.revision||0)+1}};return value;});
    });
    if(socket.connected){changes(userId);socket.emit('account:state',await snapshot(userId));}
  }
  io.on('connection',socket=>{
    const {userId,device}=socket.data,key=keyFor(userId,device.deviceId);
    const ready=register(socket).catch(err=>{ctx.log.warn({message:err.message},'Device registration failed');socket.disconnect(true);throw err;});ready.catch(()=>{});
    let bucketTime=Date.now(),count=0;
    const on=(event,fn)=>socket.on(event,async(payload,ack)=>{try{await ready;if(Date.now()-bucketTime>1000){bucketTime=Date.now();count=0;}if(++count>30)fail(429,'REALTIME_LIMIT','Слишком много команд.');const auth=await ensure(socket),result=await fn(payload,auth);if(typeof ack==='function')ack({ok:true,...result});}catch(err){const error=localizedError({code:err.code||'REALTIME_ERROR',message:err.status?err.message:'Не удалось выполнить команду.'},socket.data.language);if(typeof ack==='function')ack({error});else socket.emit('command:error',error);}});
    on('locale:change',async payload=>{const {language}=parse(z.object({language:z.enum(languageCodes)}).strict(),payload);socket.data.language=language;return {language};});
    on('device:claim',async()=>ctx.withLock('connect:'+userId,async()=>{
      const value=await store.get('connect',userId)||defaultConnect(userId);
      if(!value.independent&&value.activeDeviceId&&(value.activeDeviceId!==device.deviceId||value.activeSurfaceId!==device.surfaceId)){const previous=outputSocket(keyFor(userId,value.activeDeviceId),value.activeSurfaceId);if(previous)await dispatch(previous,{command:'pause',localOnly:true,outputActive:false});}
      primary.set(key,socket.id);await store.update('connect',userId,v=>{v||=defaultConnect(userId);return {...v,activeDeviceId:device.deviceId,activeSurfaceId:device.surfaceId,state:{...v.state,revision:(v.state.revision||0)+1}};});return {connect:await publish(userId)};
    }));
    on('device:state',async(payload,auth)=>{
      const {outputActive,roomId,...state}=parse(stateSchema.safeExtend({outputActive:z.boolean().optional(),roomId:text(100).nullable().optional()}),payload);
      if(state.trackId)await ctx.requireTrack(state.trackId,auth.user);
      const queueIdentity=JSON.stringify(state.queue);if(socket.data.queueIdentity!==queueIdentity){for(const tid of [...new Set(state.queue.filter(tid=>tid!==state.trackId))])await ctx.requireTrack(tid,auth.user);socket.data.queueIdentity=queueIdentity;}
      const value=await store.get('connect',userId)||defaultConnect(userId),here=value.activeDeviceId===device.deviceId&&value.activeSurfaceId===device.surfaceId;
      const allowed=value.independent||here||(!value.activeDeviceId&&state.trackId&&outputActive!==false),previous=await store.get('devices',key);if(!previous)fail(401,'AUTH_REQUIRED','Сессия завершена.');
      if(roomId)await ctx.requireRoom(roomId,userId);
      const accepted=(!allowed&&!roomId)?{...state,playing:false}:state;socket.data.lastState=accepted;
      await store.update('devices',key,v=>v?{...v,state:{...accepted,updatedAt:Date.now()},lastSeen:Date.now(),online:true}:undefined);
      if(allowed&&!roomId&&!transferring.has(userId)){primary.set(key,socket.id);await store.update('connect',userId,v=>{v||=defaultConnect(userId);if(transferring.has(userId)||!v.independent&&v.activeDeviceId&&(v.activeDeviceId!==device.deviceId||v.activeSurfaceId!==device.surfaceId))return v;return {...v,activeDeviceId:device.deviceId,activeSurfaceId:device.surfaceId,state:{...state,updatedAt:Date.now(),revision:(v.state.revision||0)+1}};});await publish(userId);}
      else if(!allowed&&state.playing&&!roomId&&!transferring.has(userId))socket.emit('account:state',await snapshot(userId));
      if(previous.state?.trackId!==accepted.trackId||previous.state?.playing!==accepted.playing)changes(userId);return {};
    });
    on('room:join',async payload=>{const {roomId}=parse(z.object({roomId:text(100)}).strict(),payload),room=await ctx.requireRoom(roomId,userId),serverTime=Date.now(),state={...liveState(room.state,serverTime),updatedAt:serverTime};socket.data.roomId=roomId;socket.join(`room:${roomId}`);socket.emit('room:state',{roomId,state,serverTime});await roomPresence(roomId);return {room:{...room,state}};});
    on('room:leave',async payload=>{const {roomId}=parse(z.object({roomId:text(100)}).strict(),payload);socket.leave(`room:${roomId}`);if(socket.data.roomId===roomId)socket.data.roomId=null;await roomPresence(roomId);return {};});
    on('room:command',async payload=>{const {roomId,...command}=parse(commandSchema.safeExtend({roomId:text(100)}),payload);return ctx.roomCommand(userId,roomId,command);});
    socket.on('disconnect',()=>{const task=(async()=>{
      await ready.catch(()=>{});const surfaces=live.get(key);surfaces?.delete(socket.id);if(primary.get(key)===socket.id)primary.delete(key);
      try{if(!surfaces?.size){live.delete(key);await store.update('devices',key,value=>value?{...value,online:false,lastSeen:Date.now(),state:{...liveState(value.state),playing:false,updatedAt:Date.now()}}:undefined);}
        await store.update('connect',userId,value=>value?.activeDeviceId===device.deviceId&&value.activeSurfaceId===device.surfaceId?{...value,activeDeviceId:null,activeSurfaceId:null,state:{...liveState(value.state),playing:false,updatedAt:Date.now(),revision:(value.state.revision||0)+1}}:undefined);
        changes(userId);await publish(userId);if(socket.data.roomId)await roomPresence(socket.data.roomId);
      }catch(err){ctx.log.warn({message:err.message},'Device disconnect failed');}
    })();disconnects.add(task);task.finally(()=>disconnects.delete(task));});
  });
  async function roomPresence(rid){const room=await store.get('rooms',rid);if(!room)return;const sockets=await io.in(`room:${rid}`).fetchSockets(),members=room.members.map(member=>({...member,online:sockets.some(socket=>socket.data.userId===member.userId),devices:sockets.filter(socket=>socket.data.userId===member.userId).map(socket=>({id:socket.data.device.deviceId,name:socket.data.device.name,kind:socket.data.device.kind}))}));io.to(`room:${rid}`).emit('room:members',{roomId:rid,members});}
  app.get('/api/devices',requireAuth,asyncRoute(async(req,res)=>{const records=await store.list('devices',record=>record.userId===req.auth.user.id);res.json({devices:records.map(record=>({id:record.deviceId,name:record.name,kind:record.kind,online:socketsFor(record.id).length>0,surfaceId:outputSocket(record.id)?.data.device.surfaceId,createdAt:record.createdAt,lastSeen:record.lastSeen,state:record.state})),limit:planLimits(req.auth.user).devices});}));
  app.delete('/api/devices/:id',requireAuth,asyncRoute(async(req,res)=>{if(!await store.get('devices',keyFor(req.auth.user.id,req.params.id)))fail(404,'DEVICE_NOT_FOUND','Устройство не найдено.');await ctx.revokeDevice(req.auth.user.id,req.params.id);await ctx.audit('device.remove',req.auth.user.id,{deviceId:req.params.id});res.json({ok:true});}));
  app.get('/api/connect',requireAuth,asyncRoute(async(req,res)=>res.json({connect:await snapshot(req.auth.user.id)})));
  app.patch('/api/connect',requireAuth,asyncRoute(async(req,res)=>{const {independent}=parse(z.object({independent:z.boolean()}).strict(),req.body),uid=req.auth.user.id;await ctx.withLock('connect:'+uid,async()=>{const value=await store.get('connect',uid)||defaultConnect(uid);if(!independent)for(const [key] of live)if(key.startsWith(uid+':'))for(const socket of socketsFor(key))if(socket.data.device.surfaceId!==value.activeSurfaceId&&socket.data.roomId==null&&socket.data.lastState?.playing)await dispatch(socket,{command:'pause',localOnly:true,outputActive:false});await store.update('connect',uid,v=>{v||=defaultConnect(uid);return {...v,independent,state:{...v.state,revision:(v.state.revision||0)+1}};});});res.json({connect:await publish(uid)});}));
  app.post('/api/devices/command',requireAuth,asyncRoute(async(req,res)=>{
    const {deviceId,surfaceId,...command}=parse(commandSchema.safeExtend({deviceId:text(100),surfaceId:text(100).optional()}),req.body),uid=req.auth.user.id,key=keyFor(uid,deviceId),target=outputSocket(key,surfaceId);if(!target)fail(409,'DEVICE_OFFLINE','Устройство сейчас отключено.');
    for(const tid of [...(command.queue||[]),...(command.trackId?[command.trackId]:[])])await ctx.requireTrack(tid,req.auth.user);
    if(command.command==='transfer')await ctx.withLock('connect:'+uid,async()=>{
      const value=await store.get('connect',uid)||defaultConnect(uid),sourceDid=command.fromDeviceId||value.activeDeviceId,sourceKey=keyFor(uid,sourceDid),source=await store.get('devices',sourceKey),sourceSocket=outputSocket(sourceKey,value.activeDeviceId===sourceDid?value.activeSurfaceId:undefined);
      if(!source||!sourceSocket||!source.state.trackId)fail(409,'SOURCE_OFFLINE','На исходном устройстве нет активного трека.');if(sourceSocket.id===target.id)fail(400,'SOURCE_DEVICE','Выбери другое устройство.');
      const state={...liveState(value.activeDeviceId===sourceDid?value.state:source.state),updatedAt:Date.now()};transferring.add(uid);
      try{await dispatch(sourceSocket,{command:'pause',localOnly:true,outputActive:false});await dispatch(target,{command:'track',trackId:state.trackId,position:state.position,queue:state.queue,volume:state.volume,localOnly:true,outputActive:true});if(!state.playing)await dispatch(target,{command:'pause',localOnly:true,outputActive:true});primary.set(key,target.id);if(sourceKey!==key)await store.update('devices',sourceKey,v=>v?{...v,state:{...state,playing:false,updatedAt:Date.now()}}:undefined);await store.update('devices',key,v=>v?{...v,state}:undefined);await store.update('connect',uid,v=>({...v||defaultConnect(uid),activeDeviceId:deviceId,activeSurfaceId:target.data.device.surfaceId,state:{...state,revision:(v?.state.revision||0)+1}}));}
      catch(err){await dispatch(target,{command:'pause',localOnly:true,outputActive:false}).catch(()=>{});await dispatch(sourceSocket,{command:state.playing?'play':'pause',localOnly:true,outputActive:true}).catch(()=>{});throw err;}
      finally{transferring.delete(uid);await publish(uid);changes(uid);}
    });else{if(command.command==='ended')fail(400,'INVALID_COMMAND','Неверная команда устройства.');await dispatch(target,command);}res.json({ok:true});
  }));
  ctx.closeRealtime=async()=>{await new Promise(resolve=>io.close(resolve));await Promise.allSettled([...disconnects]);};
}
