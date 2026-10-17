import { useEffect, useRef, useState } from 'react';
import { ArrowUpRight, Check, ChevronDown, Layers3, Link, ListMusic, Music2, Search, UserRound, X } from 'lucide-react';
import { api, errorText } from './api';
import { t, useLocale } from './locale';
import { ArtistPage } from './parity-taste';
import { PlaylistArt, PublicPlaylist } from './parity-playlists';
import { SearchArtists, type SearchArtist } from './search-artists';
import { useStore } from './store';
import { Empty, Heading, IconButton, TrackList, TrackSkeleton } from './ui';
import { sourceNames, trackCount, type Playlist, type Source, type Track } from './types';

type SearchResult = { pendingProviders?:string[];tracks:Track[];artists?:SearchArtist[];playlists?:Playlist[];suggestion?:string|null;errors?:{provider?:string;message?:string;reason?:string}[] };
type ResultKind='all'|'tracks'|'artists'|'playlists';
const kinds=[['all',Layers3],['tracks',Music2],['artists',UserRound],['playlists',ListMusic]] as const;
const sources=['all','local','soundcloud','spotify','yandex','youtube'] as const;
const categories=[['copy.458','lofi hip hop',1,'copy.459'],['copy.460','late night jazz',2,'copy.461'],['copy.462','ambient instrumental',3,'copy.463'],['copy.464','indie pop',4,'copy.465'],['copy.466','chill electronic',5,'copy.467']] as const;

function SourceMenu(){
 const store=useStore(),[open,setOpen]=useState(false),root=useRef<HTMLDivElement>(null),trigger=useRef<HTMLButtonElement>(null);
 useEffect(()=>{if(!open)return;const close=(event:PointerEvent)=>{if(!root.current?.contains(event.target as Node))setOpen(false);};document.addEventListener('pointerdown',close);return()=>document.removeEventListener('pointerdown',close);},[open]);
 return <div ref={root} className="discovery-source-menu" onKeyDown={event=>{if(event.key==='Escape'){event.stopPropagation();setOpen(false);trigger.current?.focus();}}}><button ref={trigger} className="discovery-source-trigger" aria-haspopup="menu" aria-expanded={open} onClick={()=>setOpen(!open)}><span>{store.source==='all'?t('copy.502'):sourceNames[store.source as Source]}</span><ChevronDown size={15}/></button>{open&&<div className="discovery-source-options" role="menu" aria-label={t('polish.search.sources')}>{sources.map(source=><button key={source} role="menuitemradio" aria-checked={store.source===source} onClick={()=>{store.setSource(source);setOpen(false);trigger.current?.focus();}}>{source==='all'?t('copy.502'):sourceNames[source]}{store.source===source&&<Check size={15}/>}</button>)}</div>}</div>;
}

