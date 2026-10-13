export type ControlValues={volume:number;playing:boolean;position:number;shuffle:boolean;repeat:'off'|'all'|'one'};
export type ControlToken={scope:string;version:number;values:Partial<ControlValues>};
type Pending={version:number;value:ControlValues[keyof ControlValues];draft:boolean};
const fields=['volume','playing','position','shuffle','repeat'] as const;

/** Local presentation and canonical state have separate lifetimes. No network or timers live here. */
export class OptimisticControls {
 private scope='';private sequence=0;private invalidBefore=0;
 private accepted:ControlValues={volume:.8,playing:false,position:0,shuffle:false,repeat:'off'};
 private pending=new Map<keyof ControlValues,Pending>();
 reset(scope:string,state:Partial<ControlValues>){this.scope=scope;this.pending.clear();this.accepted={volume:.8,playing:false,position:0,shuffle:false,repeat:'off',...state};this.invalidBefore=++this.sequence;}
 ensure(scope:string,state:Partial<ControlValues>):Partial<ControlValues>{if(scope===this.scope)return {};const restored:Partial<ControlValues>={};for(const field of this.pending.keys())(restored as Record<string,unknown>)[field]=this.accepted[field];this.reset(scope,this.broadcast(state));return restored;}
 observe(state:Partial<ControlValues>){this.accepted={...this.accepted,...state};}
 observeUnheld(state:Partial<ControlValues>){for(const field of fields)if(!this.pending.has(field)&&state[field]!==undefined)(this.accepted as Record<string,unknown>)[field]=state[field];}
 begin(scope:string,state:Partial<ControlValues>,values:Partial<ControlValues>,draft=false):ControlToken {
  this.ensure(scope,state);const version=++this.sequence;
  for(const field of fields)if(values[field]!==undefined)this.pending.set(field,{version,value:values[field]!,draft});
  return {scope,version,values};
 }
 current(token:ControlToken){return token.scope===this.scope&&token.version>this.invalidBefore;}
 superseded(token:ControlToken){return !fields.some(field=>token.values[field]!==undefined&&this.pending.get(field)?.version===token.version);}
 has(field:keyof ControlValues){return this.pending.has(field);}
 overlay<T extends Partial<ControlValues>>(state:T):T {
  const values:Partial<ControlValues>={};for(const [field,edit]of this.pending)(values as Record<string,unknown>)[field]=edit.value;
  return {...state,...values};
 }
 broadcast<T extends Partial<ControlValues>>(state:T):T {
  const values:Partial<ControlValues>={};for(const field of this.pending.keys())(values as Record<string,unknown>)[field]=this.accepted[field];
  return {...state,...values};
 }
 settle(token:ControlToken,success:boolean,acceptSent=false):Partial<ControlValues> {
  if(!this.current(token))return {};
  if(success&&acceptSent)this.observe(token.values);
  const restore:Partial<ControlValues>={};
  for(const field of fields)if(token.values[field]!==undefined&&this.pending.get(field)?.version===token.version){
   this.pending.delete(field);(restore as Record<string,unknown>)[field]=this.accepted[field];
  }
  return restore;
 }
 cancelDraft(field:keyof ControlValues):Partial<ControlValues>{
  if(!this.pending.get(field)?.draft)return {};
  this.pending.delete(field);return {[field]:this.accepted[field]};
 }
}
