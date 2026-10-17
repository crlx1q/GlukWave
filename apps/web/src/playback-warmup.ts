import type {Playback} from './types';
type Entry={at:number;value?:Playback;job?:Promise<Playback>;controller?:AbortController;foreground?:boolean};
/** Metadata preparation only; no unrestricted downloads or background converters. */
export class PlaybackWarmup {
 private account='';private entries=new Map<string,Entry>();
 reset(account:string){if(this.account===account)return;this.account=account;for(const entry of this.entries.values())entry.controller?.abort();this.entries.clear();}
 async get(id:string,resolve:()=>Promise<Playback>,fresh=false):Promise<Playback>{
  let entry=this.entries.get(id);
  if(fresh||entry&&Date.now()-entry.at>60000){this.entries.delete(id);entry=undefined;}
  if(entry?.value)return entry.value;
  if(entry?.job){entry.foreground=true;return entry.job;}
  entry={at:Date.now(),foreground:true};this.entries.set(id,entry);
  while(this.entries.size>3)this.entries.delete(this.entries.keys().next().value!);
  const account=this.account,record=entry;
  entry.job=resolve().then(value=>{if(account===this.account){if(value.kind==='audio'&&value.url){record.value=value;record.job=undefined;}else if(this.entries.get(id)===record)this.entries.delete(id);}return value;},error=>{if(this.entries.get(id)===record)this.entries.delete(id);throw error;});
  return entry.job;
 }
 async prepare(id:string,resolve:(signal:AbortSignal)=>Promise<Playback>,signal:AbortSignal):Promise<Playback>{
  if(signal.aborted)throw new DOMException('Aborted','AbortError');
  const hit=this.entries.get(id);if(hit&&Date.now()-hit.at<=60000){if(hit.value)return hit.value;if(hit.job)return hit.job;}
  const controller=new AbortController(),entry:Entry={at:Date.now(),controller,foreground:false};this.entries.set(id,entry);
  while(this.entries.size>3){const key=this.entries.keys().next().value!,old=this.entries.get(key);if(!old?.foreground)old?.controller?.abort();this.entries.delete(key);}
  const abort=()=>{if(!entry.foreground){controller.abort();if(this.entries.get(id)===entry)this.entries.delete(id);}};signal.addEventListener('abort',abort,{once:true});
  const account=this.account;
  entry.job=resolve(controller.signal).then(value=>{if(account===this.account&&this.entries.get(id)===entry&&value.kind==='audio'&&value.url){entry.value=value;entry.job=undefined;}return value;},error=>{if(this.entries.get(id)===entry)this.entries.delete(id);throw error;}).finally(()=>signal.removeEventListener('abort',abort));
  return entry.job;
 }
}
