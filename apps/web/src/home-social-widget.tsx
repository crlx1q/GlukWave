import {useEffect,useRef,useState} from 'react';
import {ArrowRight,Globe,Headphones,LockKeyhole,Play,RefreshCw,Users} from 'lucide-react';
import {api,errorText,post} from './api';
import {canvasText as text} from './home-canvas-copy';
import {countLabel,t,useLocale} from './locale';
import type {Friend} from './parity-social';
import {usePlayer} from './player';
import {useStore} from './store';
import type {HomeWidget,Room,RoomSummary,Track} from './types';
import {Art,TrackSkeleton} from './ui';

type SocialKind='friends'|'rooms';
type SocialRoom=Room|RoomSummary;
type SocialData={friends:Friend[];rooms:SocialRoom[]};

export function HomeSocialWidget({widget,kind}:{widget:HomeWidget;kind:SocialKind}){
 useLocale();
 const store=useStore(),player=usePlayer(),owner=store.user?.id;
 const [snapshot,setSnapshot]=useState<{owner:string;data?:SocialData;error?:string}>();
 const [retry,setRetry]=useState(0),[joining,setJoining]=useState<string>();
 const activeOwner=useRef(owner);
 activeOwner.current=owner;

 useEffect(()=>{
  if(!owner)return;
  const controller=new AbortController(),{signal}=controller;
  const event=kind==='friends'?'friends:changed':'room:directory';
  let pending=false,scheduled:ReturnType<typeof setTimeout>|undefined;
  const refresh=async()=>{
   if(pending||signal.aborted)return;
   pending=true;
   try{
    let data:SocialData;
    if(kind==='friends'){
     const result=await api<{friends:Friend[]}>('/friends',{signal});
     data={friends:result.friends.filter(friend=>friend.online&&friend.activity?.playing&&friend.activity.track),rooms:[]};
    }else{
     const result=await api<{rooms:Room[];publicRooms?:RoomSummary[]}>('/rooms',{signal});
     const rooms=new Map<string,SocialRoom>();
     for(const room of [...result.rooms,...(result.publicRooms||[])])if(room.type!=='jam'&&!rooms.has(room.id))rooms.set(room.id,room);
     data={friends:[],rooms:[...rooms.values()]};
    }
    if(!signal.aborted)setSnapshot({owner,data});
   }catch(reason){
    if(!signal.aborted)setSnapshot(previous=>({owner,data:previous?.owner===owner?previous.data:undefined,error:errorText(reason)}));
   }finally{pending=false;}
  };
  const changed=()=>{
   if(document.hidden)return;
   clearTimeout(scheduled);
   scheduled=setTimeout(()=>void refresh(),350);
  };
  void refresh();
  const timer=setInterval(changed,30000);
  player.socket?.on(event,changed);
  document.addEventListener('visibilitychange',changed);
  return()=>{
   controller.abort();
   clearInterval(timer);
   clearTimeout(scheduled);
   player.socket?.off(event,changed);
   document.removeEventListener('visibilitychange',changed);
  };
 },[kind,owner,player.socket,retry]);

 const open=()=>{
  store.navigate('rooms');
  if(kind==='friends'&&owner)location.hash='rooms?section=friends';
 };
 const join=(room:SocialRoom)=>{
  if(joining)return;
  if(player.room?.id===room.id){open();return;}
  setJoining(room.id);
  void store.run(async()=>{
   const next='state' in room?room:(await post<{room:Room}>('/rooms/join',{roomId:room.id})).room;
   if(owner!==activeOwner.current)return;
   await player.joinRoom(next);
   if(owner===activeOwner.current)open();
  }).finally(()=>setJoining(undefined));
 };

 const current=owner&&snapshot?.owner===owner?snapshot:undefined;
 const limit=widget.view==='compact'?3:widget.size==='large'?6:widget.size==='medium'?4:3;
 const activeRoom=player.room?.type==='room'?player.room:null;
 const rooms=current?.data?.rooms||[];
 const shownRooms=activeRoom?[activeRoom,...rooms.filter(room=>room.id!==activeRoom.id)]:rooms;
 const hasRows=kind==='friends'?Boolean(current?.data?.friends.length):Boolean(shownRooms.length);
 const Icon=kind==='friends'?Users:Headphones;
 const actionLabel=text(kind==='friends'?'friendsOpen':'roomsOpen');
 return <section className="canvas-social">
  <div className="section-heading">
   <h2>{text(kind)}</h2>
   {owner&&<button className="text-button" aria-label={actionLabel} onClick={open}>{actionLabel}<ArrowRight size={15}/></button>}
  </div>
  {!owner?<div className="canvas-social-empty"><Icon size={20}/><button className="text-button" onClick={()=>store.requireAuth()}>{t('copy.290')}<ArrowRight size={15}/></button></div>
  :!current&&!hasRows?<TrackSkeleton rows={2}/>
  :<>{current?.error&&<div className="canvas-social-empty"><p role="status">{current.error}</p><button className="text-button" onClick={()=>setRetry(value=>value+1)}><RefreshCw size={15}/>{t('copy.129')}</button></div>}
  {hasRows?<div className="canvas-social-grid">
   {kind==='friends'?current?.data?.friends.slice(0,limit).map(({user,activity})=>{
    const track=activity?.track;
    if(!track)return null;
    return <SocialRow key={user.id} name={user.displayName} caption={`${track.title} · ${track.artist}`} track={track}
     onClick={()=>void player.playTrack(track,[track])} label={`${t('copy.629')} · ${track.title}`} action={<Play size={15}/>}
     fallback={user.displayName.slice(0,1)} badge={user.avatarUrl?<img src={user.avatarUrl} alt=""/>:user.displayName.slice(0,1)}/>;
   }):shownRooms.slice(0,limit).map(room=>{
    const selected=player.room?.id===room.id,publicRoom=room.visibility==='public';
    const canJoin=!selected&&!store.offline&&player.connectionStatus==='online';
    const count=room.memberCount??room.members?.length??0;
    const caption=room.currentTrack?`${room.currentTrack.title} · ${room.currentTrack.artist}`:t(publicRoom?'connect.publicRoom':'connect.privateRoom');
    return <SocialRow key={room.id} name={room.name} caption={caption} track={room.currentTrack}
     onClick={canJoin?()=>join(room):open} label={`${canJoin?t('connect.joinRoom'):actionLabel} · ${room.name}`}
     disabled={canJoin&&!!joining} action={joining===room.id?'…':<ArrowRight size={16}/>}
     fallback={publicRoom?<Globe size={19}/>:<LockKeyhole size={17}/>} badge={count||undefined} badgeLabel={count?countLabel(count,'members'):undefined}/>;
   })}
  </div>:!current?.error&&<div className="canvas-social-empty"><Icon size={20}/><p>{text(kind==='friends'?'friendsEmpty':'roomsEmpty')}</p></div>}</>}
 </section>;
}

function SocialRow({name,caption,track,action,label,onClick,disabled=false,fallback,badge,badgeLabel}:{
 name:string;caption:string;track?:Track|null;action:React.ReactNode;label:string;onClick:()=>void;disabled?:boolean;
 fallback:React.ReactNode;badge?:React.ReactNode;badgeLabel?:string;
}){
 return <button className="canvas-social-row" type="button" aria-label={label} title={`${name} · ${caption}`} disabled={disabled} onClick={onClick}>
  <span className="canvas-social-art">{track?<Art track={track}/>:fallback}</span>
  <span className="canvas-social-label"><b>{name}</b><small>{caption}</small></span>
  {badge&&<span className="canvas-social-badge" aria-hidden="true" title={badgeLabel}>{badge}</span>}
  <span className="canvas-social-action" aria-hidden="true">{action}</span>
 </button>;
}
