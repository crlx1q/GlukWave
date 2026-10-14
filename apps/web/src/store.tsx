import { t, useLocale, setLanguageChoice } from './locale';
import {readableCoverAccent} from './cover-accent';
import {LibraryEdits,replacePlaylist,rememberTrack,setLiked,mergePlaylistCover} from './library-edits';
import {startupAccountId,preferenceStorage} from './locale-startup';
import { createContext, useCallback, useContext, useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import type { Socket } from 'socket.io-client';
import { ApiError, api, errorText, post, setRequestAccount } from './api';
import { advancedSettingsChange } from './parity-model';
import { resetDiagnostics } from './diagnostics';
import { applyAppearance, mergeSettings, mergeSettingsPatches, normalizeSettings, normalizeSettingsPatch, readLocalSettings, readPendingSettings, writeLocalSettings, writeConfirmedSettings, writePendingSettings } from './preferences';
import { clearPrivate, getCacheGeneration, readLibrary, saveLibrary } from './cache';
import { type Config, type Library, type Playlist, type Settings, type SettingsPatch, type Track, type User } from './types';
export type Route = 'home'|'search'|'library'|'sources'|'rooms'|'lofi'|'downloads'|'settings'|'profile'|'admin';
type SettingsSnapshot = {settings:Settings & {revision?:number};revision?:number};
type Toast = { id:number; text:string; error:boolean };
type Store = {
  user:User|null; config:Config|null; library:Library; settings:Settings; loading:boolean; libraryLoading:boolean; offline:boolean;
  route:Route; navigate:(route:Route)=>void; query:string; setQuery:(query:string)=>void; source:string; setSource:(source:string)=>void;
  authOpen:boolean; setAuthOpen:(open:boolean)=>void; setUser:(user:User|null)=>void; refresh:()=>Promise<void>; refreshLibrary:()=>Promise<void>;
  notify:(text:string,error?:boolean)=>void; toast:Toast|null; requireAuth:()=>boolean; logout:()=>Promise<void>;
  saveSettings:(partial:SettingsPatch)=>Promise<void>; beginSettingsEdit:()=>()=>void; bindSettingsSync:(socket:Socket)=>()=>void; settingsSync:'saved'|'saving'|'local'; resolvedTheme:'light'|'dark'|'amoled'; motion:boolean; like:(track:Track)=>Promise<void>; remember:(tracks:Track[])=>void;
  run:<T>(operation:()=>Promise<T>,success?:string)=>Promise<T|undefined>;
  renderAccent:string;setCoverAccent:(value:string|null)=>void;
  librarySaving:string[];createPlaylist:(input:{name:string;description?:string;public?:boolean;trackIds?:string[];knownTracks?:Track[]})=>Promise<Playlist>;
  updatePlaylist:(id:string,patch:Partial<Pick<Playlist,'name'|'description'|'public'|'trackIds'>>)=>Promise<Playlist>;
  setPlaylistTrack:(id:string,track:Track,present:boolean)=>Promise<Playlist>;deletePlaylist:(id:string)=>Promise<void>;acceptPlaylist:(playlist:Playlist)=>void;
};
const Context = createContext<Store|null>(null);
const emptyLibrary: Library = {tracks:[],likedIds:[],playlists:[],history:[]};
const routes: Route[] = ['home','search','library','sources','rooms','lofi','downloads','settings','profile','admin'];
function initialRoute():Route { const route=location.hash.slice(1).split('?')[0]; return routes.includes(route as Route)?route as Route:'home'; }
export function StoreProvider({children}:{children:ReactNode}) {useLocale();
  const startupAccount=useRef(startupAccountId(preferenceStorage()));
  const [coverAccent,setCoverAccent]=useState<string|null>(null);
  const [user,setUserState]=useState<User|null>(null), [config,setConfig]=useState<Config|null>(null), [library,setLibrary]=useState<Library>(emptyLibrary), [settings,setSettings]=useState<Settings>(()=>readLocalSettings(startupAccount.current));
  const [libraryOwner,setLibraryOwner]=useState<string|null>(null),[libraryPending,setLibraryPending]=useState(false),libraryFlight=useRef(0);
  const [librarySaving,setLibrarySaving]=useState<string[]>([]);
  const edits=useRef<LibraryEdits|null>(null);
  if(!edits.current)edits.current=new LibraryEdits(emptyLibrary,(value,saving)=>{setLibrary(value);setLibrarySaving(saving);});
  const [loading,setLoading]=useState(true),[offline,setOffline]=useState(!navigator.onLine),[route,setRoute]=useState<Route>(initialRoute),[query,setQuery]=useState(''),[source,setSource]=useState('all'),[authOpen,setAuthOpen]=useState(false),[toast,setToast]=useState<Toast|null>(null);
  const [settingsSync,setSettingsSync]=useState<'saved'|'saving'|'local'>('local'),[systemDark,setSystemDark]=useState(()=>matchMedia('(prefers-color-scheme: dark)').matches),[systemMotion,setSystemMotion]=useState(()=>matchMedia('(prefers-reduced-motion: reduce)').matches),[systemContrast,setSystemContrast]=useState(()=>matchMedia('(prefers-contrast: more)').matches);
  const settingsRef=useRef(settings),settingsFrame=useRef<number|null>(null),presentHeldPalette=useRef(()=>{});
  const settingsHolds=useRef(0);
  const settingsServer=useRef(settings),pendingSettings=useRef<SettingsPatch>({}),serverRevision=useRef(-1),accountGeneration=useRef(0),settingsTimer=useRef<ReturnType<typeof setTimeout>|undefined>(undefined),settingsFlight=useRef<{userId:string;generation:number;controller:AbortController;partial:SettingsPatch}|null>(null),flushSettingsRef=useRef<(id:string)=>Promise<void>>(async()=>{});
  const userRef=useRef(user);userRef.current=user;const toastTimer=useRef<ReturnType<typeof setTimeout>|undefined>(undefined);
  const notify=useCallback((text:string,error=false)=>{clearTimeout(toastTimer.current);setToast({id:Date.now(),text,error});toastTimer.current=setTimeout(()=>setToast(null),6500);},[]);
  useEffect(()=>()=>clearTimeout(toastTimer.current),[]);
  const setUser=useCallback((next:User|null)=>{if(userRef.current?.id!==next?.id){resetDiagnostics();edits.current!.reset(next?.id||null,emptyLibrary);}userRef.current=next;setRequestAccount(next?.id||null);setUserState(next);if(next)localStorage.setItem('gw-user',JSON.stringify(next));else localStorage.removeItem('gw-user');},[]);
  const navigate=useCallback((next:Route)=>{location.hash=next;setRoute(next);window.scrollTo({top:0,behavior:'instant'});},[]);
  const refreshLibrary=useCallback(async()=>{
    if(!user){setLibraryPending(false);setLibraryOwner(null);return;}
    const flight=++libraryFlight.current,revision=edits.current!.revision;setLibraryPending(true);
    try {const generation=await getCacheGeneration(user.id);const fresh=await api<Library>('/library');if(userRef.current?.id!==user.id||flight!==libraryFlight.current)return;if(edits.current!.snapshot(fresh,revision))await saveLibrary(user.id,edits.current!.confirmed,generation);setLibraryOwner(user.id);setOffline(false);}
    catch(error){if(userRef.current?.id!==user.id)return;const saved=await readLibrary(user.id);if(saved){edits.current!.snapshot(saved,revision);setOffline(true);}else throw error;}
    finally{if(userRef.current?.id===user.id&&flight===libraryFlight.current){setLibraryPending(false);setLibraryOwner(user.id);}}
  },[user]);
  const refresh=useCallback(async()=>{
    const result=await api<{user:User|null}>('/auth/me');setUser(result.user);
  },[setUser]);
  useEffect(()=>{
    let cancelled=false;
    Promise.allSettled([api<Config>('/config'),api<{user:User|null}>('/auth/me')]).then(async results=>{
      if(cancelled)return;
      if(results[0].status==='fulfilled')setConfig(results[0].value);
      if(results[1].status==='fulfilled'){setUser(results[1].value.user);setOffline(false);}
      else {setOffline(true);try {const previous=JSON.parse(localStorage.getItem('gw-user')||'null') as User|null;if(previous){userRef.current=previous;setUserState(previous);edits.current!.reset(previous.id,await readLibrary(previous.id)||emptyLibrary);}}catch{/* Invalid local metadata is discarded. */}}
      setLoading(false);
    });
    const handleHash=()=>setRoute(initialRoute()); const online=()=>{setOffline(!navigator.onLine);if(navigator.onLine)void refresh().catch(()=>setOffline(true));};
    window.addEventListener('hashchange',handleHash);window.addEventListener('online',online);window.addEventListener('offline',online);
    return()=>{cancelled=true;window.removeEventListener('hashchange',handleHash);window.removeEventListener('online',online);window.removeEventListener('offline',online);};
  },[refresh,setUser]);
  useEffect(()=>{if(user)void refreshLibrary().catch(error=>notify(errorText(error),true));else setLibrary(emptyLibrary);},[user,refreshLibrary,notify]);
  const scheduleSettings=useCallback((id:string,delay=550)=>{clearTimeout(settingsTimer.current);if(settingsHolds.current)return;settingsTimer.current=setTimeout(()=>void flushSettingsRef.current(id),delay);},[]);
  // Keep the accepted server snapshot separate from edits that have not been acknowledged.
  // A later socket event can then update other fields without undoing the user's current drag.
  const publishSettings=useCallback((id:string|null)=>{
    const flight=settingsFlight.current;
    const edits=mergeSettingsPatches(flight?.userId===id?flight.partial:{},pendingSettings.current);
    const next=mergeSettings(settingsServer.current,edits);settingsRef.current=next;
    const present=()=>{setLanguageChoice(settingsRef.current.language);setSettings(settingsRef.current);setSettingsSync(id?(Object.keys(edits).length?(navigator.onLine?'saving':'local'):'saved'):'local');};
    if(settingsHolds.current){if(settingsFrame.current===null){const generation=accountGeneration.current;settingsFrame.current=requestAnimationFrame(()=>{settingsFrame.current=null;if(generation!==accountGeneration.current)return;const paletteOnly=Object.keys(edits).every(key=>key==='appearance')&&Object.keys(edits.appearance||{}).every(key=>['light','dark','amoled','coverAccent'].includes(key));if(paletteOnly)presentHeldPalette.current();else present();});}return;}
    if(settingsFrame.current!==null){cancelAnimationFrame(settingsFrame.current);settingsFrame.current=null;}
    present();writeLocalSettings(id,next);if(id)writePendingSettings(id,edits);
  },[]);
  const acceptSettings=useCallback((id:string,generation:number,payload:SettingsSnapshot)=>{
    if(userRef.current?.id!==id||accountGeneration.current!==generation)return;
    const revision=payload.revision??payload.settings.revision??0;
    if(!Number.isSafeInteger(revision)||revision<serverRevision.current)return;
    serverRevision.current=revision;settingsServer.current=normalizeSettings(payload.settings);writeConfirmedSettings(id,settingsServer.current,revision);publishSettings(id);
  },[publishSettings]);
  const pullSettings=useCallback(async(id:string,generation:number,signal?:AbortSignal)=>{
    const payload=await api<SettingsSnapshot>('/settings',{signal});
    if(signal?.aborted||userRef.current?.id!==id||accountGeneration.current!==generation)return;
    acceptSettings(id,generation,payload);
    if(Object.keys(pendingSettings.current).length)scheduleSettings(id);
  },[acceptSettings,scheduleSettings]);
  const bindSettingsSync=useCallback((socket:Socket)=>{
    const id=userRef.current?.id,generation=accountGeneration.current,controller=new AbortController();if(!id)return()=>{};
    const changed=(payload:SettingsSnapshot)=>acceptSettings(id,generation,payload);
    const connected=()=>void pullSettings(id,generation,controller.signal).catch(()=>{});
    socket.on('settings:changed',changed);socket.on('connect',connected);if(socket.connected)connected();
    return()=>{controller.abort();socket.off('settings:changed',changed);socket.off('connect',connected);};
  },[acceptSettings,pullSettings]);
  flushSettingsRef.current=async(id:string)=>{
    if(settingsHolds.current||userRef.current?.id!==id||!Object.keys(pendingSettings.current).length)return;
    if(!navigator.onLine){setSettingsSync('local');return;}
    if(settingsFlight.current?.userId===id)return;
    const sent=pendingSettings.current;pendingSettings.current={};const flight={userId:id,generation:accountGeneration.current,partial:sent,controller:new AbortController()};settingsFlight.current=flight;writePendingSettings(id,sent);setSettingsSync('saving');let success=false;
    try {
      const result=await api<SettingsSnapshot>('/settings',{method:'PATCH',headers:{'X-GlukWave-Account':id},body:JSON.stringify(sent),signal:flight.controller.signal});success=true;
      if(flight.controller.signal.aborted||userRef.current?.id!==id||accountGeneration.current!==flight.generation)return;
      settingsFlight.current=null;acceptSettings(id,flight.generation,result);publishSettings(id);
    }catch(error) {
      if(flight.controller.signal.aborted||userRef.current?.id!==id||accountGeneration.current!==flight.generation)return;
      settingsFlight.current=null;if(error instanceof ApiError&&['PLAN_LIMIT','INVALID_SETTINGS','VALIDATION'].includes(error.code)){publishSettings(id);notify(errorText(error),true);return;}pendingSettings.current=mergeSettingsPatches(sent,pendingSettings.current);publishSettings(id);setSettingsSync('local');
    }finally {
      if(userRef.current?.id===id&&accountGeneration.current===flight.generation){if(settingsFlight.current===flight)settingsFlight.current=null;if(Object.keys(pendingSettings.current).length&&navigator.onLine)scheduleSettings(id,success?120:15000);}
    }
  };
  const userId=user?.id||null;
  const preferenceScope=userId||(loading?startupAccount.current:null);
  useLayoutEffect(()=>{
    clearTimeout(settingsTimer.current);if(settingsFrame.current!==null){cancelAnimationFrame(settingsFrame.current);settingsFrame.current=null;}settingsFlight.current?.controller.abort();settingsFlight.current=null;accountGeneration.current++;settingsHolds.current=0;serverRevision.current=-1;
    pendingSettings.current=preferenceScope?readPendingSettings(preferenceScope):{};settingsServer.current=readLocalSettings(preferenceScope);publishSettings(preferenceScope);
    return()=>{clearTimeout(settingsTimer.current);if(settingsFrame.current!==null){cancelAnimationFrame(settingsFrame.current);settingsFrame.current=null;}settingsFlight.current?.controller.abort();};
  },[preferenceScope,publishSettings]);
  useEffect(()=>{
    if(!userId)return;const generation=accountGeneration.current,controller=new AbortController();setSettingsSync('saving');
    void pullSettings(userId,generation,controller.signal).catch(()=>{if(!controller.signal.aborted&&userRef.current?.id===userId&&accountGeneration.current===generation){setSettingsSync('local');if(Object.keys(pendingSettings.current).length&&navigator.onLine)scheduleSettings(userId,15000);}});
    return()=>controller.abort();
  },[userId,pullSettings,scheduleSettings]);
  useEffect(()=>{
    const appearance=matchMedia('(prefers-color-scheme: dark)'),motion=matchMedia('(prefers-reduced-motion: reduce)'),contrast=matchMedia('(prefers-contrast: more)');const update=()=>{setSystemDark(appearance.matches);setSystemMotion(motion.matches);setSystemContrast(contrast.matches);};appearance.addEventListener('change',update);motion.addEventListener('change',update);contrast.addEventListener('change',update);
    const sync=()=>{const id=userRef.current?.id;if(id&&navigator.onLine&&Object.keys(pendingSettings.current).length)scheduleSettings(id,100);};
    // Optimistic drafts in another tab are not a server snapshot. Reading them
    // back through the API causes a ping-pong that resets the save debounce.
    const storage=(event:StorageEvent)=>{const id=userRef.current?.id||null;if(id){if(event.key!==`gw-settings-confirmed:${id}`||!event.newValue)return;try{const confirmed=JSON.parse(event.newValue) as SettingsSnapshot;if(confirmed.settings&&Number.isSafeInteger(confirmed.revision))acceptSettings(id,accountGeneration.current,confirmed);}catch{/* Ignore invalid local metadata. */}}else if(event.key==='gw-settings:guest'){const next=readLocalSettings(null);settingsServer.current=next;settingsRef.current=next;setSettings(next);}};
    window.addEventListener('online',sync);window.addEventListener('storage',storage);
    return()=>{appearance.removeEventListener('change',update);motion.removeEventListener('change',update);contrast.removeEventListener('change',update);window.removeEventListener('online',sync);window.removeEventListener('storage',storage);clearTimeout(settingsTimer.current);settingsFlight.current?.controller.abort();};
  },[scheduleSettings,pullSettings,acceptSettings]);
  const resolvedTheme=settings.theme==='system'?(systemDark?'dark':'light'):settings.theme,motion=!settings.reducedMotion&&!systemMotion;
  const renderAccent=readableCoverAccent(settings.appearance.coverAccent?coverAccent:null,settings.appearance[resolvedTheme].bg,settings.appearance[resolvedTheme].accent,systemContrast);
  presentHeldPalette.current=()=>{const live=settingsRef.current;applyAppearance(live.appearance,resolvedTheme,motion,readableCoverAccent(live.appearance.coverAccent?coverAccent:null,live.appearance[resolvedTheme].bg,live.appearance[resolvedTheme].accent,systemContrast));window.dispatchEvent(new Event('wave:palette-preview'));};
  useLayoutEffect(()=>applyAppearance(settings.appearance,resolvedTheme,motion,renderAccent),[settings.appearance,resolvedTheme,motion,renderAccent]);
  const requireAuth=useCallback(()=>{if(!user){setAuthOpen(true);return false;}if(offline){notify(t('copy.729'),true);return false;}return true;},[user,offline,notify]);
  const run=useCallback(async<T,>(operation:()=>Promise<T>,success?:string)=>{try{const result=await operation();if(success)notify(success);return result;}catch(error){if((error as Error)?.name!=='AbortError')notify(errorText(error),true);return undefined;}},[notify]);
  const beginSettingsEdit=useCallback(()=>{
    const generation=accountGeneration.current;settingsHolds.current++;clearTimeout(settingsTimer.current);let released=false;
    return()=>{if(released||generation!==accountGeneration.current)return;released=true;settingsHolds.current=Math.max(0,settingsHolds.current-1);const id=userRef.current?.id||null;if(!settingsHolds.current){publishSettings(id);if(id&&Object.keys(pendingSettings.current).length)scheduleSettings(id,0);}};
  },[scheduleSettings,publishSettings]);
  const saveSettings=useCallback(async(partial:SettingsPatch)=>{
    const change=normalizeSettingsPatch(partial);if(!Object.keys(change).length)return;if(userRef.current?.plan==='free'&&advancedSettingsChange(change,settingsRef.current)){notify(t('parity.planLimit'),true);return;}const id=userRef.current?.id||null;
    if(!id){settingsServer.current=mergeSettings(settingsServer.current,change);publishSettings(null);return;}
    pendingSettings.current=mergeSettingsPatches(pendingSettings.current,change);publishSettings(id);if(navigator.onLine)scheduleSettings(id);
  },[scheduleSettings,publishSettings,notify]);
  useLayoutEffect(()=>{document.documentElement.style.setProperty('--font-scale',String(settings.fontScale));document.documentElement.dataset.textScale=settings.fontScale>1?'large':'normal';document.documentElement.style.setProperty('--app-font',settings.fontFamily==='system'?'system-ui, sans-serif':settings.fontFamily==='nunito'?"'Nunito', sans-serif":"'Manrope', 'Nunito', sans-serif");},[settings.fontScale,settings.fontFamily]);
  const persistLibrary=useCallback(()=>{const id=userRef.current?.id,revision=edits.current!.revision;if(!id||edits.current!.pending)return;void getCacheGeneration(id).then(generation=>{if(userRef.current?.id===id&&edits.current!.revision===revision&&!edits.current!.pending)return saveLibrary(id,edits.current!.confirmed,generation);}).catch(()=>{});},[]);
  useEffect(()=>{if(libraryOwner===user?.id&&!librarySaving.length)persistLibrary();},[library,libraryOwner,user?.id,librarySaving.length,persistLibrary]);
  const like=useCallback(async(track:Track)=>{if(!requireAuth())return;const liked=!edits.current!.value.likedIds.includes(track.id);await edits.current!.mutate('like:'+track.id,current=>setLiked(rememberTrack(current,track),track.id,liked),()=>api(`/library/likes/${encodeURIComponent(track.id)}`,{method:'PUT',body:JSON.stringify({liked})}),current=>setLiked(rememberTrack(current,track),track.id,liked));persistLibrary();},[requireAuth,persistLibrary]);
  const acceptPlaylist=useCallback((playlist:Playlist)=>{edits.current!.accept(current=>mergePlaylistCover(current,playlist));persistLibrary();},[persistLibrary]);
  const createPlaylist=useCallback(async(input:{name:string;description?:string;public?:boolean;trackIds?:string[];knownTracks?:Track[]})=>{
    if(!requireAuth())throw new ApiError('AUTH_REQUIRED',t('copy.515'));
    const {knownTracks=[],...body}=input;const seed=(current:Library)=>knownTracks.filter(track=>body.trackIds?.includes(track.id)).reduce(rememberTrack,current);
    const id='pending:'+crypto.randomUUID(),now=new Date().toISOString(),draft:Playlist={id,name:input.name.trim(),description:input.description||'',public:input.public||false,trackIds:[...new Set(input.trackIds||[])],ownerId:userRef.current!.id,artwork:'',createdAt:now,updatedAt:now};
    const result=await edits.current!.mutate('create:'+id,current=>replacePlaylist(seed(current),draft),()=>post<{playlist:Playlist}>('/playlists',body),(current,value)=>replacePlaylist({...seed(current),playlists:current.playlists.filter(playlist=>playlist.id!==id)},value.playlist));persistLibrary();return result.playlist;
  },[requireAuth,persistLibrary]);
  const updatePlaylist=useCallback(async(id:string,partial:Partial<Pick<Playlist,'name'|'description'|'public'|'trackIds'>>)=>{
    if(!requireAuth())throw new ApiError('AUTH_REQUIRED',t('copy.515'));
    if(id.startsWith('pending:'))throw new ApiError('PLAYLIST_PENDING',t('copy.085'));
    const result=await edits.current!.mutate('playlist:'+id,current=>({...current,playlists:current.playlists.map(playlist=>playlist.id===id?{...playlist,...partial}:playlist)}),()=>api<{playlist:Playlist}>(`/playlists/${encodeURIComponent(id)}`,{method:'PATCH',body:JSON.stringify(partial)}),(current,value)=>replacePlaylist(current,value.playlist));persistLibrary();return result.playlist;
  },[requireAuth,persistLibrary]);
  const setPlaylistTrack=useCallback(async(id:string,track:Track,present:boolean)=>{
    if(!requireAuth())throw new ApiError('AUTH_REQUIRED',t('copy.515'));
    if(id.startsWith('pending:'))throw new ApiError('PLAYLIST_PENDING',t('copy.085'));
    const result=await edits.current!.mutate('playlist:'+id,current=>({...rememberTrack(current,track),playlists:current.playlists.map(playlist=>playlist.id===id?{...playlist,trackIds:present?[...new Set([...playlist.trackIds,track.id])]:playlist.trackIds.filter(value=>value!==track.id)}:playlist)}),()=>api<{playlist:Playlist}>(`/playlists/${encodeURIComponent(id)}/tracks/${encodeURIComponent(track.id)}`,{method:'PUT',body:JSON.stringify({present})}),(current,value)=>replacePlaylist(rememberTrack(current,track),value.playlist));persistLibrary();return result.playlist;
  },[requireAuth,persistLibrary]);
  const deletePlaylist=useCallback(async(id:string)=>{if(!requireAuth())throw new ApiError('AUTH_REQUIRED',t('copy.515'));if(id.startsWith('pending:'))return;const remove=(current:Library)=>({...current,playlists:current.playlists.filter(playlist=>playlist.id!==id)});await edits.current!.mutate('playlist:'+id,remove,()=>api(`/playlists/${encodeURIComponent(id)}`,{method:'DELETE'}),remove);persistLibrary();},[requireAuth,persistLibrary]);
  const remember=useCallback((tracks:Track[])=>{const known=new Map(tracks.map(track=>[track.id,track]));edits.current!.accept(current=>({...current,tracks:current.tracks.map(track=>known.get(track.id)||track)}));},[]);
  const logout=useCallback(async()=>{if(user){await post('/auth/logout');await clearPrivate(user.id);}setUser(null);setLibrary(emptyLibrary);navigate('home');notify(t('copy.730'));},[user,setUser,navigate,notify]);
  return <Context.Provider value={{user,config,library,librarySaving,createPlaylist,updatePlaylist,setPlaylistTrack,deletePlaylist,acceptPlaylist,settings,renderAccent,setCoverAccent,settingsSync,resolvedTheme,motion,loading,libraryLoading:!!user&&(libraryPending||libraryOwner!==user.id),offline,route,navigate,query,setQuery,source,setSource,authOpen,setAuthOpen,setUser,refresh,refreshLibrary,notify,toast,requireAuth,logout,saveSettings,beginSettingsEdit,bindSettingsSync,like,remember,run}}>{children}</Context.Provider>;
}
export function useStore(){const context=useContext(Context);if(!context)throw new Error('Missing store');return context;}

