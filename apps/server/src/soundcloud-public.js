import {load} from 'cheerio';
import {fail} from './util.js';

const origin='https://soundcloud.com';
const maxPageBytes=2*1024*1024;
const reserved=new Set(['search','discover','charts','you','settings','pages','upload','terms-of-use','popular','tags']);
export function soundcloudWaveformUrl(value){
  try{const url=new URL(value);if(url.protocol!=='https:'||url.hostname!=='wave.sndcdn.com'||url.port||url.username||url.password||!/^\/[a-z\d_-]{1,160}\.(?:json|png)$/i.test(url.pathname))return null;return `https://wave.sndcdn.com${url.pathname.replace(/\.png$/i,'.json')}`;}catch{return null;}
}
export function soundcloudTrackUrl(value){
  let url;try{url=new URL(value,origin);}catch{return null;}
  if(url.protocol!=='https:'||!['soundcloud.com','www.soundcloud.com'].includes(url.hostname)||url.port||url.username||url.password)return null;
  const parts=url.pathname.split('/').filter(Boolean);
  if(parts.length!==2||reserved.has(parts[0])||parts[1]==='sets'||parts.some(part=>!/^[a-z\d_-]{1,200}$/i.test(part)))return null;
  return `${origin}/${parts.join('/')}`;
}
export function parseSoundcloudSearch(html){
  const $=load(html),found=new Map();
  $('noscript').each((_,section)=>{const fragment=load($(section).html()||'',{scriptingEnabled:false},false);fragment('h2 a[href]').each((_,element)=>{const url=soundcloudTrackUrl(fragment(element).attr('href')),title=fragment(element).text().trim().slice(0,200);if(url&&title)found.set(url,{url,title});});});
  return [...found.values()].slice(0,10);
}
export function parseSoundcloudTrack(html,expectedUrl){
  const $=load(html);let entries;
  for(const element of $('script').toArray()){
    const body=$(element).text(),start=body.indexOf('window.__sc_hydration');
    if(start<0)continue;
    const match=body.slice(start).match(/^window\.__sc_hydration\s*=\s*(\[.*\])\s*;?\s*$/s);
    if(match){try{entries=JSON.parse(match[1]);}catch{}break;}
  }
  const track=Array.isArray(entries)?entries.find(entry=>entry.hydratable==='sound'&&entry.data?.kind==='track')?.data:null;
  if(!track||track.sharing&&track.sharing!=='public'||!soundcloudTrackUrl(track.permalink_url))return null;
  const title=typeof track.title==='string'?track.title.trim().slice(0,200):'',sid=track.urn||String(track.id||'');
  if(!title||!/^[\w:.-]{1,100}$/.test(sid))return null;
  const artwork=value=>{try{const url=new URL(value);return url.protocol==='https:'&&/^(?:[a-z\d-]+\.)*sndcdn\.com$/i.test(url.hostname)?url.toString():'';}catch{return '';}};
  const duration=Number(track.duration);
  return {id:track.id,urn:sid,title,user:{username:String(track.user?.username||'').slice(0,200),avatar_url:artwork(track.user?.avatar_url)},artwork_url:artwork(track.artwork_url),waveform_url:soundcloudWaveformUrl(track.waveform_url),duration:Number.isFinite(duration)&&duration>0&&duration<=86400000?duration:0,permalink_url:soundcloudTrackUrl(track.permalink_url)||expectedUrl};
}

