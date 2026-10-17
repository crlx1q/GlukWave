import {api,ApiError} from './api';
import {getCacheGeneration,readMetadata,saveMetadata,removeMetadata,type MetadataEntry} from './cache';

const rows=new Map<string,MetadataEntry>(),flights=new Map<string,Promise<unknown>>();
let currentAccount:string|null=null,epoch=0;
export function setMetadataAccount(account:string|null){if(account!==currentAccount){currentAccount=account;epoch++;rows.clear();flights.clear();}}
export function peekMetadata<T>(account:string,path:string){return rows.get(`${account}:${path}`)?.value as T|undefined;}
export async function readCachedMetadata<T>(account:string,path:string){
 const existing=peekMetadata<T>(account,path);if(existing)return existing;
 const version=epoch,row=await readMetadata(account,path).catch(()=>undefined);
 if(version!==epoch||account!==currentAccount)return;
 if(row){const latest=rows.get(`${account}:${path}`);if(latest&&latest.at>row.at)return latest.value as T;rows.set(`${account}:${path}`,row);return row.value as T;}
}
/** Caller paints the saved snapshot first, then awaits this coalesced refresh. */
export function cachedMetadata<T>(path:string,{account,signal,maxAge=120000,force=false}:{account:string;signal?:AbortSignal;maxAge?:number;force?:boolean}):Promise<T>{
 if(account!==currentAccount)return Promise.reject(new DOMException('Account changed','AbortError'));
 const key=`${account}:${path}`,saved=rows.get(key);
 if(!force&&saved&&Date.now()-saved.at<maxAge)return Promise.resolve(saved.value as T);
 const active=flights.get(key);if(active)return follow(active as Promise<T>,signal);
 const version=epoch,controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),20000);
 const job=(async()=>{
  const generation=await getCacheGeneration(account).catch(()=>0);
  try{
   const value=await api<T>(path,{signal:controller.signal});
   if(account!==currentAccount||version!==epoch)throw new DOMException('Account changed','AbortError');
   rows.delete(key);rows.set(key,{key,userId:account,at:Date.now(),value});while(rows.size>48)rows.delete(rows.keys().next().value!);
   void saveMetadata(account,path,value,generation).catch(()=>{});return value;
  }catch(error){if(error instanceof ApiError&&[401,403,404].includes(error.status||0)){rows.delete(key);await removeMetadata(account,path).catch(()=>{});}else if(account===currentAccount&&version===epoch&&saved)return saved.value as T;throw error;}
  finally{clearTimeout(timeout);}
 })();
 flights.set(key,job);void job.then(()=>{if(flights.get(key)===job)flights.delete(key);},()=>{if(flights.get(key)===job)flights.delete(key);});return follow(job,signal);
}
function follow<T>(job:Promise<T>,signal?:AbortSignal):Promise<T>{
 if(!signal)return job;if(signal.aborted)return Promise.reject(new DOMException('Aborted','AbortError'));
 return new Promise((resolve,reject)=>{const abort=()=>reject(new DOMException('Aborted','AbortError'));signal.addEventListener('abort',abort,{once:true});job.then(value=>{signal.removeEventListener('abort',abort);if(!signal.aborted)resolve(value);},error=>{signal.removeEventListener('abort',abort);reject(error);});});
}
