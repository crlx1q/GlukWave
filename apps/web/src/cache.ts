import { t } from './locale';
import { openDB, type DBSchema } from 'idb';
import type { Library, Track } from './types';
export type CachedTrack = { key:string; userId:string; track:Track; blob:Blob; bytes:number; savedAt:number; manual:boolean };
interface WaveDB extends DBSchema {
  downloads:{key:string;value:CachedTrack;indexes:{userId:string}};
  library:{key:string;value:Library};
  generation:{key:string;value:number};
}
const database=openDB<WaveDB>('glukwave-private-v1',2,{upgrade(db){
  if(!db.objectStoreNames.contains('downloads'))db.createObjectStore('downloads',{keyPath:'key'}).createIndex('userId','userId');
  if(!db.objectStoreNames.contains('library'))db.createObjectStore('library');
  if(!db.objectStoreNames.contains('generation'))db.createObjectStore('generation');
}});
type DownloadOperation={controller:AbortController;promise:Promise<void>;manual:boolean;progress:((fraction:number)=>void)[]};
const inFlight=new Map<string,DownloadOperation>();
const changes=new BroadcastChannel('glukwave-cache-events');
function announce(userId:string,trackId?:string){window.dispatchEvent(new Event('wave:cache'));changes.postMessage({userId,trackId});}
function cancel(userId:string,trackId?:string){for(const[key,operation]of inFlight)if(key.startsWith(`${userId}:`)&&(!trackId||key===`${userId}:${trackId}`))operation.controller.abort();}
changes.onmessage=event=>{cancel(event.data.userId,event.data.trackId);window.dispatchEvent(new Event('wave:cache'));};
export async function getCacheGeneration(userId:string){return(await(await database).get('generation',userId))||0;}
export async function cached(userId:string,trackId:string){return(await database).get('downloads',`${userId}:${trackId}`);}
export async function downloads(userId:string){return(await database).getAllFromIndex('downloads','userId',userId);}
export async function deleteDownload(userId:string,trackId:string){
  cancel(userId,trackId);const db=await database,key=`${userId}:${trackId}`,tx=db.transaction(['downloads','generation'],'readwrite');
  await tx.objectStore('generation').put(((await tx.objectStore('generation').get(key))||0)+1,key);
  await tx.objectStore('downloads').delete(key);await tx.done;announce(userId,trackId);
}
async function clear(userId:string,privateMetadata:boolean){
  cancel(userId);const db=await database,tx=db.transaction(['downloads','library','generation'],'readwrite');
  const generation=tx.objectStore('generation');await generation.put(((await generation.get(userId))||0)+1,userId);
  const rows=await tx.objectStore('downloads').index('userId').getAllKeys(userId);
  for(const key of rows)await tx.objectStore('downloads').delete(key);
  if(privateMetadata)await tx.objectStore('library').delete(userId);
  await tx.done;announce(userId);
}
export const clearPrivate=(userId:string)=>clear(userId,true);
export const clearDownloads=(userId:string)=>clear(userId,false);
export async function saveLibrary(userId:string,library:Library,expectedGeneration?:number){
  const db=await database,tx=db.transaction(['library','generation'],'readwrite');
  const current=(await tx.objectStore('generation').get(userId))||0;
  if(expectedGeneration===undefined||current===expectedGeneration)await tx.objectStore('library').put(library,userId);
  await tx.done;
}
export async function readLibrary(userId:string){return(await database).get('library',userId);}
export async function saveTrack(userId:string,track:Track,limitMB:number,manual:boolean,progress?:(fraction:number)=>void){
  if(!track.playback.offline||track.playback.kind!=='audio')throw new Error(t('copy.275'));
  const key=`${userId}:${track.id}`,active=inFlight.get(key);
  if(active){active.manual||=manual;if(progress)active.progress.push(progress);return active.promise;}
  const operation:DownloadOperation={controller:new AbortController(),promise:Promise.resolve(),manual,progress:progress?[progress]:[]};
  operation.promise=(async()=>{
    const db=await database,generation=await getCacheGeneration(userId),trackGeneration=(await db.get('generation',key))||0;
    const response=await fetch(`/api/media/${encodeURIComponent(track.id)}/download`,{credentials:'include',signal:operation.controller.signal});
    if(!response.ok){const body=await response.json().catch(()=>({}));throw new Error(body.error?.message||t('copy.276'));}
    const size=Number(response.headers.get('Content-Length')),limit=limitMB*1024*1024;
    if(size>limit){await response.body?.cancel();throw new Error(t('copy.277'));}
    const parts:Uint8Array<ArrayBuffer>[]=[];let received=0;
    if(response.body){const reader=response.body.getReader();while(true){const chunk=await reader.read();if(chunk.done)break;received+=chunk.value.byteLength;if(received>limit){await reader.cancel();throw new Error(t('copy.278'));}parts.push(new Uint8Array(chunk.value));for(const listener of operation.progress)listener(size?received/size:0);}}
    else parts.push(new Uint8Array(await response.arrayBuffer()));
    const blob=new Blob(parts,{type:response.headers.get('Content-Type')||'audio/mpeg'});
    if(operation.controller.signal.aborted)throw new DOMException(t('copy.279'),'AbortError');
    // Quota decisions and writes share a transaction, including across different browser tabs.
    const tx=db.transaction(['downloads','generation'],'readwrite'),generations=tx.objectStore('generation');
    const actualGeneration=(await generations.get(userId))||0,actualTrackGeneration=(await generations.get(key))||0;
    if(actualGeneration!==generation||actualTrackGeneration!==trackGeneration||operation.controller.signal.aborted){await tx.done;throw new DOMException(t('copy.279'),'AbortError');}
    const records=tx.objectStore('downloads'),existing=await records.get(key),rows=(await records.index('userId').getAll(userId)).filter(row=>row.key!==key).sort((a,b)=>a.savedAt-b.savedAt);
    let total=rows.reduce((sum,row)=>sum+row.bytes,0);
    for(const row of rows.filter(row=>!row.manual))if(total+blob.size>limit){await records.delete(row.key);total-=row.bytes;}
    if(total+blob.size>limit){tx.abort();await tx.done.catch(()=>{});throw new Error(t('copy.280'));}
    try{await records.put({key,userId,track,blob,bytes:blob.size,savedAt:Date.now(),manual:operation.manual||!!existing?.manual});await tx.done;}
    catch(error){if(error instanceof DOMException&&error.name==='QuotaExceededError')throw new Error(t('copy.281'));throw error;}
    for(const listener of operation.progress)listener(1);window.dispatchEvent(new Event('wave:cache'));
  })().finally(()=>{if(inFlight.get(key)===operation)inFlight.delete(key);});
  inFlight.set(key,operation);return operation.promise;
}

export async function pinDownload(userId:string,trackId:string){const db=await database,key=`${userId}:${trackId}`,tx=db.transaction('downloads','readwrite'),row=await tx.store.get(key);if(row)await tx.store.put({...row,manual:true});await tx.done;window.dispatchEvent(new Event('wave:cache'));}
