import type {Playback} from './types';
type Entry={at:number;value?:Playback;job?:Promise<Playback>};
/** Metadata preparation only; no unrestricted downloads or background converters. */
export class PlaybackWarmup {
 private account='';private entries=new Map<string,Entry>();
 reset(account:string){if(this.account===account)return;this.account=account;this.entries.clear();}
 async get(id:string,resolve:()=>Promise<Playback>,fresh=false):Promise<Playback>{
  let entry=this.entries.get(id);
  if(fresh||entry&&Date.now()-entry.at>60000){this.entries.delete(id);entry=undefined;}
  if(entry?.value)return entry.value;
  if(entry?.job)return entry.job;
  entry={at:Date.now()};this.entries.set(id,entry);
  while(this.entries.size>3)this.entries.delete(this.entries.keys().next().value!);
  const account=this.account,record=entry;
  entry.job=resolve().then(value=>{if(account===this.account){if(value.kind==='audio'&&value.url){record.value=value;record.job=undefined;}else if(this.entries.get(id)===record)this.entries.delete(id);}return value;},error=>{if(this.entries.get(id)===record)this.entries.delete(id);throw error;});
  return entry.job;
 }
}
