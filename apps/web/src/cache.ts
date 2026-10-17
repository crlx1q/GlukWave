import { t } from './locale';
import { openDB, type DBSchema, type IDBPDatabase } from 'idb';
import type { Library, Track } from './types';
import { mediaDownloadPath, mediaArtworkPath } from './media-download';
import {isAudioFile} from './audio-cache-validation';
export type CachedTrack = { key:string; userId:string; track:Track; blob:Blob; artworkBlob?:Blob; bytes:number; savedAt:number; manual:boolean };
export type MetadataEntry = {key:string;userId:string;at:number;value:unknown};
interface WaveDB extends DBSchema {
  downloads:{key:string;value:CachedTrack;indexes:{userId:string}};
  library:{key:string;value:Library};
  generation:{key:string;value:number};
  metadata:{key:string;value:MetadataEntry;indexes:{userId:string}};
}
let database: Promise<IDBPDatabase<WaveDB>|null>|undefined;
function getDatabase(){
 // The idb adapter needs Proxy. Lack of offline storage must not prevent
 // online playback on older TVs or browsers with disabled/private storage.
 return database ??= typeof indexedDB==='undefined'||typeof Proxy==='undefined'
 ? Promise.resolve(null) : openDB<WaveDB>('glukwave-private-v1',3,{upgrade(db){
  if(!db.objectStoreNames.contains('downloads'))db.createObjectStore('downloads',{keyPath:'key'}).createIndex('userId','userId');
  if(!db.objectStoreNames.contains('library'))db.createObjectStore('library');
  if(!db.objectStoreNames.contains('generation'))db.createObjectStore('generation');
  if(!db.objectStoreNames.contains('metadata'))db.createObjectStore('metadata',{keyPath:'key'}).createIndex('userId','userId');
}}).catch(()=>null);
}
type DownloadOperation={controller:AbortController;promise:Promise<void>;manual:boolean;speculative:boolean;progress:((fraction:number)=>void)[]};
const inFlight=new Map<string,DownloadOperation>();
async function cachedArtwork(track:Track,signal:AbortSignal,budget:number):Promise<Blob|undefined>{
 if(!track.artwork||budget<=0)return;
 try{
  const limit=Math.min(1024*1024,budget),response=await fetch(mediaArtworkPath(track.id,track.artwork,location.origin),{credentials:'include',signal:AbortSignal.any([signal,AbortSignal.timeout(3500)])});
  const type=response.headers.get('Content-Type')?.split(';')[0]||'';
  if(!response.ok||!/^image\/(png|jpe?g|webp|avif|gif)$/.test(type)||Number(response.headers.get('Content-Length'))>limit){await response.body?.cancel();return;}
  const reader=response.body?.getReader();if(!reader)return;const parts:Uint8Array<ArrayBuffer>[]=[];let received=0;
  while(true){const item=await reader.read();if(item.done)break;received+=item.value.byteLength;if(received>limit){await reader.cancel();return;}parts.push(new Uint8Array(item.value));}
  return new Blob(parts,{type});
 }catch{/* A missing thumbnail must not discard a valid offline track. */}
}
const changes=typeof BroadcastChannel==='function'?new BroadcastChannel('glukwave-cache-events'):null;
function announce(userId:string,trackId?:string){window.dispatchEvent(new Event('wave:cache'));changes?.postMessage({userId,trackId});}
function cancel(userId:string,trackId?:string){for(const[key,operation]of inFlight)if(key.startsWith(`${userId}:`)&&(!trackId||key===`${userId}:${trackId}`))operation.controller.abort();}
if(changes)changes.onmessage=event=>{cancel(event.data.userId,event.data.trackId);window.dispatchEvent(new Event('wave:cache'));};
export async function getCacheGeneration(userId:string){return(await(await getDatabase())?.get('generation',userId))||0;}
export async function cached(userId:string,trackId:string){
 const row=await(await getDatabase())?.get('downloads',`${userId}:${trackId}`);
 if(row&&!await isAudioFile(row.blob)){await deleteDownload(userId,trackId);return undefined;}
 return row;
}
export async function downloads(userId:string){return(await getDatabase())?.getAllFromIndex('downloads','userId',userId)??[];}
export async function deleteDownload(userId:string,trackId:string){
  cancel(userId,trackId);const db=await getDatabase();if(!db)return;const key=`${userId}:${trackId}`,tx=db.transaction(['downloads','generation'],'readwrite');
  await tx.objectStore('generation').put(((await tx.objectStore('generation').get(key))||0)+1,key);
  await tx.objectStore('downloads').delete(key);await tx.done;announce(userId,trackId);
}
async function clear(userId:string,privateMetadata:boolean){
  cancel(userId);const db=await getDatabase();if(!db)return;const tx=db.transaction(['downloads','library','generation','metadata'],'readwrite');
  const generation=tx.objectStore('generation');await generation.put(((await generation.get(userId))||0)+1,userId);
  const rows=await tx.objectStore('downloads').index('userId').getAllKeys(userId);
  for(const key of rows)await tx.objectStore('downloads').delete(key);
  if(privateMetadata){await tx.objectStore('library').delete(userId);for(const key of await tx.objectStore('metadata').index('userId').getAllKeys(userId))await tx.objectStore('metadata').delete(key);}
  await tx.done;announce(userId);
}
export const clearPrivate=(userId:string)=>clear(userId,true);
export const clearDownloads=(userId:string)=>clear(userId,false);
export async function saveLibrary(userId:string,library:Library,expectedGeneration?:number){
  const db=await getDatabase();if(!db)return;const tx=db.transaction(['library','generation'],'readwrite');
  const current=(await tx.objectStore('generation').get(userId))||0;
  if(expectedGeneration===undefined||current===expectedGeneration)await tx.objectStore('library').put(library,userId);
  await tx.done;
}
export async function readLibrary(userId:string){return(await getDatabase())?.get('library',userId);}
export async function readMetadata(userId:string,path:string){return(await getDatabase())?.get('metadata',`${userId}:${path}`);}
export async function removeMetadata(userId:string,path:string){await(await getDatabase())?.delete('metadata',`${userId}:${path}`);}
export async function saveMetadata(userId:string,path:string,value:unknown,generation:number){
 const encoded=JSON.stringify(value);if(encoded.length>256*1024)return;
 const db=await getDatabase();if(!db)return;const tx=db.transaction(['metadata','generation'],'readwrite');
 if(((await tx.objectStore('generation').get(userId))||0)!==generation){await tx.done;return;}
 const table=tx.objectStore('metadata');await table.put({key:`${userId}:${path}`,userId,at:Date.now(),value});
 const rows=(await table.index('userId').getAll(userId)).sort((a,b)=>a.at-b.at);let bytes=rows.reduce((sum,row)=>sum+JSON.stringify(row.value).length,0);
 while(rows.length>48||bytes>2*1024*1024){const row=rows.shift()!;bytes-=JSON.stringify(row.value).length;await table.delete(row.key);}
 await tx.done;
}
export async function saveTrack(userId:string,track:Track,limitMB:number,manual:boolean,progress?:(fraction:number)=>void,externalSignal?:AbortSignal){
  if(!track.playback.offline||track.playback.kind!=='audio')throw new Error(t('copy.275'));
  const downloadUrl=mediaDownloadPath(track.id,track.playback.downloadUrl,location.origin);if(!downloadUrl)throw new Error(t('copy.275'));
  const key=`${userId}:${track.id}`,active=inFlight.get(key);
  if(active){active.manual||=manual;if(!externalSignal)active.speculative=false;if(progress)active.progress.push(progress);return active.promise;}
  const operation:DownloadOperation={controller:new AbortController(),promise:Promise.resolve(),manual,speculative:!!externalSignal,progress:progress?[progress]:[]};
  const cancelSpeculative=()=>{if(!operation.manual&&operation.speculative)operation.controller.abort();};externalSignal?.addEventListener('abort',cancelSpeculative,{once:true});if(externalSignal?.aborted)cancelSpeculative();
  operation.promise=(async()=>{
    const db=await getDatabase();if(!db)throw new Error(t('copy.275'));const generation=await getCacheGeneration(userId),trackGeneration=(await db.get('generation',key))||0;
    const response=await fetch(downloadUrl,{credentials:'include',signal:operation.controller.signal});
    if(!response.ok){const body=await response.json().catch(()=>({}));throw new Error(body.error?.message||t('copy.276'));}
    const size=Number(response.headers.get('Content-Length')),limit=limitMB*1024*1024;
    if(size>limit){await response.body?.cancel();throw new Error(t('copy.277'));}
    const parts:Uint8Array<ArrayBuffer>[]=[];let received=0;
    if(response.body){const reader=response.body.getReader();while(true){const chunk=await reader.read();if(chunk.done)break;received+=chunk.value.byteLength;if(received>limit){await reader.cancel();throw new Error(t('copy.278'));}parts.push(new Uint8Array(chunk.value));for(const listener of operation.progress)listener(size?received/size:0);}}
    else parts.push(new Uint8Array(await response.arrayBuffer()));
    const blob=new Blob(parts,{type:response.headers.get('Content-Type')||'audio/mpeg'});
    if(!await isAudioFile(blob))throw new Error(t('copy.715'));
    const artworkBlob=await cachedArtwork(track,operation.controller.signal,limit-blob.size),bytes=blob.size+(artworkBlob?.size||0);
    if(operation.controller.signal.aborted)throw new DOMException(t('copy.279'),'AbortError');
    // Quota decisions and writes share a transaction, including across different browser tabs.
    const tx=db.transaction(['downloads','generation'],'readwrite'),generations=tx.objectStore('generation');
    const actualGeneration=(await generations.get(userId))||0,actualTrackGeneration=(await generations.get(key))||0;
    if(actualGeneration!==generation||actualTrackGeneration!==trackGeneration||operation.controller.signal.aborted){await tx.done;throw new DOMException(t('copy.279'),'AbortError');}
    const records=tx.objectStore('downloads'),existing=await records.get(key),rows=(await records.index('userId').getAll(userId)).filter(row=>row.key!==key).sort((a,b)=>a.savedAt-b.savedAt);
    let total=rows.reduce((sum,row)=>sum+row.bytes,0);
    for(const row of rows.filter(row=>!row.manual))if(total+bytes>limit){await records.delete(row.key);total-=row.bytes;}
    if(total+bytes>limit){tx.abort();await tx.done.catch(()=>{});throw new Error(t('copy.280'));}
    try{await records.put({key,userId,track,blob,artworkBlob,bytes,savedAt:Date.now(),manual:operation.manual||!!existing?.manual});await tx.done;}
    catch(error){if(error instanceof DOMException&&error.name==='QuotaExceededError')throw new Error(t('copy.281'));throw error;}
    for(const listener of operation.progress)listener(1);window.dispatchEvent(new Event('wave:cache'));
  })().finally(()=>{externalSignal?.removeEventListener('abort',cancelSpeculative);if(inFlight.get(key)===operation)inFlight.delete(key);});
  inFlight.set(key,operation);return operation.promise;
}

export async function pinDownload(userId:string,trackId:string){const db=await getDatabase();if(!db)return;const key=`${userId}:${trackId}`,tx=db.transaction('downloads','readwrite'),row=await tx.store.get(key);if(row)await tx.store.put({...row,manual:true});await tx.done;window.dispatchEvent(new Event('wave:cache'));}
