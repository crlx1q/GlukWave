import { t, useLocale, getLanguage } from './locale';
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { io, type Socket } from 'socket.io-client';
import { api, errorText, post } from './api';
import { cached, downloads, saveTrack } from './cache';
import { useStore } from './store';
import { configureEqualizer, createAudioGraph, type AudioGraph } from './audio-processing';
import type { Device, Playback, PlayerState, Room, Track } from './types';
type Command = { command:string; trackId?:string; queue?:string[]; position?:number; volume?:number; expectedRevision?:number; repeat?:'off'|'all'|'one'; localOnly?:boolean; outputActive?:boolean };
export type EmbedController = { play:()=>Promise<void>|void; pause:()=>void; seek:(position:number)=>void; volume?:(volume:number)=>void; destroy?:()=>void };
export type PlayerTab='player'|'lyrics'|'queue'|'comments';
type Player = { track:Track|null; state:PlayerState; duration:number; queue:Track[]; full:boolean; revealProgress:number|null; setRevealProgress:(progress:number|null)=>void; fullTab:PlayerTab; setFull:(open:boolean,tab?:PlayerTab)=>void; addTrack:Track|null; setAddTrack:(track:Track|null)=>void; savedIds:Set<string>; manualIds:Set<string>; shuffle:boolean; repeat:'off'|'all'|'one'; setShuffle:(enabled:boolean)=>void; setRepeat:(repeat:'off'|'all'|'one')=>void; playTrack:(track:Track,queue?:Track[])=>Promise<void>; command:(command:Command)=>Promise<void>; devices:Device[]; devicesOpen:boolean; setDevicesOpen:(open:boolean)=>void; room:Room|null; joinRoom:(room:Room)=>Promise<void>; leaveRoom:()=>void; socket:Socket|null; playback:Playback|null; embedReady:(controller:EmbedController)=>void; embedUpdate:(position:number,playing:boolean,duration?:number)=>void; removeQueue:(id:string)=>void; mini:()=>Promise<void>; autoplayBlocked:boolean; finish:()=>void; audioEnergy:()=>number|null; equalizerAvailable:boolean; updateRoomMembers:(roomId:string,members:Room['members'])=>void };
const Context=createContext<Player|null>(null);
// A device is a live playback surface. Origin-wide storage made a second tab evict the first.
const deviceId=crypto.randomUUID();
export const localDeviceId=deviceId;
const emptyState:PlayerState={trackId:null,position:0,playing:false,volume:.8,queue:[],updatedAt:Date.now(),revision:0};
export function PlayerProvider({children}:{children:ReactNode}) {useLocale();
  const locale=useLocale(),store=useStore(),audio=useMemo(()=>{const element=new Audio();element.crossOrigin='anonymous';return element;},[]),[track,setTrack]=useState<Track|null>(null),[playback,setPlayback]=useState<Playback|null>(null),[state,setState]=useState<PlayerState>(emptyState),[duration,setDuration]=useState(0),[queue,setQueue]=useState<Track[]>([]),[full,setFullState]=useState(false),[revealProgress,setRevealProgress]=useState<number|null>(null),[fullTab,setFullTab]=useState<PlayerTab>('player'),[addTrack,setAddTrack]=useState<Track|null>(null),[savedIds,setSavedIds]=useState(new Set<string>()),[manualIds,setManualIds]=useState(new Set<string>()),[shuffle,setShuffle]=useState(false),[repeat,setRepeat]=useState<'off'|'all'|'one'>('off'),[devices,setDevices]=useState<Device[]>([]),[devicesOpen,setDevicesOpen]=useState(false),[room,setRoom]=useState<Room|null>(null),[socket,setSocket]=useState<Socket|null>(null),[autoplayBlocked,setAutoplayBlocked]=useState(false);
  const audioMeter=useRef<{context:AudioContext;graph:AudioGraph|null}|null>(null);
  const ensureAudioMeter=useCallback(()=>{
    let meter=audioMeter.current;
    if(!meter){try{meter={context:new AudioContext(),graph:null};audioMeter.current=meter;}catch{return;}}
    const current=meter;
    const attach=()=>{if(audioMeter.current!==current||current.graph||current.context.state!=='running')return;try{current.graph=createAudioGraph(current.context,audio);configureEqualizer(current.graph,settingsRef.current.equalizer);}catch{/* The measured server envelope remains available. */}};
    if(current.context.state==='suspended')void current.context.resume().then(attach).catch(()=>{});else attach();
  },[audio]);
  const audioEnergy=useCallback(()=>{const graph=audioMeter.current?.graph;if(!graph||graph.context.state!=='running'||audio.paused)return null;graph.analyser.getByteTimeDomainData(graph.data);let square=0;for(const value of graph.data){const sample=(value-128)/128;square+=sample*sample;}return Math.min(1,Math.sqrt(square/graph.data.length)*2.2);},[audio]);
  useEffect(()=>()=>{audio.pause();const meter=audioMeter.current;audioMeter.current=null;if(meter)void meter.context.close().catch(()=>{});},[audio]);
  useEffect(()=>{if(socket?.connected)socket.emit('locale:change',{language:locale.language});},[socket,locale.language]);
  const setFull=useCallback((open:boolean,tab:PlayerTab='player')=>{setFullTab(tab);setRevealProgress(null);setFullState(open);},[]);
  const networkDelay=useRef(0);const stateRef=useRef(state),trackRef=useRef(track),playbackRef=useRef(playback),queueRef=useRef(queue),roomRef=useRef(room),controller=useRef<EmbedController|null>(null),objectUrl=useRef<string|null>(null),loadRevision=useRef(0),roomRevision=useRef(-1),roomSyncVersion=useRef(0),roomJoinVersion=useRef(0),desiredPlay=useRef(false),desiredPosition=useRef(0),settingsRef=useRef(store.settings),userRef=useRef(store.user),repeatRef=useRef(repeat),shuffleRef=useRef(shuffle);
  stateRef.current=state;trackRef.current=track;queueRef.current=queue;roomRef.current=room;settingsRef.current=store.settings;userRef.current=store.user;repeatRef.current=repeat;shuffleRef.current=shuffle;
  const update=useCallback((partial:Partial<PlayerState>)=>{const next={...stateRef.current,...partial,updatedAt:Date.now(),revision:stateRef.current.revision+1};stateRef.current=next;setState(next);},[]);
  const roomOutputActive=useRef(true);
  useEffect(()=>{const graph=audioMeter.current?.graph;if(graph)configureEqualizer(graph,store.settings.equalizer);audio.playbackRate=room?1:store.settings.playbackRate;},[audio,room?.id,store.settings.equalizer,store.settings.playbackRate]);
  const clearPlayback=useCallback(()=>{loadRevision.current++;desiredPlay.current=false;desiredPosition.current=0;audio.pause();audio.removeAttribute('src');audio.load();controller.current?.pause();controller.current?.destroy?.();controller.current=null;if(objectUrl.current){URL.revokeObjectURL(objectUrl.current);objectUrl.current=null;}trackRef.current=null;playbackRef.current=null;queueRef.current=[];setTrack(null);setPlayback(null);setQueue([]);setDuration(0);update({trackId:null,position:0,playing:false,queue:[]});if('mediaSession'in navigator)navigator.mediaSession.metadata=null;},[audio,update]);
  useEffect(()=>{const refresh=()=>{if(store.user)void downloads(store.user.id).then(rows=>{setSavedIds(new Set(rows.map(row=>row.track.id)));setManualIds(new Set(rows.filter(row=>row.manual).map(row=>row.track.id)));});else{setSavedIds(new Set());setManualIds(new Set());}};refresh();window.addEventListener('wave:cache',refresh);return()=>window.removeEventListener('wave:cache',refresh);},[store.user?.id]);
  const applyTrack=useCallback(async(next:Track,nextQueue:Track[]|undefined,playing=true,position=0,strict=false)=>{
    const revision=++loadRevision.current,startedUserId=userRef.current?.id;
    audio.pause();controller.current?.pause();controller.current?.destroy?.();controller.current=null;
    if(objectUrl.current){URL.revokeObjectURL(objectUrl.current);objectUrl.current=null;}
    trackRef.current=next;playbackRef.current=null;setTrack(next);setPlayback(null);setDuration(next.duration||0);desiredPlay.current=playing;desiredPosition.current=position;setAutoplayBlocked(false);
    const order=nextQueue?.length?nextQueue:queueRef.current.some(item=>item.id===next.id)?queueRef.current:[next];setQueue(order);store.remember([next]);update({trackId:next.id,position,playing:false,queue:order.map(item=>item.id)});
    try {
      const local=userRef.current?await cached(userRef.current.id,next.id):undefined;
      const fresh=local?{kind:'audio' as const,url:URL.createObjectURL(local.blob),offline:true}:(await api<{playback:Playback}>(`/tracks/${encodeURIComponent(next.id)}/playback`)).playback;
      if(revision!==loadRevision.current||startedUserId!==userRef.current?.id){if(local&&fresh.url)URL.revokeObjectURL(fresh.url);return;}
      playbackRef.current=fresh;setPlayback(fresh);
      if(fresh.kind==='audio'){
        if(local)objectUrl.current=fresh.url!;
        audio.src=fresh.url||`/api/media/${next.id}`;audio.volume=stateRef.current.volume;audio.currentTime=position;audio.playbackRate=roomRef.current?1:settingsRef.current.playbackRate;
        if(playing) {try {await audio.play();ensureAudioMeter();}catch {setAutoplayBlocked(true);store.notify(t('copy.704'));if(strict)throw new Error(t('copy.705'));}}
        if(userRef.current&&settingsRef.current.autoCache&&!local&&fresh.offline)void saveTrack(userRef.current.id,next,settingsRef.current.cacheLimitMB,false).catch(()=>{});
      } else if(fresh.kind==='yandex'&&playing){store.notify(t('copy.706'));if(strict)throw new Error(t('copy.707'));}
      if(strict&&playing&&fresh.kind!=='audio')await new Promise<void>((resolve,reject)=>{const started=Date.now();const timer=setInterval(()=>{if(trackRef.current?.id===next.id&&stateRef.current.playing){clearInterval(timer);resolve();}else if(Date.now()-started>7500){clearInterval(timer);reject(new Error(t('copy.708')));}},100);});
      if(userRef.current&&startedUserId===userRef.current.id)void post('/history',{trackId:next.id,position}).then(()=>store.refreshLibrary()).catch(()=>{});
    }catch(error){if(revision===loadRevision.current){update({playing:false});store.notify(errorText(error),true);}throw error;}
  },[audio,ensureAudioMeter,store.remember,store.notify,store.refreshLibrary,update]);
  const resolveQueue=useCallback(async(ids?:string[])=>{if(!ids?.length)return queueRef.current;const tracks:Track[]=[];for(const id of ids){const known=store.library.tracks.find(item=>item.id===id)||queueRef.current.find(item=>item.id===id);if(known)tracks.push(known);else try{tracks.push((await api<{track:Track}>(`/tracks/${id}`)).track);}catch{/* A deleted queue item is omitted. */}}return tracks;},[store.library.tracks]);
  const applyCommand=useCallback(async(command:Command,strict=false)=>{
    if(command.command==='track'||command.command==='transfer'){
      if(!command.trackId)return;
      const next=store.library.tracks.find(item=>item.id===command.trackId)||queueRef.current.find(item=>item.id===command.trackId)||(await api<{track:Track}>(`/tracks/${command.trackId}`)).track;
      if(command.volume!==undefined){audio.volume=command.volume;update({volume:command.volume});}await applyTrack(next,await resolveQueue(command.queue),true,command.position||0,strict);return;
    }
    if(command.command==='next'||command.command==='previous'){
      const current=queueRef.current.findIndex(item=>item.id===trackRef.current?.id),order=queueRef.current;
      if(!order.length)return;
      const index=shuffleRef.current?Math.floor(Math.random()*order.length):(current+(command.command==='next'?1:-1)+order.length)%order.length;
      await applyTrack(order[index],order,true,0,strict);return;
    }
    if(command.command==='volume'){const volume=Math.max(0,Math.min(1,command.volume??.8));audio.volume=volume;controller.current?.volume?.(volume);update({volume});return;}
    if(command.command==='seek'){const position=Math.max(0,command.position||0);desiredPosition.current=position;if(playback?.kind==='audio')audio.currentTime=position;else if(controller.current)controller.current.seek(position);else {store.notify(t('copy.709'));return;}update({position});return;}
    if(!trackRef.current){if(strict)throw new Error(t('copy.710'));store.navigate('library');return;}
    if(command.command==='pause'){desiredPlay.current=false;audio.pause();controller.current?.pause();update({playing:false});return;}
    if(command.command==='play'){
      desiredPlay.current=true;
      try {if(playback?.kind==='audio'){await audio.play();ensureAudioMeter();}else if(controller.current){await controller.current.play();if(strict)await new Promise<void>((resolve,reject)=>{const started=Date.now();const timer=setInterval(()=>{if(stateRef.current.playing){clearInterval(timer);resolve();}else if(Date.now()-started>7500){clearInterval(timer);reject(new Error(t('copy.711')));}},100);});}else {store.notify(t('copy.712'));if(strict)throw new Error(t('copy.713'));return;}setAutoplayBlocked(false);}catch(error){setAutoplayBlocked(true);throw error;}
    }
  },[applyTrack,audio,ensureAudioMeter,playback,resolveQueue,store.library.tracks,store.navigate,store.notify,update]);
  const applyCommandRef=useRef(applyCommand);applyCommandRef.current=applyCommand;
  const applyTrackRef=useRef(applyTrack);applyTrackRef.current=applyTrack;
  const resolveQueueRef=useRef(resolveQueue);resolveQueueRef.current=resolveQueue;
  const sliderCommands=useRef(new Map<string,{timer:ReturnType<typeof setTimeout>;next:Command;roomId:string;done:Array<()=>void>}>());
  const sendCommand=useCallback(async(next:Command,expectedRoomId?:string,strict=false)=>{
    try {
      if(expectedRoomId&&expectedRoomId!==roomRef.current?.id)return;
      // Listening permissions govern the shared timeline, not the listener's own output level.
      if(next.command==='volume'){await applyCommandRef.current(next);return;}
      if(next.command==='play')roomOutputActive.current=true;
      if(roomRef.current&&socket){const sentAt=performance.now();await new Promise<void>((resolve,reject)=>socket.timeout(8000).emit('room:command',{roomId:roomRef.current!.id,...next},(error:unknown,result:{error?:{message:string}})=>{if(error)reject(new Error(t('copy.714')));else if(result?.error)reject(new Error(result.error.message));else{networkDelay.current=Math.min(250,(performance.now()-sentAt)/2);resolve();}}));}
      else await applyCommandRef.current(next);
    }catch(error){store.notify(errorText(error),true);if(strict)throw error;}
  },[socket,store.notify]);
  const sendCommandRef=useRef(sendCommand);sendCommandRef.current=sendCommand;
  const command=useCallback((next:Command):Promise<void>=>{
    const roomId=roomRef.current?.id;
    if(!roomId||!['volume','seek'].includes(next.command))return sendCommand(next);
    // Separate trailing lanes preserve both controls and keep fast drags below the socket quota.
    return new Promise(resolve=>{const key=next.command,current=sliderCommands.current.get(key);if(current){current.next=next;current.done.push(resolve);return;}
      const entry={next,roomId,done:[resolve],timer:setTimeout(()=>{sliderCommands.current.delete(key);void sendCommand(entry.next,entry.roomId).finally(()=>entry.done.forEach(done=>done()));},150)};sliderCommands.current.set(key,entry);
    });
  },[sendCommand]);
  useEffect(()=>()=>{for(const entry of sliderCommands.current.values()){clearTimeout(entry.timer);entry.done.forEach(done=>done());}sliderCommands.current.clear();},[]);
  const playTrack=useCallback(async(next:Track,order?:Track[])=>{
    try{if(roomRef.current)await command({command:'track',trackId:next.id,queue:(order||[next]).map(item=>item.id)});else await applyTrack(next,order);}catch{/* Playback errors are already reported by applyTrack. */}
  },[applyTrack,command]);
  const finish=useCallback(()=>{
    const currentRoom=roomRef.current;
    if(currentRoom){desiredPlay.current=false;update({playing:false});if(currentRoom.members.find(member=>member.userId===userRef.current?.id)?.canControl&&currentRoom.state.trackId)void command({command:'ended',trackId:currentRoom.state.trackId,expectedRevision:currentRoom.state.revision,repeat:repeatRef.current});return;}
    const index=queueRef.current.findIndex(item=>item.id===trackRef.current?.id);if(repeatRef.current==='one'){void applyCommandRef.current({command:'seek',position:0}).then(()=>applyCommandRef.current({command:'play'})).catch(error=>store.notify(errorText(error),true));}else if(index>=0&&(index<queueRef.current.length-1||repeatRef.current==='all'||shuffleRef.current))void command({command:'next'});else{desiredPlay.current=false;update({playing:false});}
  },[command,store.notify,update]);
  const syncRoomState=useCallback(async(payload:{roomId:string;state:PlayerState;serverTime:number},force=false)=>{
    if(payload.roomId!==roomRef.current?.id||(!force&&payload.state.revision<=roomRevision.current))return;
    if(payload.state.revision<roomRevision.current)return;
    const version=++roomSyncVersion.current,account=userRef.current?.id;
    // Invalidate any in-flight playback resolution before fetching this newer revision.
    loadRevision.current++;roomRevision.current=payload.state.revision;roomRef.current={...roomRef.current,state:payload.state};setRoom(roomRef.current);
    const isCurrent=()=>version===roomSyncVersion.current&&payload.roomId===roomRef.current?.id&&account===userRef.current?.id;
    try{
      if(!payload.state.trackId){clearPlayback();return;}
      const [order,next]=await Promise.all([resolveQueueRef.current(payload.state.queue),trackRef.current?.id===payload.state.trackId?Promise.resolve(trackRef.current):api<{track:Track}>(`/tracks/${encodeURIComponent(payload.state.trackId)}`).then(result=>result.track)]);
      if(!isCurrent())return;
      const elapsed=payload.state.playing?Math.max(0,(payload.serverTime-payload.state.updatedAt)/1000)+networkDelay.current/1000:0;
      const target=payload.state.position+elapsed;
      if(!isCurrent())return;
      const shouldPlay=payload.state.playing&&roomOutputActive.current;
      if(trackRef.current?.id!==next.id||!playbackRef.current){await applyTrackRef.current(next,order,shouldPlay,target);return;}
      queueRef.current=order;setQueue(order);update({queue:order.map(item=>item.id)});
      if(Math.abs(stateRef.current.position-target)>1.4||force)await applyCommandRef.current({command:'seek',position:target});
      if(!isCurrent())return;
      if(stateRef.current.playing!==shouldPlay)await applyCommandRef.current({command:shouldPlay?'play':'pause'});
    }catch(error){if(isCurrent())store.notify(errorText(error),true);}
  },[clearPlayback,store.notify,update]);
  const syncRoomStateRef=useRef(syncRoomState);syncRoomStateRef.current=syncRoomState;
  useEffect(()=>{
    const onTime=()=>update({position:audio.currentTime});const onPlay=()=>update({playing:true});const onPause=()=>update({playing:false});const onDuration=()=>{if(Number.isFinite(audio.duration))setDuration(audio.duration);};
    const onEnded=finish;
    const onError=()=>{if(audio.error&&audio.src){update({playing:false});store.notify(t('copy.715'),true);}};
    audio.addEventListener('timeupdate',onTime);audio.addEventListener('play',onPlay);audio.addEventListener('pause',onPause);audio.addEventListener('durationchange',onDuration);audio.addEventListener('ended',onEnded);audio.addEventListener('error',onError);
    return()=>{audio.removeEventListener('timeupdate',onTime);audio.removeEventListener('play',onPlay);audio.removeEventListener('pause',onPause);audio.removeEventListener('durationchange',onDuration);audio.removeEventListener('ended',onEnded);audio.removeEventListener('error',onError);};
  },[audio,finish,store.notify,update]);
  useEffect(()=>{
    document.title=state.playing&&track?`${track.title} — ${track.artist} · GlukWave`:t('copy.716');
    if(!('mediaSession'in navigator))return;
    navigator.mediaSession.playbackState=state.playing?'playing':'paused';
    if(track)navigator.mediaSession.metadata=new MediaMetadata({title:track.title,artist:track.artist,album:track.album,artwork:track.artwork?[{src:track.artwork}]:[]});
    const handlers:Partial<Record<MediaSessionAction,MediaSessionActionHandler>>={play:()=>void command({command:'play'}),pause:()=>void command({command:'pause'}),nexttrack:()=>void command({command:'next'}),previoustrack:()=>void command({command:'previous'}),seekto:details=>void command({command:'seek',position:details.seekTime||0}),seekforward:details=>void command({command:'seek',position:stateRef.current.position+(details.seekOffset||10)}),seekbackward:details=>void command({command:'seek',position:Math.max(0,stateRef.current.position-(details.seekOffset||10))})};
    for(const[action,handler]of Object.entries(handlers))try{navigator.mediaSession.setActionHandler(action as MediaSessionAction,handler!);}catch{/* Browser may not expose every media action. */}
  },[state.playing,track,command,locale.language]);
  useEffect(()=>{if(!store.user||store.offline)return;const connection=io({withCredentials:true,auth:{language:getLanguage(),deviceId,name:`${navigator.userAgent.includes('Windows')?t('copy.717'):t('copy.718')} · ${navigator.userAgent.includes('Firefox')?'Firefox':navigator.userAgent.includes('Edg')?'Edge':'Web'}`,kind:'web'}});setSocket(connection);const unbindSettings=store.bindSettingsSync(connection);
    const reloadDevices=()=>void api<{devices:Device[]}>('/devices').then(result=>setDevices(result.devices)).catch(()=>{});
    connection.on('connect',()=>{connection.emit('device:state',stateRef.current);reloadDevices();const roomId=roomRef.current?.id;if(roomId)connection.timeout(8000).emit('room:join',{roomId},(error:unknown,result:{room?:Room;error?:{message:string}})=>{if(roomId!==roomRef.current?.id)return;if(error||result?.error){store.notify(result?.error?.message||t('copy.721'),true);return;}if(result.room)void syncRoomStateRef.current({roomId,state:result.room.state,serverTime:Date.now()},true);});});
    connection.on('devices:changed',reloadDevices);
    connection.on('device:command',async(payload:Command,ack?:(result:unknown)=>void)=>{try{if(payload.outputActive!==undefined)roomOutputActive.current=payload.outputActive;if(roomRef.current&&!payload.localOnly)await sendCommandRef.current(payload,undefined,true);else await applyCommandRef.current(payload,true);ack?.({ok:true});connection.emit('device:state',stateRef.current);}catch(error){ack?.({error:{code:'PLAYBACK',message:errorText(error)}});store.notify(errorText(error),true);}});
    connection.on('room:state',(payload:{roomId:string;state:PlayerState;serverTime:number})=>void syncRoomStateRef.current(payload));
    connection.on('room:members',(payload:{roomId:string;members:Room['members']})=>{if(payload.roomId===roomRef.current?.id&&roomRef.current){roomRef.current={...roomRef.current,members:payload.members};setRoom(roomRef.current);}});
    connection.on('room:closed',(payload:{roomId:string})=>{if(payload.roomId===roomRef.current?.id){roomSyncVersion.current++;roomJoinVersion.current++;setRoom(null);roomRef.current=null;store.notify(t('copy.719'));}});
    connection.on('notification',(event:{title:string;body:string})=>store.notify(`${event.title}: ${event.body}`));
    const interval=setInterval(()=>{if(connection.connected)connection.emit('device:state',stateRef.current);},1800);
    return()=>{clearInterval(interval);unbindSettings();connection.disconnect();setSocket(null);setDevices([]);};
  },[store.user?.id,store.offline,store.notify,store.bindSettingsSync]);
  const joinRoom=useCallback(async(next:Room)=>{if(!socket?.connected)throw new Error(t('copy.720'));const version=++roomJoinVersion.current,account=userRef.current?.id;const fresh=await new Promise<Room>((resolve,reject)=>socket.timeout(8000).emit('room:join',{roomId:next.id},(error:unknown,result:{error?:{message:string};room?:Room})=>{if(error||result?.error)reject(new Error(result?.error?.message||t('copy.721')));else resolve(result.room||next);}));if(version!==roomJoinVersion.current||account!==userRef.current?.id)return;roomRevision.current=-1;roomOutputActive.current=true;roomRef.current=fresh;setRoom(fresh);await syncRoomStateRef.current({roomId:fresh.id,state:fresh.state,serverTime:Date.now()},true);},[socket]);
  const leaveRoom=useCallback(()=>{roomJoinVersion.current++;roomSyncVersion.current++;loadRevision.current++;if(roomRef.current)socket?.emit('room:leave',{roomId:roomRef.current.id});setRoom(null);roomRef.current=null;roomRevision.current=-1;},[socket]);
  const updateRoomMembers=useCallback((roomId:string,members:Room['members'])=>{if(roomRef.current?.id===roomId){roomRef.current={...roomRef.current,members};setRoom(roomRef.current);}},[]);
  const embedReady=useCallback((embed:EmbedController)=>{controller.current=embed;const position=stateRef.current.position||desiredPosition.current;if(position)embed.seek(position);embed.volume?.(stateRef.current.volume);if(desiredPlay.current)Promise.resolve(embed.play()).catch(()=>{setAutoplayBlocked(true);store.notify(t('copy.722'));});},[store.notify]);
  const embedUpdate=useCallback((position:number,playing:boolean,total?:number)=>{update({position,playing});if(playing)setAutoplayBlocked(false);if(total&&Number.isFinite(total))setDuration(total);},[update]);
  const removeQueue=useCallback((id:string)=>{const remaining=queueRef.current.filter(item=>item.id!==id);if(roomRef.current){void command({command:'seek',position:stateRef.current.position,queue:remaining.map(item=>item.id)});return;}setQueue(remaining);queueRef.current=remaining;update({queue:remaining.map(item=>item.id)});},[update,command]);
  const channel=useMemo(()=>new BroadcastChannel(`glukwave-mini-${deviceId}`),[]);
  useEffect(()=>{channel.onmessage=event=>{if(event.data?.command)void command(event.data);};const send=()=>channel.postMessage({type:'state',track:trackRef.current,state:stateRef.current,duration:audio.duration||trackRef.current?.duration||0});const interval=setInterval(send,500);send();return()=>clearInterval(interval);},[channel,command,audio]);
  const mini=useCallback(async()=>{const pip=(window as Window & {documentPictureInPicture?:{requestWindow:(options:{width:number;height:number})=>Promise<Window>}}).documentPictureInPicture;const url=`/mini.html?device=${encodeURIComponent(deviceId)}`;if(pip){const pipWindow=await pip.requestWindow({width:380,height:176});pipWindow.document.title='GlukWave';const iframe=pipWindow.document.createElement('iframe');iframe.src=url;iframe.style.cssText='border:0;width:100%;height:100vh';pipWindow.document.body.style.margin='0';pipWindow.document.body.appendChild(iframe);}else {const popup=window.open(url,'glukwave-mini','width=380,height=176,popup=yes');if(!popup)throw new Error(t('copy.723'));store.notify(t('copy.724'));}},[store.notify]);
  useEffect(()=>()=>{audio.pause();if(objectUrl.current)URL.revokeObjectURL(objectUrl.current);channel.close();},[audio,channel]);
  const playbackAccount=useRef(store.user?.id);
  useEffect(()=>{if(playbackAccount.current!==store.user?.id||!store.user){playbackAccount.current=store.user?.id;roomSyncVersion.current++;roomJoinVersion.current++;clearPlayback();roomRef.current=null;roomRevision.current=-1;setRoom(null);setFullState(false);setRevealProgress(null);}},[store.user?.id,clearPlayback]);
  return <Context.Provider value={{track,state,duration,queue,full,revealProgress,setRevealProgress,fullTab,setFull,addTrack,setAddTrack,savedIds,manualIds,shuffle,repeat,setShuffle,setRepeat,playTrack,command,devices,devicesOpen,setDevicesOpen,room,joinRoom,leaveRoom,socket,playback,embedReady,embedUpdate,removeQueue,mini,autoplayBlocked,finish,audioEnergy,updateRoomMembers,equalizerAvailable:playback?.kind==='audio'}}>{children}</Context.Provider>;
}
export function usePlayer(){const context=useContext(Context);if(!context)throw new Error('Missing player');return context;}

