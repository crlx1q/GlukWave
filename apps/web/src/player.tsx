import { t, useLocale, getLanguage } from './locale';
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { io, type Socket } from 'socket.io-client';
import { api, errorText, post, patch } from './api';
import {deviceId,surfaceId,browserDeviceName} from './device-identity';
import { ownsOutput, snapshotPosition } from './connect-controller';
import { reportError } from './diagnostics';
import { waitForPlayback } from './playback-lifecycle';
import { restoredVolume, saveVolume } from './volume';
import { cached, downloads, saveTrack } from './cache';
import { useStore } from './store';
import { configureEqualizer, createAudioGraph, type AudioGraph } from './audio-processing';
import type { ConnectState, Device, Playback, PlayerState, Room, Track } from './types';
type Command = { command:string; trackId?:string; queue?:string[]; position?:number; volume?:number; expectedRevision?:number; repeat?:'off'|'all'|'one'; localOnly?:boolean; outputActive?:boolean; roomId?:string|null };
export type EmbedController = { play:()=>Promise<void>|void; pause:()=>void; seek:(position:number)=>void; volume?:(volume:number)=>void; destroy?:()=>void };
export type PlayerTab='player'|'lyrics'|'queue'|'comments';
type Player = { track:Track|null; state:PlayerState; duration:number; queue:Track[]; full:boolean; revealProgress:number|null; setRevealProgress:(progress:number|null)=>void; fullTab:PlayerTab; setFull:(open:boolean,tab?:PlayerTab)=>void; addTrack:Track|null; setAddTrack:(track:Track|null)=>void; savedIds:Set<string>; manualIds:Set<string>; shuffle:boolean; repeat:'off'|'all'|'one'; setShuffle:(enabled:boolean)=>void; setRepeat:(repeat:'off'|'all'|'one')=>void; playTrack:(track:Track,queue?:Track[])=>Promise<void>; command:(command:Command)=>Promise<void>; devices:Device[]; devicesOpen:boolean; setDevicesOpen:(open:boolean)=>void; room:Room|null; joinRoom:(room:Room)=>Promise<void>; leaveRoom:()=>Promise<void>; socket:Socket|null; playback:Playback|null; embedReady:(controller:EmbedController)=>void; embedUpdate:(position:number,playing:boolean,duration?:number)=>void; removeQueue:(id:string)=>void; mini:()=>Promise<void>; autoplayBlocked:boolean; finish:()=>void; audioEnergy:()=>number|null; equalizerAvailable:boolean; updateRoomMembers:(roomId:string,members:Room['members'])=>void };
type ConnectControls={connectState:ConnectState|null;outputHere:boolean;connectionStatus:'online'|'connecting'|'offline';devicesLoading:boolean;devicesError:string;refreshDevices:()=>Promise<void>;setIndependent:(value:boolean)=>Promise<void>;removeDevice:(id:string)=>Promise<void>};
const Context=createContext<(Player&ConnectControls)|null>(null);
export const localDeviceId=deviceId;
const emptyState:PlayerState={trackId:null,position:0,playing:false,volume:restoredVolume(),queue:[],updatedAt:Date.now(),revision:0};
export function PlayerProvider({children}:{children:ReactNode}) {useLocale();
  const locale=useLocale(),store=useStore(),audio=useMemo(()=>{const element=new Audio();element.crossOrigin='anonymous';return element;},[]),[track,setTrack]=useState<Track|null>(null),[playback,setPlayback]=useState<Playback|null>(null),[state,setState]=useState<PlayerState>(emptyState),[duration,setDuration]=useState(0),[queue,setQueue]=useState<Track[]>([]),[full,setFullState]=useState(false),[revealProgress,setRevealProgress]=useState<number|null>(null),[fullTab,setFullTab]=useState<PlayerTab>('player'),[addTrack,setAddTrack]=useState<Track|null>(null),[savedIds,setSavedIds]=useState(new Set<string>()),[manualIds,setManualIds]=useState(new Set<string>()),[shuffle,setShuffle]=useState(false),[repeat,setRepeat]=useState<'off'|'all'|'one'>('off'),[devices,setDevices]=useState<Device[]>([]),[devicesOpen,setDevicesOpen]=useState(false),[room,setRoom]=useState<Room|null>(null),[socket,setSocket]=useState<Socket|null>(null),[autoplayBlocked,setAutoplayBlocked]=useState(false);
  const audioMeter=useRef<{context:AudioContext;graph:AudioGraph|null}|null>(null),loadAbort=useRef<AbortController|null>(null);
  const [connectState,setConnectState]=useState<ConnectState|null>(null),[outputHere,setOutputHere]=useState(true),[connectionStatus,setConnectionStatus]=useState<'online'|'connecting'|'offline'>('offline');
  const connectRef=useRef<ConnectState|null>(null),outputHereRef=useRef(true),remoteAnchor=useRef<{position:number;time:number}|null>(null);
  const [devicesLoading,setDevicesLoading]=useState(false),[devicesError,setDevicesError]=useState('');
  const refreshDevices=useCallback(async()=>{const account=userRef.current?.id;if(!account)return;setDevicesLoading(true);try{const result=await api<{devices:Device[]}>('/devices');if(account!==userRef.current?.id)return;setDevices(result.devices);setDevicesError('');}catch(error){if(account===userRef.current?.id)setDevicesError(errorText(error));}finally{if(account===userRef.current?.id)setDevicesLoading(false);}},[]);
  const setOutput=useCallback((here:boolean)=>{outputHereRef.current=here;setOutputHere(here);},[]);
  const ensureAudioMeter=useCallback(()=>{
    let meter=audioMeter.current;
    if(!meter){try{meter={context:new AudioContext(),graph:null};audioMeter.current=meter;}catch{return;}}
    const current=meter;
    const attach=()=>{if(audioMeter.current!==current||current.graph||current.context.state!=='running')return;try{current.graph=createAudioGraph(current.context,audio);configureEqualizer(current.graph,settingsRef.current.equalizer);}catch{/* The measured server envelope remains available. */}};
    if(current.context.state==='suspended')void current.context.resume().then(attach).catch(()=>{});else attach();
  },[audio]);
  const audioEnergy=useCallback(()=>{const graph=audioMeter.current?.graph;if(!graph||graph.context.state!=='running'||audio.paused)return null;graph.analyser.getByteTimeDomainData(graph.data);let square=0;for(const value of graph.data){const sample=(value-128)/128;square+=sample*sample;}return Math.min(1,Math.sqrt(square/graph.data.length)*2.2);},[audio]);
  useEffect(()=>()=>{loadRevision.current++;loadAbort.current?.abort();outputHereRef.current=false;audio.pause();audio.removeAttribute('src');audio.load();controller.current?.destroy?.();controller.current=null;const meter=audioMeter.current;audioMeter.current=null;if(meter)void meter.context.close().catch(()=>{});},[audio]);
  useEffect(()=>{if(socket?.connected)socket.emit('locale:change',{language:locale.language});},[socket,locale.language]);
  const setFull=useCallback((open:boolean,tab:PlayerTab='player')=>{setFullTab(tab);setRevealProgress(null);setFullState(open);},[]);
  const networkDelay=useRef(0);const stateRef=useRef(state),trackRef=useRef(track),playbackRef=useRef(playback),queueRef=useRef(queue),roomRef=useRef(room),controller=useRef<EmbedController|null>(null),objectUrl=useRef<string|null>(null),artworkObjectUrl=useRef<string|null>(null),loadRevision=useRef(0),roomRevision=useRef(-1),roomSyncVersion=useRef(0),roomJoinVersion=useRef(0),desiredPlay=useRef(false),desiredPosition=useRef(0),settingsRef=useRef(store.settings),userRef=useRef(store.user),repeatRef=useRef(repeat),shuffleRef=useRef(shuffle),durationRef=useRef(duration);
  stateRef.current=state;trackRef.current=track;queueRef.current=queue;roomRef.current=room;settingsRef.current=store.settings;userRef.current=store.user;repeatRef.current=repeat;shuffleRef.current=shuffle;durationRef.current=duration;
  const update=useCallback((partial:Partial<PlayerState>)=>{const next={...stateRef.current,...partial,updatedAt:Date.now(),revision:stateRef.current.revision+1};if(partial.volume!==undefined)saveVolume(next.volume);stateRef.current=next;setState(next);},[]);
  const roomOutputActive=useRef(true);
  useEffect(()=>{const graph=audioMeter.current?.graph;if(graph)configureEqualizer(graph,store.settings.equalizer);audio.playbackRate=room?1:store.settings.playbackRate;},[audio,room?.id,store.settings.equalizer,store.settings.playbackRate]);
  const clearPlayback=useCallback(()=>{loadRevision.current++;loadAbort.current?.abort();desiredPlay.current=false;desiredPosition.current=0;audio.pause();audio.removeAttribute('src');audio.load();controller.current?.pause();controller.current?.destroy?.();controller.current=null;if(objectUrl.current){URL.revokeObjectURL(objectUrl.current);objectUrl.current=null;}if(artworkObjectUrl.current){URL.revokeObjectURL(artworkObjectUrl.current);artworkObjectUrl.current=null;}trackRef.current=null;playbackRef.current=null;queueRef.current=[];setTrack(null);setPlayback(null);setQueue([]);setDuration(0);update({trackId:null,position:0,playing:false,queue:[]});if('mediaSession'in navigator)navigator.mediaSession.metadata=null;},[audio,update]);
  useEffect(()=>{const refresh=()=>{if(store.user)void downloads(store.user.id).then(rows=>{setSavedIds(new Set(rows.map(row=>row.track.id)));setManualIds(new Set(rows.filter(row=>row.manual).map(row=>row.track.id)));});else{setSavedIds(new Set());setManualIds(new Set());}};refresh();window.addEventListener('wave:cache',refresh);return()=>window.removeEventListener('wave:cache',refresh);},[store.user?.id]);
  const applyTrack=useCallback(async(next:Track,nextQueue:Track[]|undefined,playing=true,position=0,strict=false)=>{
    loadAbort.current?.abort();const request=new AbortController();loadAbort.current=request;
    const revision=++loadRevision.current,startedUserId=userRef.current?.id;
    audio.pause();controller.current?.pause();controller.current?.destroy?.();controller.current=null;
    if(objectUrl.current){URL.revokeObjectURL(objectUrl.current);objectUrl.current=null;}if(artworkObjectUrl.current){URL.revokeObjectURL(artworkObjectUrl.current);artworkObjectUrl.current=null;}
    trackRef.current=next;playbackRef.current=null;setTrack(next);setPlayback(null);setDuration(next.duration||0);desiredPlay.current=playing;desiredPosition.current=position;setAutoplayBlocked(false);
    const order=nextQueue?.length?nextQueue:queueRef.current.some(item=>item.id===next.id)?queueRef.current:[next];setQueue(order);store.remember([next]);update({trackId:next.id,position,playing:false,queue:order.map(item=>item.id)});
    try {
      const local=userRef.current?await cached(userRef.current.id,next.id):undefined;
      const fresh=local?{kind:'audio' as const,url:URL.createObjectURL(local.blob),offline:true}:(await api<{playback:Playback}>(`/tracks/${encodeURIComponent(next.id)}/playback`,{signal:request.signal})).playback;
      if(revision!==loadRevision.current||startedUserId!==userRef.current?.id){if(local&&fresh.url)URL.revokeObjectURL(fresh.url);return;}
      const cachedCover=local?.artworkBlob?URL.createObjectURL(local.artworkBlob):undefined;if(cachedCover)artworkObjectUrl.current=cachedCover;
      const effective={...next,artwork:cachedCover||next.artwork,playback:local?{...local.track.playback,kind:'audio' as const,offline:true}:fresh};
      trackRef.current=effective;setTrack(effective);store.remember([{...effective,artwork:next.artwork}]);const effectiveOrder=order.map(item=>item.id===next.id?effective:item);queueRef.current=effectiveOrder;setQueue(effectiveOrder);
      playbackRef.current=fresh;setPlayback(fresh);
      if(fresh.kind==='audio'){
        if(local)objectUrl.current=fresh.url!;
        audio.src=fresh.url||`/api/media/${next.id}`;audio.volume=stateRef.current.volume;audio.currentTime=position;audio.playbackRate=roomRef.current?1:settingsRef.current.playbackRate;
        if(playing) {try {await audio.play();ensureAudioMeter();}catch {setAutoplayBlocked(true);store.notify(t('copy.704'));if(strict)throw new Error(t('copy.705'));}}
        if(userRef.current&&settingsRef.current.autoCache&&!local&&fresh.offline)void saveTrack(userRef.current.id,effective,settingsRef.current.cacheLimitMB,false).catch(()=>{});
      } else if(fresh.kind==='yandex'&&playing){store.notify(t('copy.706'));if(strict)throw new Error(t('copy.707'));}
      if(strict&&playing&&fresh.kind!=='audio')await waitForPlayback(()=>trackRef.current?.id===next.id&&stateRef.current.playing,request.signal,t('copy.708'));
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
    if(command.command==='seek'){const position=Math.max(0,command.position||0);if(!trackRef.current)return;desiredPosition.current=position;if(playbackRef.current?.kind==='audio')audio.currentTime=position;else if(controller.current)controller.current.seek(position);else if(playbackRef.current){store.notify(t('copy.709'));return;}update({position});return;}
    if(!trackRef.current){if(strict)throw new Error(t('copy.710'));store.navigate('library');return;}
    if(command.command==='pause'){desiredPlay.current=false;audio.pause();controller.current?.pause();update({playing:false});return;}
    if(command.command==='play'){
      desiredPlay.current=true;
      try {if(playback?.kind==='audio'){await audio.play();ensureAudioMeter();}else if(controller.current){await controller.current.play();if(strict&&loadAbort.current)await waitForPlayback(()=>stateRef.current.playing,loadAbort.current.signal,t('copy.711'));}else {store.notify(t('copy.712'));if(strict)throw new Error(t('copy.713'));return;}setAutoplayBlocked(false);}catch(error){setAutoplayBlocked(true);throw error;}
    }
  },[applyTrack,audio,ensureAudioMeter,playback,resolveQueue,store.library.tracks,store.navigate,store.notify,update]);
  const applyCommandRef=useRef(applyCommand);applyCommandRef.current=applyCommand;
  const applyTrackRef=useRef(applyTrack);applyTrackRef.current=applyTrack;
  const resolveQueueRef=useRef(resolveQueue);resolveQueueRef.current=resolveQueue;
  const sliderCommands=useRef(new Map<string,{timer:ReturnType<typeof setTimeout>;next:Command;roomId:string;done:Array<()=>void>}>());
  const sendCommand=useCallback(async(next:Command,expectedRoomId?:string,strict=false)=>{
    try {
      if(expectedRoomId&&expectedRoomId!==roomRef.current?.id)return;
      const currentRoom=roomRef.current;
      if(currentRoom?.type==='jam'&&currentRoom.ownerId!==userRef.current?.id&&['play','pause'].includes(next.command)){const result=await post<{connect:ConnectState}>(`/jams/${currentRoom.id}/pause`,{paused:next.command==='pause'});syncConnectRef.current(result.connect);await syncRoomStateRef.current({roomId:currentRoom.id,state:currentRoom.state,serverTime:result.connect.serverTime},true);return;}
      if(next.command==='play'&&roomRef.current&&!connectRef.current?.activeDeviceId)await enterRoomRef.current(roomRef.current);
      // Listening permissions govern the shared timeline, not the listener's own output level.
      if(next.command==='volume'&&roomRef.current){if(!outputHereRef.current&&connectRef.current?.activeDeviceId)await post('/devices/command',{...next,deviceId:connectRef.current.activeDeviceId,surfaceId:connectRef.current.activeSurfaceId});else await applyCommandRef.current(next);return;}
      if(roomRef.current&&socket){const sentAt=performance.now();await new Promise<void>((resolve,reject)=>socket.timeout(8000).emit('room:command',{roomId:roomRef.current!.id,...next},(error:unknown,result:{error?:{message:string}})=>{if(error)reject(new Error(t('copy.714')));else if(result?.error)reject(new Error(result.error.message));else{networkDelay.current=Math.min(250,(performance.now()-sentAt)/2);resolve();}}));}
      else if(connectRef.current&&!connectRef.current.independent&&!outputHereRef.current&&connectRef.current.activeDeviceId)await post('/devices/command',{...next,deviceId:connectRef.current.activeDeviceId,surfaceId:connectRef.current.activeSurfaceId});
      else {
        if(!roomRef.current&&socket?.connected&&!connectRef.current?.activeDeviceId){const result=await socket.timeout(8000).emitWithAck('device:claim',{});if(result.error)throw new Error(result.error.message);setOutput(true);}
        if(!playbackRef.current&&trackRef.current&&next.command==='play')await applyTrackRef.current(trackRef.current,queueRef.current,true,stateRef.current.position);
        else await applyCommandRef.current(next);
        if(socket?.connected){const dur=durationRef.current>0?durationRef.current:(trackRef.current?.duration||0);socket.emit('device:state',{...stateRef.current,duration:dur>0?dur:undefined,outputActive:outputHereRef.current,roomId:null});}
      }
    }catch(error){store.notify(errorText(error),true);if(strict)throw error;}
  },[socket,store.notify,setOutput]);
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
    try{if(roomRef.current||connectRef.current&&!connectRef.current.independent&&!outputHereRef.current)await command({command:'track',trackId:next.id,queue:(order||[next]).map(item=>item.id)});else {
      if(socket?.connected&&!connectRef.current?.activeDeviceId){const result=await socket.timeout(8000).emitWithAck('device:claim',{});if(result.error)throw new Error(result.error.message);setOutput(true);}
      await applyTrack(next,order);
      if(socket?.connected){const dur=durationRef.current>0?durationRef.current:(trackRef.current?.duration||0);socket.emit('device:state',{...stateRef.current,duration:dur>0?dur:undefined,outputActive:true,roomId:null});}
    }}catch(error){store.notify(errorText(error),true);}
  },[applyTrack,command,socket,setOutput,store.notify]);
  const finish=useCallback(()=>{
    if(!outputHereRef.current)return;
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
      const target=snapshotPosition(payload.state,payload.serverTime,networkDelay.current);
      if(!isCurrent())return;
      if(!outputHereRef.current){
        desiredPlay.current=false;audio.pause();controller.current?.pause();controller.current?.destroy?.();controller.current=null;playbackRef.current=null;setPlayback(null);
        trackRef.current=next;setTrack(next);queueRef.current=order;setQueue(order);setDuration(next.duration);
        stateRef.current={...payload.state,playing:payload.state.playing&&!connectRef.current?.jamPaused,position:target,volume:connectRef.current?.state.volume??stateRef.current.volume};setState({...stateRef.current});remoteAnchor.current={position:target,time:performance.now()};return;
      }
      remoteAnchor.current=null;
      const shouldPlay=payload.state.playing&&roomOutputActive.current&&!connectRef.current?.jamPaused;
      if(trackRef.current?.id!==next.id||!playbackRef.current){await applyTrackRef.current(next,order,shouldPlay,target);return;}
      queueRef.current=order;setQueue(order);update({queue:order.map(item=>item.id)});
      if(Math.abs(stateRef.current.position-target)>1.4||force)await applyCommandRef.current({command:'seek',position:target});
      if(!isCurrent())return;
      if(stateRef.current.playing!==shouldPlay)await applyCommandRef.current({command:shouldPlay?'play':'pause'});
    }catch(error){if(isCurrent())store.notify(errorText(error),true);}
  },[audio,clearPlayback,store.notify,update]);
  const syncRoomStateRef=useRef(syncRoomState);syncRoomStateRef.current=syncRoomState;
  const adoptRoomRef=useRef<(id:string,adoptOnly?:boolean)=>Promise<void>>(async()=>{}),adoptingRoom=useRef<string|null>(null);
  const clearRoom=useCallback(()=>{roomSyncVersion.current++;roomJoinVersion.current++;adoptingRoom.current=null;roomRef.current=null;setRoom(null);roomRevision.current=-1;roomOutputActive.current=false;remoteAnchor.current=null;if(userRef.current)localStorage.removeItem(`gw-room-${userRef.current.id}`);},[]);
  const syncConnect=useCallback((value:ConnectState,adopt=true)=>{
    if(connectRef.current&&value.state.revision<connectRef.current.state.revision)return;
    const pausedChanged=connectRef.current?.jamPaused!==value.jamPaused;const wasRemote=!outputHereRef.current;connectRef.current=value;setConnectState(value);
    const here=ownsOutput(value,deviceId,surfaceId);setOutput(here);roomOutputActive.current=here;
    if(adopt&&value.roomId&&roomRef.current?.id!==value.roomId&&adoptingRoom.current!==value.roomId)void adoptRoomRef.current(value.roomId).catch(error=>store.notify(errorText(error),true));
    else if(value.roomId===null&&roomRef.current){clearRoom();clearPlayback();}
    if(value.independent&&!value.roomId&&!roomRef.current){if(wasRemote){remoteAnchor.current=null;desiredPlay.current=false;stateRef.current={...stateRef.current,playing:false,volume:restoredVolume()};setState({...stateRef.current});}return;}
    if(!here){
      loadRevision.current++;desiredPlay.current=false;audio.pause();controller.current?.pause();controller.current?.destroy?.();controller.current=null;
      playbackRef.current=null;setPlayback(null);trackRef.current=value.track;setTrack(value.track);queueRef.current=value.queueTracks;setQueue(value.queueTracks);setDuration(value.track?.duration||0);
      stateRef.current={...value.state,position:snapshotPosition(value.state,value.serverTime)};setState({...stateRef.current});remoteAnchor.current={position:stateRef.current.position,time:performance.now()};
    }else if(!playbackRef.current&&value.track){trackRef.current=value.track;setTrack(value.track);queueRef.current=value.queueTracks;setQueue(value.queueTracks);setDuration(value.track.duration);stateRef.current={...value.state,playing:false,volume:restoredVolume()};setState({...stateRef.current});}
  if(here&&pausedChanged&&roomRef.current?.type==='jam')void syncRoomStateRef.current({roomId:roomRef.current.id,state:roomRef.current.state,serverTime:value.serverTime},true);
  },[audio,setOutput,clearPlayback,clearRoom,store.notify]);
  const syncConnectRef=useRef(syncConnect);syncConnectRef.current=syncConnect;
  const socketRef=useRef<Socket|null>(null);socketRef.current=socket;
  const enterRoom=useCallback(async(next:Room,adoptOnly=false)=>{
    const connection=socketRef.current;if(!connection?.connected)throw new Error(t('copy.720'));
    const version=++roomJoinVersion.current,account=userRef.current?.id;adoptingRoom.current=next.id;
    try{
      const result=await connection.timeout(8000).emitWithAck('room:join',{roomId:next.id,...(adoptOnly?{adoptOnly:true}:{})}) as {room?:Room;connect?:ConnectState;error?:{message:string}};
      if(result.error)throw new Error(result.error.message);
      if(version!==roomJoinVersion.current||account!==userRef.current?.id)return;
      const fresh=result.room||next;roomSyncVersion.current++;roomRevision.current=-1;roomRef.current=fresh;setRoom(fresh);
      if(account)localStorage.setItem(`gw-room-${account}`,fresh.id);
      if(result.connect)syncConnectRef.current(result.connect);
      else try{syncConnectRef.current((await api<{connect:ConnectState}>('/connect')).connect);}catch{/* Older servers keep their explicit room behavior. */}
      if(!adoptOnly)await syncRoomStateRef.current({roomId:fresh.id,state:fresh.state,serverTime:Date.now()},true);
    }finally{if(adoptingRoom.current===next.id)adoptingRoom.current=null;}
  },[]);
  const enterRoomRef=useRef(enterRoom);enterRoomRef.current=enterRoom;
  adoptRoomRef.current=async(id,adoptOnly=true)=>{
    if(roomRef.current?.id===id)return;
    const account=userRef.current?.id;adoptingRoom.current=id;
    try{const next=(await api<{room:Room}>(`/rooms/${encodeURIComponent(id)}`)).room;if(account!==userRef.current?.id||adoptingRoom.current!==id)return;await enterRoom(next,adoptOnly);if(roomRef.current?.id===id&&!outputHereRef.current)await syncRoomStateRef.current({roomId:id,state:roomRef.current.state,serverTime:Date.now()},true);}
    finally{if(adoptingRoom.current===id)adoptingRoom.current=null;}
  };
  useEffect(()=>{
    const local=()=>outputHereRef.current;
    const onTime=()=>{if(local())update({position:audio.currentTime});};const onPlay=()=>{if(local())update({playing:true});else audio.pause();};const onPause=()=>{if(local())update({playing:false});};const onDuration=()=>{if(local()&&Number.isFinite(audio.duration))setDuration(audio.duration);};
    const onEnded=()=>{if(local())finish();};
    const onError=()=>{if(local()&&audio.error&&audio.src){reportError('Audio playback failed','playback',{code:`MEDIA_${audio.error.code}`});update({playing:false});store.notify(t('copy.715'),true);}};
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
  useEffect(()=>{if(!store.user||store.offline)return;setConnectionStatus('connecting');const account=store.user.id,connection=io({withCredentials:true,auth:{language:getLanguage(),deviceId,surfaceId,name:browserDeviceName,kind:'web'}});socketRef.current=connection;setSocket(connection);const unbindSettings=store.bindSettingsSync(connection);
    const reloadDevices=()=>void refreshDevices();
    connection.on('connect',()=>{setConnectionStatus('online');reloadDevices();
      const restore=async()=>{try{const value=(await api<{connect:ConnectState}>('/connect')).connect;if(account!==userRef.current?.id||!connection.connected)return;syncConnectRef.current(value,false);
        const pinned=value.roomId??(value.roomId===undefined?localStorage.getItem(`gw-room-${account}`):null);if(pinned){const adoptOnly=Boolean(value.activeDeviceId);if(roomRef.current?.id===pinned)await enterRoom(roomRef.current,adoptOnly);else await adoptRoomRef.current(pinned,adoptOnly);if(roomRef.current?.id===pinned)await syncRoomStateRef.current({roomId:pinned,state:roomRef.current.state,serverTime:Date.now()},true);}
      }catch(error){if(account===userRef.current?.id)store.notify(errorText(error),true);}};void restore();
    });
    connection.on('account:state',(value:ConnectState)=>syncConnectRef.current(value));
    connection.on('session:revoked',()=>{if(store.user?.id!==userRef.current?.id)return;clearRoom();clearPlayback();store.setUser(null);store.setAuthOpen(true);connection.disconnect();});
    connection.on('disconnect',()=>{setConnectionStatus(navigator.onLine?'connecting':'offline');if(roomRef.current){setOutput(false);roomOutputActive.current=false;desiredPlay.current=false;audio.pause();controller.current?.pause();}});
    connection.on('devices:changed',reloadDevices);
    connection.on('connect_error',()=>{setConnectionStatus(navigator.onLine?'connecting':'offline');if(navigator.onLine)reportError('Realtime connection failed','socket',{code:'CONNECT_ERROR'});});
    const emitState=()=>{if(connection.connected&&(outputHereRef.current||roomRef.current)){const dur=durationRef.current>0?durationRef.current:(trackRef.current?.duration||0);connection.emit('device:state',{...stateRef.current,duration:dur>0?dur:undefined,playing:outputHereRef.current&&stateRef.current.playing,outputActive:outputHereRef.current,roomId:roomRef.current?.id||null});}};
    connection.on('device:command',async(payload:Command,ack?:(result:unknown)=>void)=>{try{
      if(payload.roomId&&roomRef.current?.id!==payload.roomId)await adoptRoomRef.current(payload.roomId,true);
      else if(payload.roomId===null&&roomRef.current)clearRoom();
      if(payload.outputActive!==undefined){roomOutputActive.current=payload.outputActive;setOutput(payload.outputActive);}
      if(roomRef.current&&!payload.localOnly)await sendCommandRef.current(payload,undefined,true);
      else if(!playbackRef.current&&trackRef.current&&payload.command==='play')await applyTrackRef.current(trackRef.current,queueRef.current,true,stateRef.current.position,true);
      else await applyCommandRef.current(payload,true);
      emitState();ack?.({ok:true});
    }catch(error){ack?.({error:{code:'PLAYBACK',message:errorText(error)}});store.notify(errorText(error),true);}});
    connection.on('room:state',(payload:{roomId:string;state:PlayerState;serverTime:number})=>void syncRoomStateRef.current(payload));
    connection.on('room:members',(payload:{roomId:string;members:Room['members']})=>{if(payload.roomId===roomRef.current?.id&&roomRef.current){roomRef.current={...roomRef.current,members:payload.members};setRoom(roomRef.current);}});
    connection.on('room:closed',(payload:{roomId:string})=>{if(payload.roomId===roomRef.current?.id){clearRoom();clearPlayback();store.notify(t('copy.719'));}});
    connection.on('room:left',(payload:{roomId:string})=>{if(payload.roomId===roomRef.current?.id){clearRoom();clearPlayback();}});
    connection.on('notification',(event:{title:string;body:string})=>store.notify(`${event.title}: ${event.body}`));
    const interval=setInterval(emitState,1800);
    return()=>{clearInterval(interval);unbindSettings();connection.disconnect();setSocket(null);setDevices([]);setConnectionStatus('offline');};
  },[store.user?.id,store.offline,store.notify,store.bindSettingsSync,clearPlayback,clearRoom,setOutput,store.setUser,store.setAuthOpen,enterRoom,refreshDevices]);
  const joinRoom=useCallback((next:Room)=>enterRoom(next),[enterRoom]);
  const leaveRoom=useCallback(async()=>{
    const current=roomRef.current;if(!current)return;
    const connection=socketRef.current;if(!connection?.connected)throw new Error(t('copy.720'));
    if(current.ownerId!==userRef.current?.id)await post(`/rooms/${encodeURIComponent(current.id)}/leave`);
    else{const result=await connection.timeout(8000).emitWithAck('room:leave',{roomId:current.id}) as {connect?:ConnectState;error?:{message:string}};if(result.error)throw new Error(result.error.message);if(result.connect)syncConnectRef.current(result.connect,false);}
    clearRoom();clearPlayback();
    const fresh=await api<{connect:ConnectState}>('/connect');syncConnectRef.current(fresh.connect,false);
  },[clearRoom,clearPlayback]);
  const updateRoomMembers=useCallback((roomId:string,members:Room['members'])=>{if(roomRef.current?.id===roomId){roomRef.current={...roomRef.current,members};setRoom(roomRef.current);}},[]);
  const embedReady=useCallback((embed:EmbedController)=>{if(!outputHereRef.current){embed.pause();embed.destroy?.();return;}controller.current=embed;const position=stateRef.current.position||desiredPosition.current;if(position)embed.seek(position);embed.volume?.(stateRef.current.volume);if(desiredPlay.current)Promise.resolve(embed.play()).catch(()=>{setAutoplayBlocked(true);store.notify(t('copy.722'));});},[store.notify]);
  const embedUpdate=useCallback((position:number,playing:boolean,total?:number)=>{if(!outputHereRef.current)return;update({position,playing});if(playing)setAutoplayBlocked(false);if(total&&Number.isFinite(total)&&total>0){durationRef.current=total;setDuration(total);}},[update]);
  const removeQueue=useCallback((id:string)=>{const remaining=queueRef.current.filter(item=>item.id!==id);if(roomRef.current){void command({command:'seek',position:stateRef.current.position,queue:remaining.map(item=>item.id)});return;}setQueue(remaining);queueRef.current=remaining;update({queue:remaining.map(item=>item.id)});},[update,command]);
  const channel=useMemo(()=>new BroadcastChannel(`glukwave-mini-${surfaceId}`),[]);
  const [miniActive,setMiniActive]=useState(false),miniWindow=useRef<Window|null>(null);
  useEffect(()=>{const send=()=>channel.postMessage({type:'state',track:trackRef.current,state:stateRef.current,duration:audio.duration||trackRef.current?.duration||0,palette:settingsRef.current.appearance[store.resolvedTheme],motion:store.motion,speed:settingsRef.current.appearance.speed});channel.onmessage=event=>{if(event.data?.command)void command(event.data);else if(event.data?.type==='subscribe'){setMiniActive(true);send();}else if(event.data?.type==='unsubscribe')setMiniActive(false);};if(!miniActive)return()=>{channel.onmessage=null;};const interval=setInterval(()=>{if(miniWindow.current?.closed){setMiniActive(false);return;}send();},500);send();return()=>{clearInterval(interval);channel.onmessage=null;};},[channel,command,audio,miniActive,store.resolvedTheme,store.motion]);
  const mini=useCallback(async()=>{const pip=(window as Window & {documentPictureInPicture?:{requestWindow:(options:{width:number;height:number})=>Promise<Window>}}).documentPictureInPicture;const url=`/mini.html?device=${encodeURIComponent(surfaceId)}`;if(pip){const pipWindow=await pip.requestWindow({width:380,height:176});miniWindow.current=pipWindow;pipWindow.document.title='GlukWave';const iframe=pipWindow.document.createElement('iframe');iframe.src=url;iframe.style.cssText='border:0;width:100%;height:100vh';pipWindow.document.body.style.margin='0';pipWindow.document.body.appendChild(iframe);}else {const popup=window.open(url,'glukwave-mini','width=380,height=176,popup=yes');if(!popup)throw new Error(t('copy.723'));miniWindow.current=popup;store.notify(t('copy.724'));}},[store.notify]);
  useEffect(()=>{let timer:ReturnType<typeof setInterval>|undefined;const tick=()=>{const anchor=remoteAnchor.current;if(!document.hidden&&!outputHereRef.current&&stateRef.current.playing&&anchor){const position=anchor.position+(performance.now()-anchor.time)/1000;stateRef.current={...stateRef.current,position};setState({...stateRef.current});}};const schedule=()=>{clearInterval(timer);timer=undefined;if(!document.hidden&&state.playing&&!outputHere){tick();timer=setInterval(tick,250);}};schedule();document.addEventListener('visibilitychange',schedule);return()=>{clearInterval(timer);document.removeEventListener('visibilitychange',schedule);};},[state.playing,outputHere]);
  const setIndependent=useCallback(async(independent:boolean)=>{const result=await patch<{connect:ConnectState}>('/connect',{independent});syncConnectRef.current(result.connect);},[]);
  const removeDevice=useCallback(async(id:string)=>{await api(`/devices/${encodeURIComponent(id)}`,{method:'DELETE'});setDevices(value=>value.filter(item=>item.id!==id));},[]);
  useEffect(()=>()=>{audio.pause();if(objectUrl.current)URL.revokeObjectURL(objectUrl.current);if(artworkObjectUrl.current)URL.revokeObjectURL(artworkObjectUrl.current);channel.close();},[audio,channel]);
  const playbackAccount=useRef(store.user?.id);
  useEffect(()=>{if(playbackAccount.current!==store.user?.id||!store.user){playbackAccount.current=store.user?.id;roomSyncVersion.current++;roomJoinVersion.current++;clearPlayback();roomRef.current=null;roomRevision.current=-1;setRoom(null);setFullState(false);setRevealProgress(null);connectRef.current=null;setConnectState(null);remoteAnchor.current=null;setOutput(true);}},[store.user?.id,clearPlayback,setOutput]);
  return <Context.Provider value={{track,state,duration,queue,full,revealProgress,setRevealProgress,fullTab,setFull,addTrack,setAddTrack,savedIds,manualIds,shuffle,repeat,setShuffle,setRepeat,playTrack,command,devices,devicesOpen,setDevicesOpen,room,joinRoom,leaveRoom,socket,playback,embedReady,embedUpdate,removeQueue,mini,autoplayBlocked,finish,audioEnergy,updateRoomMembers,equalizerAvailable:playback?.kind==='audio',connectState,outputHere,connectionStatus,devicesLoading,devicesError,refreshDevices,setIndependent,removeDevice}}>{children}</Context.Provider>;
}
export function usePlayer(){const context=useContext(Context);if(!context)throw new Error('Missing player');return context;}
