import crypto from 'node:crypto';
import {promisify} from 'node:util';
import {z} from 'zod';

const scrypt=promisify(crypto.scrypt);
export const id=()=>crypto.randomUUID();
export const now=()=>new Date().toISOString();
export const secret=()=>crypto.randomBytes(32).toString('base64url');
export const digest=value=>crypto.createHash('sha256').update(value).digest('hex');
export class HttpError extends Error {constructor(status,code,message,details){super(message);this.status=status;this.code=code;this.details=details;}}
export const fail=(status,code,message,details)=>{throw new HttpError(status,code,message,details);};
export function parse(schema,input){const r=schema.safeParse(input);if(!r.success)fail(400,'VALIDATION','Проверь заполненные поля.',r.error.flatten());return r.data;}
export const text=(max=200)=>z.string().trim().min(1).max(max);
export const uuid=z.string().uuid();
export const publicUser=u=>{if(!u)return null;const {passwordHash,blocked,...d}=u;return d;};
export async function hashPassword(value){const salt=crypto.randomBytes(16).toString('hex');const key=await scrypt(value,salt,64,{N:32768,r:8,p:1,maxmem:64*1024*1024});return `${salt}:${key.toString('hex')}`;}
export async function verifyPassword(value,hash){if(!hash){await scrypt(value,'glukwave-dummy-salt',64,{N:32768,r:8,p:1,maxmem:64*1024*1024});return false;}const [salt,encoded]=hash.split(':');const key=await scrypt(value,salt,64,{N:32768,r:8,p:1,maxmem:64*1024*1024});const expected=Buffer.from(encoded,'hex');return expected.length===key.length&&crypto.timingSafeEqual(key,expected);}
export function seal(value,key){const iv=crypto.randomBytes(12);const cipher=crypto.createCipheriv('aes-256-gcm',Buffer.from(key,'hex'),iv);const body=Buffer.concat([cipher.update(JSON.stringify(value)),cipher.final()]);return [iv,cipher.getAuthTag(),body].map(v=>v.toString('base64url')).join('.');}
export function unseal(value,key){const [iv,tag,body]=value.split('.').map(v=>Buffer.from(v,'base64url'));const cipher=crypto.createDecipheriv('aes-256-gcm',Buffer.from(key,'hex'),iv);cipher.setAuthTag(tag);return JSON.parse(Buffer.concat([cipher.update(body),cipher.final()]).toString());}
export const defaultAppearance={light:{bg:'#efede3',surface:'#f8f7f1',ink:'#302f2c',accent:'#a08369'},dark:{bg:'#141517',surface:'#202225',ink:'#eeeae3',accent:'#b1a2de'},amoled:{bg:'#000000',surface:'#0b0b0b',ink:'#f4f1f7',accent:'#b1a2de'},radius:24,speed:1,compact:false,blur:true,waveStyle:'silk',cover3d:true,coverKind:'vinyl'};
export const defaultSettings={autoCache:true,cacheLimitMB:1024,lyrics:true,comments:true,lyricsUnderCover:true,fontFamily:'manrope',fontScale:1,discordPresence:true,notifications:false,language:'auto',theme:'light',reducedMotion:false,seasonalEffects:{enabled:false,mode:'auto',intensity:'subtle'},appearance:defaultAppearance,equalizer:{enabled:false,preamp:0,bands:Array(10).fill(0)},playbackRate:1};
export function mergeSettings(previous={},changes={}){
  const before=previous.appearance||{},next=changes.appearance||{};
  return {...defaultSettings,...previous,...changes,seasonalEffects:{...defaultSettings.seasonalEffects,...previous.seasonalEffects,...changes.seasonalEffects},equalizer:{...defaultSettings.equalizer,...previous.equalizer,...changes.equalizer},appearance:{...defaultAppearance,...before,...next,light:{...defaultAppearance.light,...before.light,...next.light},dark:{...defaultAppearance.dark,...before.dark,...next.dark},amoled:{...defaultAppearance.amoled,...before.amoled,...next.amoled}}};
}
export function keyboardSuggestion(q){const en="qwertyuiop[]asdfghjkl;'zxcvbnm,./`",ru='йцукенгшщзхъфывапролджэячсмитьбю.ё';if(!/[a-z]/i.test(q)||/[а-яё]/i.test(q))return null;const mapped=[...q].map(c=>{const i=en.indexOf(c.toLowerCase());return i<0?c:c===c.toUpperCase()?ru[i].toUpperCase():ru[i];}).join('');return mapped===q?null:mapped;}
export function parseLyrics(raw){
  let sync=false;const lines=[];
  for(const line of raw.split(/\r?\n/)){
    // Standard LRC uses minutes:seconds.fraction; three colon groups explicitly mean hours.
    const matches=[...line.matchAll(/\[(?:(\d{1,3}):(\d{2}):(\d{2})|(\d{1,4}):(\d{2}))(?:\.(\d{1,3}))?\]/g)];
    const content=line.replace(/\[[^\]]*\]/g,'').trim();if(!content)continue;
    const timestamps=matches.flatMap(m=>{
      const hours=m[1]===undefined?0:Number(m[1]),minutes=Number(m[2]??m[4]),seconds=Number(m[3]??m[5]);
      if(seconds>=60||(m[1]!==undefined&&minutes>=60))return [];
      return [hours*3600+minutes*60+seconds+(m[6]?Number(`0.${m[6]}`):0)];
    });
    if(timestamps.length){sync=true;for(const time of timestamps)lines.push({time,text:content});}
    else if(!/^\[[a-z]+:/i.test(line))lines.push({time:null,text:content});
  }
  return {lines:lines.sort((a,b)=>(a.time??Infinity)-(b.time??Infinity)),synchronized:sync,source:'user'};
}
export async function remoteJson(url,options={}){const r=await fetch(url,{...options,signal:AbortSignal.timeout(12000)});if(!r.ok)fail(r.status===429?429:502,'PROVIDER_ERROR',`Площадка ответила ошибкой ${r.status}. Попробуй позже.`);return r.json();}
export const asyncRoute=fn=>(req,res,next)=>Promise.resolve(fn(req,res,next)).catch(next);