export async function readSoundcloudPage(value,fetcher=fetch){
  let url=new URL(value),redirects=0;
  for(;;){
    if(url.protocol!=='https:'||!['soundcloud.com','www.soundcloud.com'].includes(url.hostname)||url.port||url.username||url.password)fail(400,'UNSUPPORTED_URL','Нужна публичная ссылка SoundCloud.');
    const response=await fetcher(url,{redirect:'manual',headers:{Accept:'text/html','User-Agent':'GlukWave/0.1 (+https://wave.gluk.tech)'},signal:AbortSignal.timeout(8000)});
    if([301,302,303,307,308].includes(response.status)){
      await response.body?.cancel();if(++redirects>3||!response.headers.get('location'))fail(502,'SOUNDCLOUD_REDIRECT','SoundCloud не открыл страницу.');url=new URL(response.headers.get('location'),url);continue;
    }
    if(!response.ok){await response.body?.cancel();fail(response.status===429?429:502,'SOUNDCLOUD_PUBLIC_ERROR',`SoundCloud ответил ${response.status}. Попробуй позже или открой ссылку трека.`);}
    if(!response.headers.get('content-type')?.includes('text/html')){await response.body?.cancel();fail(502,'SOUNDCLOUD_FORMAT','SoundCloud вернул неизвестный формат.');}
    if(Number(response.headers.get('content-length'))>maxPageBytes){await response.body?.cancel();fail(502,'SOUNDCLOUD_FORMAT','Страница SoundCloud слишком большая.');}
    const reader=response.body.getReader(),chunks=[];let size=0;
    try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>maxPageBytes)fail(502,'SOUNDCLOUD_FORMAT','Страница SoundCloud слишком большая.');chunks.push(Buffer.from(value));}}
    finally{await reader.cancel().catch(()=>{});}
    return Buffer.concat(chunks).toString('utf8');
  }
}

export function createPublicSoundcloud({fetcher=fetch}={}){
  const cache=new Map(),pending=new Map(),waiters=[];let active=0,minute=Date.now(),requests=0;
  async function page(url){
    if(waiters.length>=40)fail(503,'SOUNDCLOUD_BUSY','Поиск SoundCloud занят. Попробуй через минуту.');
    if(active>=4)await new Promise(resolve=>waiters.push(resolve));else active++;
    try{if(Date.now()-minute>=60000){minute=Date.now();requests=0;}if(++requests>180)fail(429,'SOUNDCLOUD_LIMIT','Дай SoundCloud немного времени. Повтори поиск через минуту.');return await readSoundcloudPage(url,fetcher);}
    finally{if(waiters.length)waiters.shift()();else active--;}
  }
  async function cached(key,ttl,operation){
    const saved=cache.get(key);if(saved?.expiresAt>Date.now())return saved.value;
    if(pending.has(key))return pending.get(key);
    const promise=(async()=>{const value=await operation();cache.delete(key);cache.set(key,{value,expiresAt:Date.now()+ttl});if(cache.size>2200)cache.delete(cache.keys().next().value);return value;})();
    pending.set(key,promise);try{return await promise;}finally{pending.delete(key);}
  }
  async function track(value){const url=soundcloudTrackUrl(value);if(!url)fail(400,'UNSUPPORTED_URL','Нужна ссылка SoundCloud на отдельный трек.');return cached(url,3600000,async()=>{const result=parseSoundcloudTrack(await page(url),url);if(!result)fail(502,'SOUNDCLOUD_METADATA','SoundCloud не открыл данные трека. Попробуй официальную ссылку позже.');return result;});}
  async function search(query){
    const q=String(query).trim();if(!q||q.length>200)fail(400,'VALIDATION','Введи запрос до 200 символов.');
    return cached('search:'+q.toLowerCase(),300000,async()=>{
      const html=await page(`${origin}/search/sounds?${new URLSearchParams({q})}`),candidates=parseSoundcloudSearch(html);
      if(!candidates.length){const $=load(html,{scriptingEnabled:false});if(!$('noscript').length||!$('a[href="/search/sounds"]').length)fail(502,'SOUNDCLOUD_FORMAT','SoundCloud изменил страницу поиска. Открой трек по ссылке.');return [];}
      const results=await Promise.allSettled(candidates.map(candidate=>track(candidate.url))),tracks=results.filter(result=>result.status==='fulfilled').map(result=>result.value);
      if(!tracks.length)throw results.find(result=>result.status==='rejected').reason;
      return tracks;
    });
  }
  return {search,track};
}
