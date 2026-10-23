import {useRef,useState} from 'react';
import {ArrowUpRight,ArrowRight,Heart,Music2,Radio,Sun,Focus,Moon,Sparkles,Play,Search} from 'lucide-react';
import {useStore} from './store';
import {usePlayer} from './player';
import {api,errorText} from './api';
import {t,useLocale} from './locale';
import {ui27} from './glukwave27-copy';
import {canvasText as text} from './home-canvas-copy';
import {PersonalWave} from './home-wave';
import {RecommendationShelf} from './refinement20-home';
import {Art,TrackSkeleton} from './ui';
import {PlaylistArt} from './parity-playlists';
import type {HomeWidget,Track} from './types';
import {trackCount} from './types';
import {likedTracks} from './library-order';
export function widgetTitle(widget:HomeWidget,playlists:{id:string;name:string}[]){return widget.type==='playlist'?playlists.find(item=>item.id===widget.playlistId)?.name||text('playlist'):widget.type==='mix'?widget.genre||text('mix'):text(widget.type);}
const today=()=>{const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;};
export function HomeWidgetContent({widget,upload}:{widget:HomeWidget;upload:()=>void}){
 useLocale();const store=useStore(),player=usePlayer(),[pending,setPending]=useState<string|null>(null),account=useRef(store.user?.id);account.current=store.user?.id;
 const playMix=async(key:string,query:string)=>{const owner=account.current;setPending(key);try{const data=await api<{tracks:Track[]}>(`/recommendations?${query}&day=${today()}&limit=30`);if(owner!==account.current)return;if(!data.tracks?.length){store.notify(ui27('noTracks'));return;}await player.playTrack(data.tracks[0],data.tracks);}catch(reason){if(owner===account.current)store.notify(errorText(reason),true);}finally{if(owner===account.current)setPending(null);}};
 const open=(id?:string)=>{store.navigate('library');if(id)location.hash=`library?playlist=${encodeURIComponent(id)}`;};
 if(widget.type==='wave')return <PersonalWave upload={upload}/>;
 if(widget.type==='recommendations'||widget.type==='popular')return <RecommendationShelf mode={widget.type==='popular'?'popular':'personal'} initial/>;
 if(widget.type==='discovery')return <><RecommendationShelf mode="discovery"/><div className="canvas-moods">{(['calm','dream','focus','happy'] as const).map((mood,i)=>{const Icon=[Moon,Sparkles,Focus,Sun][i];return <button key={mood} onClick={()=>void store.run(()=>player.startWave({mood}))}><Icon size={18}/><span>{t(`wave18.mood.${mood}`)}</span><ArrowUpRight size={14}/></button>;})}</div></>;
 if(widget.type==='daily')return <section className="canvas-daily"><WidgetHeading title={text('daily')}/><div className="canvas-daily-grid">{([{id:'morning',Icon:Sun},{id:'focus',Icon:Focus},{id:'evening',Icon:Moon},{id:'discovery',Icon:Sparkles}] as const).map(({id,Icon})=><button key={id} disabled={!!pending} onClick={()=>void playMix(id,`mix=${id}`)}><Icon size={23}/><b>{ui27(id)}</b><span>{pending===id?'…':<ArrowUpRight size={15}/>}</span></button>)}</div></section>;
 if(widget.type==='playlists')return <section className="canvas-playlists"><WidgetHeading title={text('playlists')} action={()=>open()}/>{store.libraryLoading&&!store.library.playlists.length?<TrackSkeleton rows={2}/>:store.library.playlists.length?<div className="canvas-playlist-grid">{store.library.playlists.slice(0,widget.view==='compact'?4:8).map(playlist=><button className="canvas-playlist" key={playlist.id} onClick={()=>open(playlist.id)}><span className="canvas-playlist-art"><PlaylistArt playlist={playlist}/><Play size={20}/></span><span className="canvas-playlist-title"><b>{playlist.name}</b><small>{trackCount(playlist.trackIds.length)}</small></span>{widget.view!=='cards'&&<ArrowUpRight size={16}/>}</button>)}</div>:<div className="canvas-empty-content"><Music2 size={25}/><p>{text('emptyLists')}</p><button className="text-button" onClick={()=>open()}>{text('library')}<ArrowRight size={15}/></button></div>}</section>;
 if(widget.type==='recent'){
  const tracks=[...new Set(store.library.history.map(item=>item.trackId))].map(id=>store.library.tracks.find(track=>track.id===id)).filter(Boolean) as Track[];
  return <section className="canvas-recent"><WidgetHeading title={text('recent')} action={()=>{open();location.hash='library?tab=history';}}/>{store.libraryLoading&&!tracks.length?<TrackSkeleton rows={2}/>:tracks.length?<div className="recent-strip">{tracks.slice(0,widget.view==='compact'?3:8).map(track=><article key={track.id} className={player.track?.id===track.id?'current':''}><Art track={track} onClick={()=>void player.playTrack(track,tracks)}/><button className="recent-title" onClick={()=>void player.playTrack(track,tracks)}><b>{track.title}</b><small>{track.artist}</small></button></article>)}</div>:<div className="canvas-empty-content"><p>{t('v7.home.beginCaption')}</p><button className="text-button" onClick={()=>store.navigate('search')}><Search size={17}/>{t('copy.171')}</button></div>}</section>;
 }
 const playlist=widget.type==='playlist'?store.library.playlists.find(item=>item.id===widget.playlistId):null;
 const tracks=widget.type==='likes'?likedTracks(store.library):playlist?playlist.trackIds.map(id=>store.library.tracks.find(item=>item.id===id)).filter(Boolean) as Track[]:[];
 const title=widgetTitle(widget,store.library.playlists),Icon=widget.type==='likes'?Heart:widget.type==='mix'?Radio:Music2;
 const activate=()=>{if(widget.type==='mix')void playMix(widget.id,`genre=${encodeURIComponent(widget.genre||'')}&mood=${widget.mood||'personal'}`);else if(widget.type==='likes'){open();location.hash='library?tab=liked';}else if(playlist)open(playlist.id);};
 return <section className={`canvas-destination destination-${widget.type}`}><button className="canvas-destination-open" aria-label={`${title} · ${widget.type==='mix'?text('mix'):trackCount(tracks.length)}`} disabled={!!pending||widget.type==='playlist'&&!playlist} onClick={activate}><span className="canvas-destination-art">{playlist?<PlaylistArt playlist={playlist}/>:tracks[0]?.artwork?<Art track={tracks[0]}/>:<Icon size={widget.view==='cards'?38:25}/>}<span className="canvas-destination-symbol"><Icon size={16}/></span></span><span className="canvas-destination-title"><b>{title}</b><small>{pending===widget.id?'…':widget.type==='mix'?text('mix'):widget.type==='playlist'&&!playlist?text('unavailable'):trackCount(tracks.length)}</small></span><ArrowUpRight size={18}/></button>{widget.view==='list'&&tracks.slice(0,3).map(track=><button className="canvas-destination-track" key={track.id} onClick={()=>void player.playTrack(track,tracks)}><Art track={track}/><span><b>{track.title}</b><small>{track.artist}</small></span><Play size={15}/></button>)}</section>;
}
function WidgetHeading({title,action}:{title:string;action?:()=>void}){return <div className="section-heading"><h2>{title}</h2>{action&&<button className="text-button" onClick={action} aria-label={`${title} · ${text('library')}`}><ArrowRight size={18}/></button>}</div>;}
