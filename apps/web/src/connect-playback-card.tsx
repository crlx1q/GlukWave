import {usePlayer} from './player';
import {t,useLocale} from './locale';
import {Art} from './ui';
import {ListeningMotionIcon} from './morph-icon';
import {DevicePlatformIcon} from './device-platform';

/** One confirmed output summary. The persistent player owns transport controls. */
export function ConnectPlaybackCard(){
 useLocale();const player=usePlayer(),active=player.devices.find(device=>device.id===player.connectState?.activeDeviceId),track=player.track;
 if(!track)return <p className="connect-idle-caption">{t('copy.304')}</p>;
 return <section className="connect-playback-card connect-output-summary" aria-label={t('focusedPlayer.nowPlaying')}>
  <div className="connect-track-line"><Art track={track}/><span><b>{track.title}</b><small>{track.artist}</small></span><ListeningMotionIcon playing={player.state.playing} loading={player.trackLoading||player.transportPending} size={20}/></div>
  <p className="connect-output-line">{active&&<DevicePlatformIcon kind={active.kind} name={active.name} size={13}/>}<span>{active?t(player.state.playing?'connect.playingOn':'connect.pausedOn',{device:active.name}):t('connect.chooseOutput')}</span></p>
  {player.autoplayBlocked&&<button className="connect-audio-unlock" onClick={()=>void player.resumePlayback()}>{t('copy.644')}</button>}
 </section>;
}
