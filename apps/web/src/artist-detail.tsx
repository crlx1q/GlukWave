import { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';
import { ArrowLeft, ExternalLink, Play, Shuffle } from 'lucide-react';
import { api, errorText } from './api';
import { cachedMetadata, peekMetadata, readCachedMetadata } from './metadata-cache';
import { t, useLocale } from './locale';
import { useStore } from './store';
import { usePlayer } from './player';
import { Art, Empty, TrackList, TrackSkeleton } from './ui';
import { PublicPlaylist } from './parity-playlists';
import { sourceNames, type Artist, type Playlist, type Source, type Track } from './types';

type Album={id:string;name:string;artwork:string;trackIds:string[]};
type Profile={artist:Artist&{bio?:string;banner?:string};tracks:Track[];albums?:Album[];playlists?:Playlist[]};

/** Dedicated local route: opening an artist preserves the shell's search and
 * library state. Browser Back closes the profile just like the native route. */
export function ArtistDetail({artist,onClose}:{artist:Artist;onClose:()=>void}){
 useLocale();const store=useStore(),player=usePlayer(),[data,setData]=useState<Profile>(()=>store.user?peekMetadata<Profile>(store.user.id,`/artists/${encodeURIComponent(artist.id)}`)||{artist,tracks:[]}:{artist,tracks:[]}),[loading,setLoading]=useState(true),[error,setError]=useState(''),[reload,setReload]=useState(0),[album,setAlbum]=useState<Album|null>(null),[playlist,setPlaylist]=useState<Playlist|null>(null);
 useEffect(()=>{const saved=document.body.style.overflow;document.body.style.overflow='hidden';history.pushState({...history.state,gwArtist:artist.id},'',location.href);const back=()=>onClose();window.addEventListener('popstate',back);const key=(event:KeyboardEvent)=>{if(event.key==='Escape'&&!document.querySelector('dialog[open]'))onClose();};window.addEventListener('keydown',key);return()=>{document.body.style.overflow=saved;window.removeEventListener('popstate',back);window.removeEventListener('keydown',key);if(history.state?.gwArtist===artist.id)history.back();};},[artist.id]);
 useEffect(()=>{
  const controller=new AbortController(),path=`/artists/${encodeURIComponent(artist.id)}`,account=store.user?.id;
  setLoading(!data.tracks.length);setError('');
  void(async()=>{
   if(account){const saved=await readCachedMetadata<Profile>(account,path);if(saved&&!controller.signal.aborted){setData(saved);setLoading(false);}}
   let result=account?await cachedMetadata<Profile>(path,{account,signal:controller.signal,maxAge:600000,force:reload>0}):await api<Profile>(path,{signal:controller.signal});
   if(!result.tracks?.length){const found=await api<{tracks:Track[]}>(`/search?q=${encodeURIComponent(artist.name)}&source=${encodeURIComponent(artist.source)}`,{signal:controller.signal});result={...result,tracks:found.tracks.filter(track=>track.artist.toLocaleLowerCase().includes(artist.name.toLocaleLowerCase()))};}
   if(!controller.signal.aborted){setData(result);store.remember(result.tracks);}
  })().catch(reason=>{if(!controller.signal.aborted)setError(errorText(reason));}).finally(()=>{if(!controller.signal.aborted)setLoading(false);});
  return()=>controller.abort();
 },[artist.id,artist.source,reload,store.user?.id]);
 const profile={...artist,...data.artist},tracks=album?data.tracks.filter(track=>album.trackIds.includes(track.id)):data.tracks,sourceUrl=profile.sourceUrl&&/^https:\/\//i.test(profile.sourceUrl)?profile.sourceUrl:null;
 const play=(shuffle=false)=>{if(!tracks.length)return;const order=[...tracks];if(shuffle)for(let i=order.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[order[i],order[j]]=[order[j],order[i]];}player.setShuffle(shuffle);void player.playTrack(order[0],order);};
 return createPortal(<section className="artist-detail" aria-label={profile.name} role="main"><div className="artist-detail-inner"><header className="artist-detail-nav"><button className="subtle-button" autoFocus onClick={()=>album?setAlbum(null):onClose()}><ArrowLeft size={17}/>{album?profile.name:t('copy.196')}</button><small>GLUKWAVE / {t('search.artist')}</small></header><div className="artist-detail-hero"><div className="artist-detail-portrait">{profile.artwork?<img src={profile.artwork} alt=""/>:<span>{profile.name.slice(0,1)}</span>}</div><div><p className="eyebrow">{sourceNames[profile.source as Source]||t('search.artist')}</p><h1>{album?.name||profile.name}</h1>{sourceUrl&&<a className="text-button" href={sourceUrl} target="_blank" rel="noopener noreferrer">{t('v26.artist.source')}<ExternalLink size={14}/></a>}</div></div>{profile.bio&&<p className="artist-detail-bio">{profile.bio}</p>}{data.tracks.length>0&&<div className="artist-detail-actions"><button className="primary-button" onClick={()=>play()}><Play size={17}/>{t('v26.artist.playAll')}</button><button className="subtle-button" onClick={()=>play(true)}><Shuffle size={17}/>{t('v26.artist.shuffle')}</button></div>}{loading&&!data.tracks.length?<TrackSkeleton/>:error&&!data.tracks.length?<Empty title={t('copy.154')} action={<button className="subtle-button" onClick={()=>setReload(value=>value+1)}>{t('copy.129')}</button>}>{error}</Empty>:<TrackList tracks={tracks} empty={t('v26.artist.empty')}/>} {!album&&!!data.albums?.length&&<section className="artist-detail-records"><h2>{t('v26.artist.albums')}</h2><div>{data.albums.filter(item=>item.trackIds.some(id=>data.tracks.some(track=>track.id===id))).map(item=><button key={item.id} onClick={()=>setAlbum(item)}><Art track={{...data.tracks.find(track=>item.trackIds.includes(track.id))!,artwork:item.artwork}}/><b>{item.name}</b></button>)}</div></section>}{!album&&!!data.playlists?.length&&<section className="artist-detail-records"><h2>{t('v26.artist.playlists')}</h2><div>{data.playlists.map(item=><button key={item.id} onClick={()=>setPlaylist(item)}><span className="art">{item.artwork?<img src={item.artwork} alt=""/>:item.name.slice(0,1)}</span><b>{item.name}</b></button>)}</div></section>}{playlist&&<PublicPlaylist playlist={playlist} onClose={()=>setPlaylist(null)}/>}</div></section>,document.body);
}
