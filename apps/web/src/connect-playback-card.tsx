import {usePlayer} from './player';
import {useStore} from './store';
import {t,useLocale} from './locale';
import {time} from './types';
import {Art,IconButton} from './ui';
import {AnimatedIcon,PlaybackIcon,ListeningMotionIcon} from './morph-icon';
import {ContinuousRange} from './continuous-range';
import {DevicePlatformIcon} from './device-platform';

/** One confirmed output and one set of controls, shared by both Connect surfaces. */
export function ConnectPlaybackCard(){
 useLocale();const player=usePlayer(),store=useStore(),active=player.devices.find(device=>device.id===player.connectState?.activeDeviceId),track=player.track,room=player.room;
 const permitted=!room||store.user?.role==='admin'||room.canControl===true||room.ownerId===store.user?.id||!!room.members.find(member=>member.userId===store.user?.id)?.canControl;
 const key=`${store.user?.id}:${room?.id}:${player.connectState?.activeDeviceId}:${track?.id}`;
 if(!track)return <p className="connect-idle-caption">{t('copy.304')}</p>;
 return <section className="connect-playback-card" aria-label={t('focusedPlayer.nowPlaying')}>
  <div className="connect-track-line"><Art track={track}/><span><b>{track.title}</b><small>{track.artist}</small></span><ListeningMotionIcon playing={player.state.playing} loading={player.trackLoading||player.transportPending} size={20}/></div>
  <p className="connect-output-line">{active&&<DevicePlatformIcon kind={active.kind} name={active.name} size={13}/>}<span>{active?t(player.state.playing?'connect.playingOn':'connect.pausedOn',{device:active.name}):t('connect.chooseOutput')}</span></p>
  <div className="connect-mini-transport"><IconButton title={t('copy.627')} disabled={!permitted||player.trackLoading||player.transportPending} onClick={()=>void store.run(()=>player.command({command:'previous'}))}><AnimatedIcon name="previous" size={20}/></IconButton><button className="main-play" disabled={!permitted&&room?.type!=='jam'} aria-label={t(player.state.playing?'copy.628':'copy.629')} aria-busy={player.trackLoading||player.transportPending} onClick={()=>void store.run(()=>player.command({command:player.state.playing?'pause':'play'}))}><PlaybackIcon playing={player.state.playing} loading={player.trackLoading||player.transportPending} size={23}/></button><IconButton title={t('copy.630')} disabled={!permitted||player.trackLoading||player.transportPending} onClick={()=>void store.run(()=>player.command({command:'next'}))}><AnimatedIcon name="next" size={20}/></IconButton></div>
  <div className="connect-mini-seek"><span>{time(player.state.position)}</span><ContinuousRange value={player.state.position} max={Math.max(1,player.duration)} label={t('copy.634')} resetKey={key} disabled={!permitted||player.trackLoading||player.transportPending} onCommit={position=>void store.run(()=>player.command({command:'seek',position}))}/><span>{time(player.duration)}</span></div>
  <div className="connect-mini-volume"><AnimatedIcon name={player.state.volume===0?'muted':player.state.volume<.5?'volumeLow':'volume'} size={17}/><ContinuousRange value={player.state.volume} max={1} step={.01} label={t('copy.643')} resetKey={key} onDraft={volume=>player.previewCommand({command:'volume',volume})} onCancel={()=>player.cancelPreview('volume')} onCommit={volume=>void store.run(()=>player.command({command:'volume',volume}))}/><output>{Math.round(player.state.volume*100)}%</output></div>
  {!permitted&&<p className="connect-control-caption">{t(room?.type==='jam'?'ecosystem17.jamOwnPause':'v7.rooms.listenOnly')}</p>}
  {player.autoplayBlocked&&<button className="connect-audio-unlock" onClick={()=>void store.run(()=>player.command({command:'play'}))}>{t('copy.644')}</button>}
 </section>;
}