export function DiscoverySearchPage(){
 useLocale();const store=useStore(),query=store.query.trim(),[result,setResult]=useState<SearchResult>({tracks:[]}),[loading,setLoading]=useState(false),[error,setError]=useState(''),[kind,setKind]=useState<ResultKind>('all'),[artist,setArtist]=useState<SearchArtist|null>(null),[playlist,setPlaylist]=useState<Playlist|null>(null);
 useEffect(()=>{
  setResult({tracks:[]});setError('');if(!query){setLoading(false);return;}
  const controller=new AbortController(),base=`/search?q=${encodeURIComponent(query)}&source=${encodeURIComponent(store.source)}`;
  setLoading(true);
  const timer=setTimeout(()=>{
   const direct=/^https?:\/\//.test(query),request=direct?api<{track:Track}>('/tracks/resolve',{method:'POST',body:JSON.stringify({url:query}),signal:controller.signal}).then(value=>({tracks:[value.track]} as SearchResult)):api<SearchResult>(base+'&fast=1',{signal:controller.signal});
   void request.then(value=>{
    if(controller.signal.aborted)return;setResult(value);store.remember(value.tracks);setLoading(false);
    if(!direct&&value.pendingProviders?.length)void api<SearchResult>(base,{signal:controller.signal}).then(complete=>{if(controller.signal.aborted)return;setResult(complete);store.remember(complete.tracks);}).catch(()=>{/* Keep useful first results through an optional provider outage. */});
   }).catch(reason=>{if(!controller.signal.aborted)setError(errorText(reason));}).finally(()=>{if(!controller.signal.aborted)setLoading(false);});
  },300);
  return()=>{clearTimeout(timer);controller.abort();};
 },[query,store.source,store.remember,store.user?.id]);
 const artists=result.artists||[],playlists=result.playlists||[],hasResults=!!(result.tracks.length||artists.length||playlists.length),visible=(which:ResultKind)=>kind==='all'||kind===which;
 return <section className={`view discovery-search-view ${query?'has-query':''}`}><Heading eyebrow={t('copy.496')} title={query?t('polish.search.results'):t('copy.497')} description={query?undefined:t('copy.498')}/>
  <form className="page-search discovery-query" onSubmit={event=>event.preventDefault()}><Search size={20}/><input type="search" value={store.query} onChange={event=>store.setQuery(event.target.value)} aria-label={t('copy.499')} placeholder={t('copy.500')}/>{query&&<IconButton title={t('copy.501')} onClick={()=>store.setQuery('')}><X size={18}/></IconButton>}</form>
  <div className="discovery-filter-row"><nav className="discovery-result-tabs" aria-label={t('polish.search.types')}>{kinds.map(([value,Icon])=><button key={value} aria-pressed={kind===value} className={kind===value?'selected':''} onClick={()=>setKind(value)}><Icon size={16}/><span>{t(`polish.search.${value}`)}</span></button>)}</nav><SourceMenu/></div>
  {result.suggestion&&<div className="layout-suggestion">{t('copy.503')}{' '}<button onClick={()=>store.setQuery(result.suggestion!)}>{result.suggestion}</button><small>{t('copy.504')}</small></div>}
  {error&&<p className="error-banner" role="alert">{error}</p>}
  {!!result.errors?.length&&<details className="provider-errors"><summary>{t('copy.505')}</summary>{result.errors.map((item,index)=><p key={index}>{item.provider&&`${sourceNames[item.provider as Source]||item.provider}: `}{t('copy.506')}</p>)}</details>}
  {loading?<TrackSkeleton label={t('copy.507')}/>:query?<div className="discovery-results">
   {visible('tracks')&&result.tracks.length>0&&<section className="discovery-track-results"><div className="section-heading"><h2>{t('search.tracks')}</h2>{kind==='all'&&<button className="text-button" onClick={()=>setKind('tracks')}>{t('polish.search.seeAll')}<ArrowUpRight size={15}/></button>}</div><TrackList tracks={kind==='all'?result.tracks.slice(0,8):result.tracks}/></section>}
   {visible('artists')&&artists.length>0&&<SearchArtists artists={artists} onSelect={setArtist}/>}
   {visible('playlists')&&playlists.length>0&&<section className="discovery-playlist-results"><div className="section-heading"><h2>{t('polish.search.playlists')}</h2>{kind==='all'&&<button className="text-button" onClick={()=>setKind('playlists')}>{t('polish.search.seeAll')}<ArrowUpRight size={15}/></button>}</div><div className="discovery-playlist-strip">{playlists.map(item=><button className="discovery-playlist" key={item.id} onClick={()=>setPlaylist(item)}><PlaylistArt playlist={item}/><b>{item.name}</b><small>{trackCount(item.trackIds.length)}</small></button>)}</div></section>}
   {(!hasResults||kind==='tracks'&&!result.tracks.length||kind==='artists'&&!artists.length||kind==='playlists'&&!playlists.length)&&<Empty icon={<Search/>} title={t('polish.search.empty')}><p>{t('polish.search.emptyHint')}</p><button className="text-button" onClick={()=>{setKind('all');store.setSource('all');}}>{t('polish.search.reset')}</button></Empty>}
  </div>:<><div className="section-heading discovery-category-heading"><h2>{t('copy.508')}</h2></div><div className="discovery-category-grid">{categories.map(([label,term,image,detail])=><button key={term} onClick={()=>{setKind('all');store.setQuery(term);}}><img src={`/assets/asset-${image}.jpg`} alt="" loading="lazy"/><span><b>{t(label)}</b><small>{t(detail)}</small></span><ArrowUpRight size={19}/></button>)}</div><div className="search-hint"><Link size={19}/><p>{t('copy.509')}<small>{t('copy.510')}</small></p></div></>}
  {artist&&<ArtistPage artist={artist} onClose={()=>setArtist(null)}/>} {playlist&&<PublicPlaylist playlist={playlist} onClose={()=>setPlaylist(null)}/>}
 </section>;
}
