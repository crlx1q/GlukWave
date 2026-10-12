import {Headphones} from 'lucide-react';
import {t,useLocale} from './locale';
import {usePlayer} from './player';
import {useStore} from './store';
export function RoomAvatars(){
 useLocale();const {room}=usePlayer();if(!room)return null;const online=room.members.filter(member=>member.online),listening=online.filter(member=>member.devices?.some(device=>device.outputActive&&device.playing));
 return <span className="room-avatar-group" aria-label={t('ecosystem.listeningCount',{count:listening.length,online:online.length})}>{online.slice(0,3).map(member=><span className={`room-avatar ${listening.includes(member)?'is-listening':''}`} title={member.displayName} key={member.userId}>{member.avatarUrl?<img src={member.avatarUrl} alt={member.displayName} decoding="async"/>:<span aria-label={member.displayName}>{member.displayName.slice(0,1)}</span>}</span>)}{online.length>3&&<span className="room-avatar-overflow">+{online.length-3}</span>}</span>;
}
export function ListeningTogether(){
 useLocale();const {room}=usePlayer(),store=useStore();if(!room)return null;const online=room.members.filter(member=>member.online),listening=online.filter(member=>member.devices?.some(device=>device.outputActive&&device.playing));
 return <button className="listening-together" onClick={()=>store.navigate('rooms')} title={online.map(member=>member.displayName).join(', ')}><RoomAvatars/>{!online.length&&<Headphones size={14}/>}<span><b>{room.name}</b><small>{t('ecosystem.listeningCount',{count:listening.length,online:online.length})}</small></span></button>;
}
