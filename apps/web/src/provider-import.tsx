import {ProviderAccess} from './provider-access';
import {useEffect,useRef,useState} from 'react';
import {ArrowLeft,ArrowRight,Check,Heart,Music2,RefreshCw,Search} from 'lucide-react';
import {api,errorText,post} from './api';
import {useStore} from './store';
import {t,useLocale} from './locale';
import {Art,Empty,Loading,Modal} from './ui';
import {sourceNames,trackCount,type Source,type Track,type Playlist} from './types';
import {refinementText as text} from './refinement20-strings';
import {publicImportText as copy} from './public-import-copy';
import './public-import.css';

type Collection={id:string;name:string;description?:string;artwork?:string;trackCount:number;sourceUrl?:string;kind?:string};
type Exposure={partial?:boolean;warnings?:string[]};
type Imported=Exposure&{playlist:Playlist|null;imported:number;deduplicated?:number;unavailable?:number;tasteSeeded?:boolean;destination?:string};
const mergeWarnings=(...lists:(string[]|undefined)[])=>[...new Set(lists.flatMap(list=>list||[]))];

export function ProviderImport({provider,onClose,connected=false}:{provider:Source;onClose:()=>void;connected?:boolean}){
 useLocale();const store=useStore(),account=store.user?.id;
 const [authorized,setAuthorized]=useState(connected);
 const [mode,setMode]=useState<'public'|'connected'>('public'),[query,setQuery]=useState(''),[searched,setSearched]=useState(false);
 const [collections,setCollections]=useState<Collection[]>([]),[collection,setCollection]=useState<Collection|null>(null),[tracks,setTracks]=useState<Track[]>([]),[selection,setSelection]=useState(new Set<string>()),[cursor,setCursor]=useState<string|null>(null),[busy,setBusy]=useState(false),[saving,setSaving]=useState(false),[error,setError]=useState(''),[all,setAll]=useState(true),[destination,setDestination]=useState<'playlist'|'likes'>('playlist'),[result,setResult]=useState<Imported|null>(null);
 const [exposure,setExposure]=useState<Exposure>({}),[searchExposure,setSearchExposure]=useState<Exposure>({});
 const generation=useRef(0),intent=useRef<{signature:string;id:string}|null>(null),saveLock=useRef(false),root=useRef<HTMLDivElement>(null),alive=useRef(true),scope=useRef(''),retry=useRef<()=>Promise<void>>(()=>Promise.resolve());
 const context=`${account||''}:${provider}:${mode}`;scope.current=context;
 const valid=(version:number)=>alive.current&&version===generation.current&&scope.current===context;
 const close=()=>{if(saveLock.current)return;alive.current=false;generation.current++;onClose();};
 const reset=()=>{generation.current++;setCollections([]);setCollection(null);setTracks([]);setSelection(new Set());setCursor(null);setBusy(false);setSaving(false);setError('');setResult(null);setSearched(false);setExposure({});setSearchExposure({});intent.current=null;saveLock.current=false;};
 const loadCollections=async()=>{
  if(!account||mode==='public'&&!query.trim())return;
  retry.current=loadCollections;const version=++generation.current;setBusy(true);setError('');setSearched(true);setCollections([]);setExposure({});setSearchExposure({});
  try{const data=mode==='public'?await post<Exposure&{playlists:Collection[];liked?:Collection}>('/public-import/search',{provider,query:query.trim()}):await api<Exposure&{playlists:Collection[];liked?:Collection}>(`/integrations/${provider}/playlists`);
   if(valid(version)){setCollections([...(data.liked?[data.liked]:[]),...(data.playlists||[])]);setExposure(data);setSearchExposure(data);}
  }catch(reason){if(valid(version))setError(errorText(reason));}finally{if(valid(version))setBusy(false);}
 };
 useEffect(()=>{alive.current=true;reset();setQuery('');if(mode==='connected'&&authorized)void loadCollections();return()=>{generation.current++;};},[provider,account,mode,authorized]);
 useEffect(()=>{const dialog=root.current?.closest('dialog'),cancel=(event:Event)=>{if(saveLock.current)event.preventDefault();};dialog?.addEventListener('cancel',cancel);return()=>{alive.current=false;generation.current++;dialog?.removeEventListener('cancel',cancel);};},[]);
 useEffect(()=>{root.current?.closest('dialog')?.scrollTo({top:0});},[collection?.id,!!result]);
 const loadTracks=async(value:Collection,next?:string|null)=>{
  if(saveLock.current)return;retry.current=()=>loadTracks(value,next);const version=++generation.current;setBusy(true);setError('');
  if(!next){setCollection(value);setTracks([]);setSelection(new Set());setCursor(null);setDestination(value.kind==='likes'||value.id==='liked'?'likes':'playlist');setAll(true);setExposure(searchExposure);intent.current=null;}
  try{const data=mode==='public'?await post<Exposure&{tracks:Track[];nextCursor?:string|null;total?:number}>('/public-import/tracks',{provider,sourceUrl:value.sourceUrl,...(next?{cursor:next}:{})}):await api<Exposure&{tracks:Track[];nextCursor?:string|null;total?:number}>(`/integrations/${provider}/playlists/${encodeURIComponent(value.id)}/tracks${next?`?cursor=${encodeURIComponent(next)}`:''}`);
   if(valid(version)){const items=data.tracks||[],knownIds=new Set(next?tracks.map(track=>track.id):[]),merged=next?[...new Map([...tracks,...items].map(track=>[track.id,track])).values()]:items;setTracks(merged);setSelection(current=>new Set([...(next?current:[]),...items.filter(track=>!knownIds.has(track.id)).map(track=>track.id)]));setCursor(data.nextCursor||null);const count=typeof data.total==='number'&&Number.isFinite(data.total)?data.total:!data.nextCursor?merged.length:null;if(count!==null)setCollection(current=>current?.id===value.id?{...current,trackCount:count}:current);setExposure(current=>({partial:current.partial||data.partial,warnings:mergeWarnings(current.warnings,data.warnings)}));}
  }catch(reason){if(valid(version))setError(errorText(reason));}finally{if(valid(version))setBusy(false);}
 };
 const importTracks=async()=>{
  if(!collection||saveLock.current||result)return;retry.current=importTracks;
  const version=++generation.current,body={playlistId:collection.id,destination,...(destination==='playlist'?{name:collection.name.slice(0,120)}:{}),...(mode==='public'?{publicSourceUrl:collection.sourceUrl}:{}),...(!all?{trackIds:[...selection].sort()}:{})},signature=JSON.stringify({provider,account,...body});
  if(intent.current?.signature!==signature)intent.current={signature,id:crypto.randomUUID()};saveLock.current=true;setSaving(true);setError('');
  try{const data=await post<Imported>(`/integrations/${provider}/import`,{...body,requestId:intent.current.id});if(valid(version)){setResult({...data,partial:exposure.partial||data.partial,warnings:mergeWarnings(exposure.warnings,data.warnings)});saveLock.current=false;setSaving(false);try{await store.refreshLibrary();}catch(reason){if(valid(version))store.notify(errorText(reason),true);}}}
  catch(reason){if(valid(version))setError(errorText(reason));}finally{if(valid(version)){saveLock.current=false;setSaving(false);}}
 };
 const notice=(value:Exposure)=>{const warnings=[...new Set((value.warnings||[]).map(warning=>warning==='PUBLIC_UNAVAILABLE_TRACKS'?copy('unavailableHint'):/^[A-Z][A-Z0-9_]+$/.test(warning)?copy('partialHint'):warning))].filter(warning=>warning!==copy('partialHint'));return (value.partial||!!value.warnings?.length)&&<div className="public-import-notice" role="status"><b>{copy('partial')}</b><p>{copy('partialHint')}</p>{!!warnings.length&&<ul>{warnings.map(warning=><li key={warning}>{warning}</li>)}</ul>}</div>;};
 return <Modal title={collection?.name||t('template.016',{v0:sourceNames[provider]})} onClose={close} wide>
  <div ref={root} className="import-preview public-import-preview" aria-busy={busy||saving}>
   {result?<div className="import-result" role="status"><Check size={28}/><h3>{text('imported')}</h3><strong>{trackCount(result.imported)}</strong>{!!result.deduplicated&&<small>{text('duplicates')}: {result.deduplicated}</small>}{!!result.unavailable&&<small>{text('unavailable')}: {result.unavailable}</small>}{notice(result)}{result.tasteSeeded&&<p>{text('tasteSeed')}</p>}<button className="primary-button" onClick={()=>{close();store.navigate('library');location.hash=`library?${result.playlist?`playlist=${encodeURIComponent(result.playlist.id)}`:'tab=liked'}`;}}>{t('copy.172')}<ArrowRight size={16}/></button></div>:
    !collection?<>
     <ProviderAccess key={`${account}:${provider}`} provider={provider} onConnected={()=>{setAuthorized(true);setMode('connected');}}/>
     {authorized&&<div className="import-destination public-import-modes" role="group" aria-label={copy('method')}>{(['public','connected'] as const).map(option=><button key={option} aria-pressed={mode===option} className={mode===option?'selected':''} onClick={()=>{generation.current++;setMode(option);}}>{copy(option)}</button>)}</div>}
     {mode==='public'&&<form className="public-import-search" onSubmit={event=>{event.preventDefault();if(!busy)void loadCollections();}}><label className="field"><span>{copy('query')}</span><input autoFocus name="publicImportQuery" value={query} autoComplete="off" maxLength={2048} placeholder={copy('placeholder')} onChange={event=>{generation.current++;setQuery(event.target.value);setSearched(false);setCollections([]);setBusy(false);setError('');setExposure({});setSearchExposure({});}}/></label><button className="primary-button" type="submit" disabled={busy||!query.trim()}><Search size={16}/>{copy(busy?'finding':'find')}</button><p>{copy('hint')}</p></form>}
     {notice(exposure)}
     {busy?<Loading label={copy('finding')}/>:collections.length?<div className="external-playlists">{collections.map(item=><button className="list-button" key={item.id} onClick={()=>void loadTracks(item)}>{item.kind==='likes'||item.id==='liked'?<Heart/>:item.artwork?<span className="public-collection-art" style={{backgroundImage:`url(${JSON.stringify(item.artwork)})`}}/>:<Music2/>}<span><b>{item.name}</b><small>{mode==='public'&&!item.trackCount?copy('collection'):trackCount(item.trackCount)}</small></span><ArrowRight size={16}/></button>)}</div>:!error&&searched&&<Empty title={copy('empty')}>{copy('emptyHint')}</Empty>}
    </>:
    <><button className="text-button" disabled={saving||busy} onClick={()=>{generation.current++;setCollection(null);setTracks([]);setError('');setExposure(searchExposure);}}><ArrowLeft size={15}/>{t('copy.522')}</button>
     {notice(exposure)}
     <div className="import-destination" role="group" aria-label={t('copy.172')}><button disabled={saving} aria-pressed={destination==='playlist'} className={destination==='playlist'?'selected':''} onClick={()=>setDestination('playlist')}><Music2 size={14}/>{text('importPlaylist')}</button><button disabled={saving} aria-pressed={destination==='likes'} className={destination==='likes'?'selected':''} onClick={()=>setDestination('likes')}><Heart size={14}/>{text('importLikes')}</button></div>
     <label className="check-field"><input type="checkbox" checked={all} disabled={saving} onChange={event=>setAll(event.target.checked)}/><span>{text('importAll')}</span></label>
     <div className="import-count"><span>{text('selection')}: {all?trackCount(collection.trackCount||tracks.length):trackCount(selection.size)}</span>{!all&&<button className="text-button" disabled={saving||busy} onClick={()=>setSelection(new Set(tracks.map(track=>track.id)))}>{text('selectAll')}</button>}</div>
     <div className="import-track-list">{tracks.map(track=><label key={track.id}><input type="checkbox" aria-label={`${track.title} · ${track.artist}`} disabled={all||saving} checked={all||selection.has(track.id)} onChange={event=>setSelection(current=>{const next=new Set(current);event.target.checked?next.add(track.id):next.delete(track.id);return next;})}/><Art track={track}/><span><b>{track.title}</b><small>{track.artist}</small></span></label>)}{!tracks.length&&!busy&&!error&&<p>{copy('emptyTracks')}</p>}</div>
     {busy?<Loading label={t('copy.583')}/>:cursor&&<button className="subtle-button" disabled={saving} onClick={()=>void loadTracks(collection,cursor)}>{text('loadMore')}</button>}
     <p className="local-note">{text('tasteSeed')}</p><button className="primary-button" disabled={saving||busy||!!error||!all&&!selection.size||!tracks.length} onClick={()=>void importTracks()}>{saving?text('importing'):t('copy.591')}{!saving&&<ArrowRight size={16}/>}</button>
    </>}
   {error&&<div className="import-error" role="alert"><p>{error}</p><button className="text-button" disabled={busy||saving} onClick={()=>void retry.current()}><RefreshCw size={14}/>{text('retry')}</button></div>}
  </div>
 </Modal>;
}
