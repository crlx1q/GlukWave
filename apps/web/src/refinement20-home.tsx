import {useEffect,useRef,useState} from 'react';
import {ArrowRight,ArrowUpRight} from 'lucide-react';
import {api} from './api';
import {useStore} from './store';
import {usePlayer} from './player';
import {t,useLocale} from './locale';
import {Art,TrackSkeleton} from './ui';
import {PlaylistArt} from './parity-playlists';
import {type Track,trackCount} from './types';
import {refinementText as text} from './refinement20-strings';
const choices=[{key:'calm',name:'copy.458',caption:'copy.459'},{key:'dream',name:'copy.460',caption:'copy.461'},{key:'focus',name:'copy.462',caption:'copy.463'},{key:'happy',name:'copy.464',caption:'copy.465'}] as const;
/** These shelves use the same recommendation engine as Wave. Work begins once
    visible, cancels with the account/page, and never invents charts or artists. */
function RecommendationShelf({mode,initial=false,onData}:{mode:'personal'|'discovery'|'popular';initial?:boolean;onData?:(tracks:Track[])=>void}){
 const store=useStore(),player=usePlayer(),root=useRef<HTMLElement>(null),[visible,setVisible]=useState(initial),[tracks,setTracks]=useState<Track[]>([]),[pending,setPending]=useState(false),[failed,setFailed]=useState(false);
 useEffect(()=>{if(visible)return;const node=root.current;if(!node)return;const observer=new IntersectionObserver(entries=>{if(entries.some(item=>item.isIntersecting)){setVisible(true);observer.disconnect();}},{rootMargin:'100px'});observer.observe(node);return()=>observer.disconnect();},[visible]);
 useEffect(()=>{if(!visible||!store.user)return;const abort=new AbortController();setPending(true);setFailed(false);setTracks([]);void api<{tracks:Track[]}>(`/recommendations?mode=${mode}&mood=personal&limit=8`,{signal:abort.signal}).then(data=>{if(!abort.signal.aborted){const actual=[...new Map((data.tracks||[]).map(track=>[track.id,track])).values()];setTracks(actual);onData?.(actual);}}).catch(()=>{if(!abort.signal.aborted)setFailed(true);}).finally(()=>{if(!abort.signal.aborted)setPending(false);});return()=>abort.abort();},[store.user?.id,mode,visible]);
 return <section ref={root} className="home-discovery-rail" aria-label={text(mode==='personal'?'forYou':mode==='discovery'?'discover':'popular')}>
  <div className="section-heading"><div><h2>{text(mode==='personal'?'forYou':mode==='discovery'?'discover':'popular')}</h2><p className="section-caption">{t(`wave18.caption.${mode}`)}</p></div><button className="text-button" onClick={()=>void store.run(()=>player.startWave({mode}))}>{t('copy.406')}<ArrowRight size={15}/></button></div>
  {pending?<TrackSkeleton rows={2}/>:tracks.length?<div className="recent-strip">{tracks.map(track=><article key={track.id} className={player.track?.id===track.id?'current':''}><Art track={track} onClick={()=>void player.playTrack(track,tracks)}/><button className="recent-title" onClick={()=>void player.playTrack(track,tracks)}><b>{track.title}</b><small>{track.artist}</small></button></article>)}</div>:<p className="section-caption">{failed?text('recommendationsUnavailable'):t('v7.home.beginCaption')}</p>}
 </section>;
}
export function HomeDiscovery(){
 useLocale();const store=useStore(),player=usePlayer(),[recommendations,setRecommendations]=useState<Track[]>([]),pool=[...new Map([...recommendations,...store.library.tracks].filter(track=>track.artwork).map(track=>[track.id,track])).values()];
 useEffect(()=>setRecommendations([]),[store.user?.id]);
 return <>
  <RecommendationShelf mode="personal" initial onData={setRecommendations}/>
  <section className="home-discover"><div className="section-heading"><div><h2>{t('copy.482')}</h2><p className="section-caption">{t('v7.home.discoverCaption')}</p></div></div><div className="collection-grid">{choices.map((choice,index)=><button className="collection-card" key={choice.key} onClick={()=>void store.run(()=>player.startWave({mood:choice.key}))}><div className="collection-art">{pool.slice(index*4,index*4+4).map(track=><Art key={track.id} track={track}/>)}{!pool.slice(index*4,index*4+4).length&&<span className="collection-word">∿</span>}<span className="collection-arrow"><ArrowUpRight size={17}/></span></div><h3>{t(choice.name)}</h3><p>{t(choice.caption)}</p></button>)}</div></section>
  <RecommendationShelf mode="discovery"/>
  {store.library.playlists.length>0&&<section className="home-playlist-discovery"><div className="section-heading"><h2>{text('playlists')}</h2><button className="text-button" onClick={()=>store.navigate('library')}>{t('copy.487')}<ArrowRight size={15}/></button></div><div className="playlist-grid">{store.library.playlists.slice(0,8).map(playlist=><article className="library-playlist" key={playlist.id}><button className="playlist-art" onClick={()=>{store.navigate('library');location.hash=`library?playlist=${encodeURIComponent(playlist.id)}`;}}><PlaylistArt playlist={playlist}/></button><button className="playlist-name" onClick={()=>{store.navigate('library');location.hash=`library?playlist=${encodeURIComponent(playlist.id)}`;}}><b>{playlist.name}</b><small>{trackCount(playlist.trackIds.length)}</small></button></article>)}</div></section>}
  <RecommendationShelf mode="popular"/>
 </>;
}
