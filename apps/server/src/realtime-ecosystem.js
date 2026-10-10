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
  const live=new Map(),primary=new Map(),changing=new Set(),disconnects=new Set();
  ctx.realtimeStats=()=>({sockets:io.sockets.sockets.size,installations:live.size,primaryOutputs:primary.size,pendingMutations:changing.size,pendingDisconnects:disconnects.size});
  const keyFor=(uid,did)=>`${uid}:${did}`;
  const socketsFor=key=>[...(live.get(key)||[])].map(sid=>io.sockets.sockets.get(sid)).filter(socket=>socket?.connected);
  const outputSocket=(key,surface)=>surface?socketsFor(key).find(socket=>socket.data.device.surfaceId===surface):socketsFor(key).find(socket=>socket.id===primary.get(key))||socketsFor(key)[0];
  const changes=uid=>{io.to(`user:${uid}`).emit('devices:changed',{});void ctx.notifyFriends?.(uid).catch(()=>{});};
  const defaultConnect=uid=>({id:uid,independent:false,activeDeviceId:null,activeSurfaceId:null,roomId:null,state:initialState()});
  const tokenFrom=socket=>{if(socket.handshake.auth.token)return socket.handshake.auth.token;const raw=socket.handshake.headers.cookie?.split(';').map(x=>x.trim()).find(x=>x.startsWith('gw_session='));try{return raw?decodeURIComponent(raw.slice(11)):null;}catch{return null;}};
  io.use(async(socket,next)=>{
    const language=languageCodes.includes(socket.handshake.auth.language)?socket.handshake.auth.language:browserLanguage(socket.handshake.headers['accept-language'])||'en';
    try{
      const rawToken=tokenFrom(socket),auth=await ctx.authenticate(rawToken);if(!auth)fail(401,'AUTH_REQUIRED','Войди в GlukWave.');
      const device=parse(z.object({deviceId:text(100),surfaceId:text(100).optional(),name:text(100),kind:z.enum(['web','windows','android','ios','macos','linux']).default('web'),token:z.string().optional(),language:z.enum(languageCodes).optional()}),socket.handshake.auth);
      if(auth.session.deviceId&&auth.session.deviceId!==device.deviceId)fail(401,'AUTH_REQUIRED','Войди на этом устройстве заново.');
      device.surfaceId||=socket.id;socket.data={userId:auth.user.id,rawToken,device,sessionId:auth.session.id,language};next();
    }catch(err){const body=localizedError({code:err.code||'AUTH_REQUIRED',message:err.message},language),error=new Error(body.message);error.data={code:body.code};next(error);}
  });
  async function ensure(socket){const auth=await ctx.authenticate(socket.data.rawToken);if(!auth){socket.emit('session:revoked',{reason:'session_expired'});socket.disconnect(true);fail(401,'AUTH_REQUIRED','Сессия завершена.');}return auth;}
  async function snapshot(uid){
    const value=await store.get('connect',uid)||defaultConnect(uid),serverTime=Date.now(),user=await store.get('users',uid);
    const room=value.roomId?await store.get('rooms',value.roomId):null,joined=room?.members.some(member=>member.userId===uid),owner=value.activeDeviceId&&outputSocket(keyFor(uid,value.activeDeviceId),value.activeSurfaceId);
    const actual=joined?{...room.state,volume:value.state.volume}:value.state,state={...liveState(actual,owner?serverTime:actual.updatedAt),playing:!!owner&&actual.playing&&!(room?.type==='jam'&&value.jamPaused),updatedAt:serverTime,revision:value.state.revision||0};
    const tracks=await Promise.all([...new Set([state.trackId,...state.queue].filter(Boolean))].map(tid=>store.get('tracks',tid))),visible=[];
    for(const track of tracks)if(track&&await ctx.canAccessTrack(track,user))visible.push(ctx.publicTrack(track,user));const byId=new Map(visible.map(track=>[track.id,track]));
    return {jamPaused:!!(joined&&room.type==='jam'&&value.jamPaused),independent:value.independent,activeDeviceId:owner?value.activeDeviceId:null,activeSurfaceId:owner?value.activeSurfaceId:null,roomId:joined?room.id:null,room:joined?{id:room.id,name:room.name,type:room.type||'room',ownerId:room.ownerId}:null,state,track:byId.get(state.trackId)||null,queueTracks:state.queue.map(tid=>byId.get(tid)).filter(Boolean),serverTime};
  }
  const publish=async uid=>{const connect=await snapshot(uid);io.to(`user:${uid}`).emit('account:state',connect);ctx.discordPlaybackChanged?.(uid);return connect;};
  ctx.publishAccountConnect=publish;ctx.accountConnect=snapshot;
  ctx.discordOutput=async uid=>{const value=await store.get('connect',uid);if(!value?.activeDeviceId)return null;const socket=outputSocket(keyFor(uid,value.activeDeviceId),value.activeSurfaceId);if(!socket||!await ctx.authenticate(socket.data.rawToken))return null;return {connect:await snapshot(uid),device:{name:socket.data.device.name,kind:socket.data.device.kind}};};
  async function dispatch(socket,command){
    if(!socket?.connected)fail(409,'DEVICE_OFFLINE','Устройство отключено.');
    try{const result=await socket.timeout(10000).emitWithAck('device:command',command);if(result?.error)fail(409,result.error.code||'PLAYBACK_FAILED',result.error.message||'Устройство не начало воспроизведение.');if(!result||result.ok!==true)fail(409,'PLAYBACK_FAILED','Устройство не подтвердило воспроизведение.');return result;}
    catch(err){if(err.status)throw err;fail(504,'DEVICE_TIMEOUT','Устройство не подтвердило команду. Открой приложение и разреши воспроизведение.');}
  }
  // ACK waits cannot let a heartbeat change the selected output underneath a transfer.
  const mutate=async(uid,work)=>ctx.withLock('connect:'+uid,async()=>{changing.add(uid);try{return await work();}finally{changing.delete(uid);}});
  ctx.attachDiscordJam=(uid,room)=>mutate(uid,async()=>{
    const value=await store.get('connect',uid),socket=value?.activeDeviceId&&outputSocket(keyFor(uid,value.activeDeviceId),value.activeSurfaceId);
    if(!socket||!await ctx.authenticate(socket.data.rawToken))fail(409,'DEVICE_OFFLINE','Ведущий сейчас не слушает музыку.');
    if(value.roomId&&value.roomId!==room.id)fail(409,'ROOM_PERMISSION','Ведущий сейчас слушает в другой комнате.');
    if(room.ownerId!==uid||room.type!=='jam')fail(403,'ROOM_PERMISSION','Джем недоступен.');
    if(value.roomId===room.id)return;
    await store.update('rooms',room.id,previous=>previous?{...previous,state:{...liveState(value.state),updatedAt:Date.now()}}:undefined);
    socket.data.roomId=room.id;socket.join(`room:${room.id}`);
    await store.update('devices',keyFor(uid,value.activeDeviceId),device=>device?{...device,roomId:room.id}:undefined);
    await store.update('connect',uid,previous=>({...previous,roomId:room.id,jamPaused:false,state:{...previous.state,revision:(previous.state.revision||0)+1}}));
    await publish(uid);await roomPresence(room.id);
  });
  async function freezeOwner(uid,did,surface){await store.update('connect',uid,value=>value?.activeDeviceId===did&&(!surface||value.activeSurfaceId===surface)?{...value,activeDeviceId:null,activeSurfaceId:null,state:{...liveState(value.state),playing:false,updatedAt:Date.now(),revision:(value.state.revision||0)+1}}:undefined);}
  ctx.userOnline=uid=>[...io.sockets.sockets.values()].some(socket=>socket.connected&&socket.data.userId===uid);
  ctx.friendOutput=async uid=>{const value=await store.get('connect',uid);if(!value?.activeDeviceId)return null;const socket=outputSocket(keyFor(uid,value.activeDeviceId),value.activeSurfaceId);if(!socket)return null;const connect=await snapshot(uid);return {state:connect.state,device:{name:socket.data.device.name,kind:socket.data.device.kind}};};
  ctx.pauseJamListener=async(uid,room,paused)=>mutate(uid,async()=>{const value=await store.get('connect',uid);if(value?.roomId!==room.id)fail(409,'ROOM_NOT_FOUND','Подключись к джему.');const socket=value.activeDeviceId&&outputSocket(keyFor(uid,value.activeDeviceId),value.activeSurfaceId);await dispatch(socket,{command:paused?'pause':'play',position:liveState(room.state).position,localOnly:true,outputActive:true,roomId:room.id});await store.update('connect',uid,v=>({...v,jamPaused:paused,state:{...v.state,revision:(v.state.revision||0)+1}}));return publish(uid);});
  ctx.sessionOnline=sid=>[...io.sockets.sockets.values()].some(socket=>socket.connected&&socket.data.sessionId===sid);
  ctx.sessionRevoked=async session=>{
    for(const did of new Set([session.deviceId,...session.deviceIds||[]].filter(Boolean))){const remaining=await store.list('sessions',entry=>entry.userId===session.userId&&entry.expiresAt>Date.now()&&(entry.deviceId===did||entry.deviceIds?.includes(did)));if(!remaining.length){const key=keyFor(session.userId,did);await store.remove('devices',key);live.delete(key);primary.delete(key);await freezeOwner(session.userId,did);}}
    changes(session.userId);await publish(session.userId);
  };
  async function revokeDevice(uid,did,reason){
    const key=keyFor(uid,did),sessions=await store.list('sessions',session=>session.userId===uid&&(session.deviceId===did||session.deviceIds?.includes(did)));
    for(const session of sessions)await ctx.revokeSession(session,reason);for(const socket of socketsFor(key)){socket.emit('session:revoked',{reason});socket.disconnect(true);}
    live.delete(key);primary.delete(key);await store.remove('devices',key);await freezeOwner(uid,did);
  }
  ctx.revokeDevice=(uid,did,reason='device_removed')=>ctx.withLock('devices:'+uid,async()=>{await revokeDevice(uid,did,reason);changes(uid);await publish(uid);});
  async function register(socket){
    const {userId,device,sessionId}=socket.data,key=keyFor(userId,device.deviceId);
    await ctx.withLock('devices:'+userId,async()=>{
      const auth=await ensure(socket),records=(await store.list('devices',record=>record.userId===userId&&record.deviceId!==device.deviceId)).sort((a,b)=>(a.createdAt||a.lastSeen||0)-(b.createdAt||b.lastSeen||0));
      while(records.length>=planLimits(auth.user).devices){const oldest=records.shift();await revokeDevice(userId,oldest.deviceId,'device_limit');}await ensure(socket);if(!socket.connected)return;
      await store.update('sessions',sessionId,value=>{if(!value||value.deviceId&&value.deviceId!==device.deviceId)fail(401,'AUTH_REQUIRED','Сессия завершена.');return {...value,deviceId:device.deviceId,deviceIds:[device.deviceId],deviceName:device.name,kind:device.kind,lastActiveAt:new Date().toISOString()};});
      await store.update('devices',key,value=>({id:key,deviceId:device.deviceId,userId,name:device.name,kind:device.kind,createdAt:value?.createdAt||Date.now(),lastSeen:Date.now(),online:true,roomId:value?.roomId||null,state:value?.state||initialState()}));
      const surfaces=live.get(key)||new Set();surfaces.add(socket.id);live.set(key,surfaces);if(!primary.has(key))primary.set(key,socket.id);socket.join(`user:${userId}`);socket.join(`session:${sessionId}`);
      await store.update('connect',userId,value=>{value||=defaultConnect(userId);if(value.activeDeviceId===device.deviceId&&!socketsFor(key).some(s=>s.id!==socket.id&&s.data.device.surfaceId===value.activeSurfaceId))return {...value,activeSurfaceId:device.surfaceId,state:{...value.state,playing:false,updatedAt:Date.now(),revision:(value.state.revision||0)+1}};return value;});
    });if(socket.connected){changes(userId);io.to(`user:${userId}`).emit('sessions:changed',{});await publish(userId);}
  }
  async function roomMembers(room){
    const sockets=[...io.sockets.sockets.values()].filter(socket=>socket.connected&&socket.data.roomId===room.id&&socket.rooms.has(`room:${room.id}`));
    return Promise.all(room.members.map(async member=>{const connect=await store.get('connect',member.userId),memberSockets=sockets.filter(socket=>socket.data.userId===member.userId),devices=new Map();for(const socket of memberSockets){const d=socket.data.device,active=connect?.roomId===room.id&&connect.activeDeviceId===d.deviceId&&connect.activeSurfaceId===d.surfaceId;if(!devices.has(d.deviceId)||active)devices.set(d.deviceId,{id:d.deviceId,name:d.name,kind:d.kind,surfaceId:d.surfaceId,outputActive:active,playing:active&&room.state.playing&&!(room.type==='jam'&&connect?.jamPaused)});}return {...member,online:memberSockets.length>0,devices:[...devices.values()]};}));
  }
  async function roomPresence(rid){const room=await store.get('rooms',rid);if(room)io.to(`room:${rid}`).emit('room:members',{roomId:rid,members:await roomMembers(room)});}
  ctx.decorateRoom=async room=>({...room,members:await roomMembers(room)});ctx.refreshRoomPresence=roomPresence;
  ctx.publishRoomConnect=async rid=>{for(const value of await store.list('connect',entry=>entry.roomId===rid)){await store.update('connect',value.id,v=>v?.roomId===rid?{...v,state:{...v.state,revision:(v.state.revision||0)+1}}:undefined);await publish(value.id);}await roomPresence(rid);};
  ctx.leaveAccountRoom=async(uid,rid)=>mutate(uid,async()=>{
    const value=await store.get('connect',uid)||defaultConnect(uid);
    if(value.roomId===rid){for(const [key] of live)if(key.startsWith(uid+':'))for(const socket of socketsFor(key))if(socket.data.roomId===rid){if(socket.data.lastState?.playing)await dispatch(socket,{command:'pause',localOnly:true,outputActive:false,roomId:rid}).catch(()=>{});socket.data.roomId=null;socket.leave(`room:${rid}`);}for(const record of await store.list('devices',d=>d.userId===uid&&d.roomId===rid))await store.update('devices',record.id,v=>v?{...v,roomId:null,state:{...liveState(v.state),playing:false,updatedAt:Date.now()}}:undefined);await store.update('connect',uid,v=>({...v||value,roomId:null,jamPaused:false,activeDeviceId:null,activeSurfaceId:null,state:{...initialState(),revision:(v?.state.revision||0)+1}}));io.to(`user:${uid}`).emit('room:left',{roomId:rid});}
    await roomPresence(rid);changes(uid);return publish(uid);
  });
  io.on('connection',socket=>{
    const {userId,device}=socket.data,key=keyFor(userId,device.deviceId),ready=register(socket).catch(err=>{ctx.log.warn({message:err.message},'Device registration failed');socket.disconnect(true);throw err;});ready.catch(()=>{});let bucketTime=Date.now(),count=0;
    const on=(event,fn)=>socket.on(event,async(payload,ack)=>{try{await ready;if(Date.now()-bucketTime>1000){bucketTime=Date.now();count=0;}if(++count>30)fail(429,'REALTIME_LIMIT','Слишком много команд.');const result=await fn(payload,await ensure(socket));if(typeof ack==='function')ack({ok:true,...result});}catch(err){const error=localizedError({code:err.code||'REALTIME_ERROR',message:err.status?err.message:'Не удалось выполнить команду.'},socket.data.language);if(typeof ack==='function')ack({error});else socket.emit('command:error',error);}});
    on('locale:change',async payload=>{const {language}=parse(z.object({language:z.enum(languageCodes)}).strict(),payload);socket.data.language=language;return {language};});
    on('device:claim',async()=>mutate(userId,async()=>{const value=await store.get('connect',userId)||defaultConnect(userId);if(!value.independent&&value.activeDeviceId&&(value.activeDeviceId!==device.deviceId||value.activeSurfaceId!==device.surfaceId)){const previous=outputSocket(keyFor(userId,value.activeDeviceId),value.activeSurfaceId);if(previous)await dispatch(previous,{command:'pause',localOnly:true,outputActive:false,roomId:value.roomId||null});}primary.set(key,socket.id);await store.update('connect',userId,v=>{v||=defaultConnect(userId);return {...v,activeDeviceId:device.deviceId,activeSurfaceId:device.surfaceId,state:{...v.state,revision:(v.state.revision||0)+1}};});return {connect:await publish(userId)};}));
    on('device:state',async(payload,auth)=>{
      const {outputActive,roomId,duration,...state}=parse(stateSchema.safeExtend({outputActive:z.boolean().optional(),roomId:text(100).nullable().optional(),duration:z.number().finite().min(0).max(86400).optional()}),payload);if(state.trackId)await ctx.requireTrack(state.trackId,auth.user);
      if(state.trackId&&duration&&duration>0){const curTrack=await store.get('tracks',state.trackId);if(curTrack&&(!curTrack.duration||curTrack.duration<=0)){await store.update('tracks',state.trackId,v=>v&&(!v.duration||v.duration<=0)?{...v,duration}:v);ctx.discordPlaybackChanged?.(userId);}}
      const queueIdentity=JSON.stringify(state.queue);if(socket.data.queueIdentity!==queueIdentity){for(const tid of [...new Set(state.queue.filter(tid=>tid!==state.trackId))])await ctx.requireTrack(tid,auth.user);socket.data.queueIdentity=queueIdentity;}if(roomId){await ctx.requireRoom(roomId,userId);if(socket.data.roomId!==roomId)fail(409,'ROOM_NOT_FOUND','Подключись к комнате заново.');}
      const value=await store.get('connect',userId)||defaultConnect(userId),here=value.activeDeviceId===device.deviceId&&value.activeSurfaceId===device.surfaceId,allowed=(value.independent||here||(!value.activeDeviceId&&state.trackId&&outputActive!==false))&&outputActive!==false,previous=await store.get('devices',key);if(!previous)fail(401,'AUTH_REQUIRED','Сессия завершена.');
      if(allowed&&!changing.has(userId)&&(!value.activeDeviceId||here)&&outputSocket(key)?.id===socket.id)ctx.observeListening?.(userId,key+':'+device.surfaceId,state);
      const accepted=allowed?state:{...state,playing:false};socket.data.lastState=accepted;const deviceOutput=outputSocket(key),writeState=allowed||!deviceOutput||deviceOutput.id===socket.id;
      const semantic=JSON.stringify([accepted.trackId,accepted.playing,accepted.volume,roomId||null,state.queue]);
      const currentPosition=liveState(previous.state).position;
      const changed=socket.data.persistedState!==semantic||allowed&&Math.abs(accepted.position-currentPosition)>2;
      const checkpoint=Date.now()-(socket.data.persistedAt||0)>=10000;
      // A mirror browser tab must not overwrite the actual output's device record.
      if(changed||checkpoint){await store.update('devices',key,v=>v?{...v,...(writeState?{state:{...accepted,updatedAt:Date.now()},roomId:roomId||null}:{}),lastSeen:Date.now(),online:true}:undefined);socket.data.persistedState=semantic;socket.data.persistedAt=Date.now();}
      if(!socket.data.activityAt||Date.now()-socket.data.activityAt>60000){socket.data.activityAt=Date.now();await store.update('sessions',socket.data.sessionId,v=>v?{...v,lastActiveAt:new Date().toISOString()}:undefined);}
      // Room commands own their timeline. Routine playback ticks must not write
      // it back to Atlas or reload a whole queue for every connected surface.
      const roomCurrent=roomId&&value.roomId===roomId&&here;
      const updateConnect=roomCurrent?state.volume!==value.state.volume:changed||checkpoint;
      if(allowed&&!changing.has(userId)&&updateConnect){primary.set(key,socket.id);await store.update('connect',userId,v=>{v||=defaultConnect(userId);if(changing.has(userId)||!v.independent&&v.activeDeviceId&&(v.activeDeviceId!==device.deviceId||v.activeSurfaceId!==device.surfaceId))return v;return {...v,roomId:roomId||null,activeDeviceId:device.deviceId,activeSurfaceId:device.surfaceId,state:{...state,updatedAt:Date.now(),revision:(v.state.revision||0)+1}};});await publish(userId);}else if(!allowed&&state.playing&&!changing.has(userId))socket.emit('account:state',await snapshot(userId));
      if(previous.state?.trackId!==accepted.trackId||previous.state?.playing!==accepted.playing){changes(userId);if(roomId)await roomPresence(roomId);}return {};
    });
    on('room:join',async payload=>{
      const {roomId,adoptOnly}=parse(z.object({roomId:text(100),adoptOnly:z.boolean().optional()}).strict(),payload),room=await ctx.requireRoom(roomId,userId),serverTime=Date.now(),state={...liveState(room.state,serverTime),updatedAt:serverTime};
      const previousRoom=socket.data.roomId;if(previousRoom&&previousRoom!==roomId)socket.leave(`room:${previousRoom}`);socket.data.roomId=roomId;socket.join(`room:${roomId}`);
      if(!adoptOnly)await mutate(userId,async()=>{const value=await store.get('connect',userId)||defaultConnect(userId),existing=value.activeDeviceId&&outputSocket(keyFor(userId,value.activeDeviceId),value.activeSurfaceId);if(value.roomId!==roomId||!existing){if(existing&&existing.id!==socket.id)await dispatch(existing,{command:'pause',localOnly:true,outputActive:false,roomId:value.roomId||null});primary.set(key,socket.id);await store.update('connect',userId,v=>({...v||value,roomId,jamPaused:value.roomId===roomId?!!value.jamPaused:false,activeDeviceId:device.deviceId,activeSurfaceId:device.surfaceId,state:{...state,volume:v?.state.volume??state.volume,revision:(v?.state.revision||0)+1}}));}});
      const connect=await publish(userId);socket.emit('room:state',{roomId,state,serverTime});await roomPresence(roomId);if(previousRoom&&previousRoom!==roomId)await roomPresence(previousRoom);return {room:{...room,state,members:await roomMembers(room)},connect};
    });
    on('room:leave',async payload=>{const {roomId}=parse(z.object({roomId:text(100)}).strict(),payload);if(await ctx.leaveJam?.(userId,roomId))return {connect:await snapshot(userId)};socket.leave(`room:${roomId}`);if(socket.data.roomId===roomId)socket.data.roomId=null;return {connect:await ctx.leaveAccountRoom(userId,roomId)};});
    on('room:command',async payload=>{const {roomId,...command}=parse(commandSchema.safeExtend({roomId:text(100)}),payload);return ctx.roomCommand(userId,roomId,command);});
    socket.on('disconnect',()=>{const task=(async()=>{await ready.catch(()=>{});const surfaces=live.get(key);surfaces?.delete(socket.id);if(primary.get(key)===socket.id)primary.delete(key);try{if(!surfaces?.size){live.delete(key);await store.update('devices',key,value=>value?{...value,online:false,lastSeen:Date.now(),state:{...liveState(value.state),playing:false,updatedAt:Date.now()}}:undefined);}await freezeOwner(userId,device.deviceId,device.surfaceId);changes(userId);io.to(`user:${userId}`).emit('sessions:changed',{});await publish(userId);if(socket.data.roomId)await roomPresence(socket.data.roomId);ctx.jamDisconnected?.(userId);}catch(err){ctx.log.warn({message:err.message},'Device disconnect failed');}})();disconnects.add(task);task.finally(()=>disconnects.delete(task));});
  });
  app.get('/api/devices',requireAuth,asyncRoute(async(req,res)=>{
    const uid=req.auth.user.id,records=await store.list('devices',record=>record.userId===uid),sessions=await store.list('sessions',record=>record.userId===uid&&record.expiresAt>Date.now()),connect=await snapshot(uid);
    const devices=await Promise.all(records.map(async record=>{const sockets=socketsFor(record.id),output=outputSocket(record.id),active=connect.activeDeviceId===record.deviceId,room=record.roomId?await store.get('rooms',record.roomId):null,state=active?connect.state:{...record.state,playing:sockets.length>0&&record.state.playing},track=state.trackId?await store.get('tracks',state.trackId):null;return {id:record.deviceId,name:record.name,kind:record.kind,online:sockets.length>0,surfaceId:active?connect.activeSurfaceId:output?.data.device.surfaceId,surfaceCount:sockets.length,sessions:sessions.filter(s=>s.deviceId===record.deviceId).length,roomId:room?.members.some(m=>m.userId===uid)?room.id:null,createdAt:record.createdAt,lastSeen:record.lastSeen,state,track:track&&await ctx.canAccessTrack(track,req.auth.user)?ctx.publicTrack(track,req.auth.user):null};}));res.set('Cache-Control','no-store').json({devices,limit:planLimits(req.auth.user).devices});
  }));
  app.delete('/api/devices/:id',requireAuth,asyncRoute(async(req,res)=>{if(!await store.get('devices',keyFor(req.auth.user.id,req.params.id)))fail(404,'DEVICE_NOT_FOUND','Устройство не найдено.');await ctx.revokeDevice(req.auth.user.id,req.params.id);await ctx.audit('device.remove',req.auth.user.id,{deviceId:req.params.id});res.json({ok:true});}));
  app.get('/api/connect',requireAuth,asyncRoute(async(req,res)=>res.set('Cache-Control','no-store').json({connect:await snapshot(req.auth.user.id)})));
  app.patch('/api/connect',requireAuth,asyncRoute(async(req,res)=>{const {independent}=parse(z.object({independent:z.boolean()}).strict(),req.body),uid=req.auth.user.id;await mutate(uid,async()=>{const value=await store.get('connect',uid)||defaultConnect(uid);if(!independent)for(const [key] of live)if(key.startsWith(uid+':'))for(const socket of socketsFor(key))if(socket.data.device.surfaceId!==value.activeSurfaceId&&socket.data.lastState?.playing)await dispatch(socket,{command:'pause',localOnly:true,outputActive:false,roomId:socket.data.roomId||null});await store.update('connect',uid,v=>{v||=defaultConnect(uid);return {...v,independent,state:{...v.state,revision:(v.state.revision||0)+1}};});});res.json({connect:await publish(uid)});}));
  app.post('/api/devices/command',requireAuth,asyncRoute(async(req,res)=>{
    const {deviceId,surfaceId,...command}=parse(commandSchema.safeExtend({deviceId:text(100),surfaceId:text(100).optional()}),req.body),uid=req.auth.user.id,key=keyFor(uid,deviceId);for(const tid of [...(command.queue||[]),...(command.trackId?[command.trackId]:[])])await ctx.requireTrack(tid,req.auth.user);
    if(command.command==='transfer')await mutate(uid,async()=>{
      const target=outputSocket(key,surfaceId);if(!target)fail(409,'DEVICE_OFFLINE','Устройство сейчас отключено.');const value=await store.get('connect',uid)||defaultConnect(uid),sourceDid=command.fromDeviceId||value.activeDeviceId,sourceKey=keyFor(uid,sourceDid),source=await store.get('devices',sourceKey),sourceSocket=outputSocket(sourceKey,value.activeDeviceId===sourceDid?value.activeSurfaceId:undefined);
      if(!source||!sourceSocket)fail(409,'SOURCE_OFFLINE','На исходном устройстве нет активного трека.');if(sourceSocket.id===target.id)fail(400,'SOURCE_DEVICE','Выбери другое устройство.');
      const active=value.activeDeviceId===sourceDid,roomId=active?value.roomId||null:source.roomId||null,room=roomId?await ctx.requireRoom(roomId,uid):null,state={...liveState(room?{...room.state,volume:value.state.volume}:active?value.state:source.state),updatedAt:Date.now()};if(room?.type==='jam'&&value.jamPaused)state.playing=false;if(!state.trackId)fail(409,'SOURCE_OFFLINE','На исходном устройстве нет активного трека.');for(const tid of new Set([state.trackId,...state.queue]))await ctx.requireTrack(tid,req.auth.user);
      io.to(`user:${uid}`).emit('connect:transfer',{status:'pending',deviceId,fromDeviceId:sourceDid});
      try{
        await dispatch(sourceSocket,{command:'pause',localOnly:true,outputActive:false,roomId});
        await dispatch(target,{command:'track',trackId:state.trackId,position:state.position,queue:state.queue,volume:state.volume,localOnly:true,outputActive:true,roomId});
        if(!state.playing)await dispatch(target,{command:'pause',localOnly:true,outputActive:true,roomId});
        // Loading can outlive a login. A late player ACK cannot revive an expired output.
        await ensure(target);
        const requestingSession=await store.get('sessions',req.auth.session.id);
        if(!requestingSession||requestingSession.expiresAt<=Date.now())fail(401,'AUTH_REQUIRED','Сессия завершена.');
        if(!target.connected)fail(409,'DEVICE_OFFLINE','Устройство отключено.');
        primary.set(key,target.id);
        if(sourceKey!==key)await store.update('devices',sourceKey,v=>v?{...v,state:{...state,playing:false,updatedAt:Date.now()}}:undefined);
        await store.update('devices',key,v=>v?{...v,roomId,state}:undefined);
        await store.update('connect',uid,v=>({...v||defaultConnect(uid),roomId,activeDeviceId:deviceId,activeSurfaceId:target.data.device.surfaceId,state:{...state,revision:(v?.state.revision||0)+1}}));
        io.to(`user:${uid}`).emit('connect:transfer',{status:'complete',deviceId});
      }
      catch(err){await dispatch(target,{command:'pause',localOnly:true,outputActive:false,roomId}).catch(()=>{});await dispatch(sourceSocket,{command:state.playing?'play':'pause',localOnly:true,outputActive:true,roomId}).catch(()=>{});io.to(`user:${uid}`).emit('connect:transfer',{status:'failed',deviceId});throw err;}
      finally{await publish(uid);changes(uid);if(roomId)await roomPresence(roomId);}
    });else{if(command.command==='ended')fail(400,'INVALID_COMMAND','Неверная команда устройства.');const target=outputSocket(key,surfaceId);if(!target)fail(409,'DEVICE_OFFLINE','Устройство сейчас отключено.');if(target.data.roomId&&command.command!=='volume'){const room=await ctx.requireRoom(target.data.roomId,uid);if(room.type==='jam'&&room.ownerId!==uid&&['play','pause'].includes(command.command))await ctx.pauseJamListener(uid,room,command.command==='pause');else await ctx.roomCommand(uid,target.data.roomId,command);}else await dispatch(target,{...command,...(target.data.roomId?{localOnly:true,roomId:target.data.roomId}:{})});}res.json({ok:true});
  }));
  ctx.closeRealtime=async()=>{await new Promise(resolve=>io.close(resolve));await Promise.allSettled([...disconnects]);};
}
