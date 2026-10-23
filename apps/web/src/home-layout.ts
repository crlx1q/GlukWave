import type {HomeLayout,HomeWidget,HomePin} from './types';
const singleton=['wave','playlists','recent','recommendations','discovery','popular','daily'];
const types=[...singleton,'likes','playlist','mix'];
export function normalizeHomeLayout(value:unknown):HomeLayout|null{
 if(!value||typeof value!=='object'||Array.isArray(value))return null;
 const input=value as Record<string,unknown>;if(input.version!==1||!Array.isArray(input.widgets))return null;
 const ids=new Set<string>(),once=new Set<string>(),widgets:HomeWidget[]=[];
 for(const item of input.widgets){if(!item||typeof item!=='object'||Array.isArray(item))continue;const row=item as Record<string,unknown>;
  if(typeof row.id!=='string'||!/^[-\w]{1,80}$/.test(row.id)||ids.has(row.id)||!types.includes(String(row.type))||!['small','medium','large'].includes(String(row.size))||!['cards','list','compact'].includes(String(row.view)))continue;
  const type=row.type as HomeWidget['type'];if(singleton.includes(type)&&once.has(type))continue;
  const next:HomeWidget={id:row.id,type,size:row.size as HomeWidget['size'],view:row.view as HomeWidget['view']};
  if(type==='playlist'){if(typeof row.playlistId!=='string'||!row.playlistId||row.playlistId.length>200)continue;next.playlistId=row.playlistId;}
  if(type==='mix'){if(typeof row.genre!=='string'||!row.genre.trim()||row.genre.trim().length>40||!['personal','energy','happy','calm','sad','focus','dream'].includes(String(row.mood)))continue;next.genre=row.genre.trim();next.mood=row.mood as HomeWidget['mood'];}
  ids.add(row.id);once.add(type);widgets.push(next);if(widgets.length===20)break;
 }return input.widgets.length&&!widgets.length?null:{version:1,widgets};
}
export function defaultHomeLayout(pins:HomePin[]=[]):HomeLayout{
 const core=(id:string,type:HomeWidget['type']):HomeWidget=>({id,type,size:'large',view:'cards'});
 const used=new Set(['wave','playlists','recent','recommendations','discovery','popular']);
 const compatible=pins.slice(0,12).map((pin,index)=>{let id=`pin-${index}-${pin.id}`.slice(0,80);let suffix=0;while(used.has(id))id=`pin-${index}-${++suffix}-${pin.id}`.slice(0,80);used.add(id);return{...pin,id,size:'small' as const,view:'compact' as const,...(pin.type==='mix'?{mood:pin.mood||'personal' as const}:{})};});
 return{version:1,widgets:[core('wave','wave'),core('playlists','playlists'),...compatible,core('recent','recent'),core('recommendations','recommendations'),core('discovery','discovery'),core('popular','popular')]};
}
export function moveHomeWidget(items:HomeWidget[],from:number,to:number){if(from<0||to<0||from>=items.length||to>=items.length||from===to)return items;const next=[...items],[item]=next.splice(from,1);next.splice(to,0,item);return next;}
