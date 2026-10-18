import type {HomePin} from './types';
const object=(value:unknown):Record<string,unknown>=>value&&typeof value==='object'&&!Array.isArray(value)?value as Record<string,unknown>:{};
export function normalizeHomePins(value:unknown):HomePin[]{
 if(!Array.isArray(value))return [];
 const result:HomePin[]=[],seen=new Set<string>();
 for(const item of value){
  const pin=object(item),id=typeof pin.id==='string'?pin.id:'';
  if(!/^[\w-]{1,80}$/.test(id)||seen.has(id))continue;
  if(pin.type==='likes')result.push({id,type:'likes'});
  else if(pin.type==='playlist'&&typeof pin.playlistId==='string'&&pin.playlistId.length>0&&pin.playlistId.length<=200)result.push({id,type:'playlist',playlistId:pin.playlistId});
  else if(pin.type==='mix'&&typeof pin.genre==='string'&&pin.genre.trim().length>0&&pin.genre.length<=40)result.push({id,type:'mix',genre:pin.genre.trim(),mood:['personal','energy','happy','calm','sad','focus','dream'].includes(String(pin.mood))?pin.mood as 'personal'|'energy'|'happy'|'calm'|'sad'|'focus'|'dream':'personal'});
  else continue;
  seen.add(id);if(result.length===12)break;
 }
 return result;
}

