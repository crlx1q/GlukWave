import {load} from 'cheerio';
import {fail,HttpError} from './util.js';

const origin='https://soundcloud.com';
const maxPageBytes=2*1024*1024;
const reserved=new Set(['search','discover','charts','you','settings','pages','upload','terms-of-use','popular','tags']);
export function publicSoundcloudClient(html){
  const $=load(html);for(const element of $('script').toArray()){
    const body=$(element).text(),start=body.indexOf('window.__sc_hydration');if(start<0)continue;
    const match=body.slice(start).match(/^window\.__sc_hydration\s*=\s*(\[.*\])\s*;?\s*$/s);if(!match)return null;
    try{const entries=JSON.parse(match[1]),identifier=entries.find(entry=>entry.hydratable==='apiClient')?.data?.id;return typeof identifier==='string'&&/^[a-z\d]{32}$/i.test(identifier)?identifier:null;}catch{return null;}
  }return null;
}
export function publicSoundcloudHydration(html){
  const $=load(html);for(const element of $('script').toArray()){
    const match=$(element).text().match(/window\.__sc_hydration\s*=\s*(\[.*\])\s*;?\s*$/s);
    if(match){try{return JSON.parse(match[1]);}catch{return [];}}
  }return [];
}
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
  const artwork=value=>{try{const url=new URL(value);return url.protocol==='https:'&&/^(?:[a-z\d-]+\.)*sndcdn\.com$/i.test(url.hostname)?url.toString().replace(/-large\./i,'-t500x500.'):'';}catch{return '';}};
  const duration=Number(track.duration);
  const artistPath=String(track.user?.permalink||'');
  return {id:track.id,urn:sid,title,downloadable:track.downloadable===true,license:String(track.license||'').slice(0,500),genre:String(track.genre||'').slice(0,200),tag_list:String(track.tag_list||'').slice(0,1000),user:{id:track.user?.id,permalink:artistPath,permalink_url:/^[\w-]+$/.test(artistPath)?`${origin}/${artistPath}`:'',username:String(track.user?.username||'').slice(0,200),avatar_url:artwork(track.user?.avatar_url)},artwork_url:artwork(track.artwork_url),waveform_url:soundcloudWaveformUrl(track.waveform_url),duration:Number.isFinite(duration)&&duration>0&&duration<=86400000?duration:0,permalink_url:soundcloudTrackUrl(track.permalink_url)||expectedUrl};
}

export async function readSoundcloudPage(value,fetcher=fetch,signal){
  let url=new URL(value),redirects=0;
  for(;;){
    if(url.protocol!=='https:'||!['soundcloud.com','www.soundcloud.com'].includes(url.hostname)||url.port||url.username||url.password)fail(400,'UNSUPPORTED_URL','Нужна публичная ссылка SoundCloud.');
    const response=await fetcher(url,{redirect:'manual',headers:{Accept:'text/html','User-Agent':'GlukWave/0.1 (+https://wave.gluk.tech)'},signal:signal?AbortSignal.any([signal,AbortSignal.timeout(8000)]):AbortSignal.timeout(8000)});
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
  async function request(operation){
    if(waiters.length>=40)fail(503,'SOUNDCLOUD_BUSY','Поиск SoundCloud занят. Попробуй через минуту.');
    if(active>=4)await new Promise((resolve,reject)=>{let timer;const wake=()=>{clearTimeout(timer);resolve();};timer=setTimeout(()=>{const at=waiters.indexOf(wake);if(at>=0){waiters.splice(at,1);reject(new HttpError(503,'SOUNDCLOUD_BUSY','SoundCloud занят. Попробуй чуть позже.'));}},8000);timer.unref();waiters.push(wake);});else active++;
    try{if(Date.now()-minute>=60000){minute=Date.now();requests=0;}if(++requests>180)fail(429,'SOUNDCLOUD_LIMIT','Дай SoundCloud немного времени. Повтори поиск через минуту.');return await operation();}
    finally{if(waiters.length)waiters.shift()();else active--;}
  }
  const page=(url,signal)=>request(()=>readSoundcloudPage(url,fetcher,signal));
  async function unicodeCandidates(q,html){
    // SoundCloud's anonymous HTML search currently decodes UTF-8 queries as
    // Latin-1. Use the same public JSON search as its website, with its public
    // application identifier. No account cookies, OAuth tokens or private API
    // credentials are copied, persisted or returned to our clients.
    const identifier=publicSoundcloudClient(html);if(!identifier)fail(502,'SOUNDCLOUD_FORMAT','SoundCloud не открыл поиск. Повтори позже.');
    return request(async()=>{
      const url='https://api-v2.soundcloud.com/search/tracks?'+new URLSearchParams({q,client_id:identifier,limit:'10'});
      const response=await fetcher(url,{redirect:'error',headers:{Accept:'application/json'},signal:AbortSignal.timeout(8000)});
      if(!response.ok){await response.body?.cancel();fail(response.status===429?429:502,'SOUNDCLOUD_PUBLIC_ERROR','Поиск SoundCloud сейчас недоступен. Повтори позже.');}
      if(!response.headers.get('content-type')?.includes('json')){await response.body?.cancel();fail(502,'SOUNDCLOUD_FORMAT','SoundCloud вернул неизвестный формат.');}
      const reader=response.body.getReader(),chunks=[];let size=0;
      try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>maxPageBytes)fail(502,'SOUNDCLOUD_FORMAT','Ответ SoundCloud слишком большой.');chunks.push(Buffer.from(value));}}
      finally{await reader.cancel().catch(()=>{});}
      let data;try{data=JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{fail(502,'SOUNDCLOUD_FORMAT','SoundCloud вернул неизвестный формат.');}
      if(!Array.isArray(data.collection))fail(502,'SOUNDCLOUD_FORMAT','SoundCloud вернул неизвестный формат.');
      return data.collection.filter(track=>track?.kind==='track'&&track.sharing==='public').map(track=>({url:soundcloudTrackUrl(track.permalink_url)})).filter(track=>track.url).slice(0,10);
    });
  }
  async function cached(key,ttl,operation){
    const saved=cache.get(key);if(saved?.expiresAt>Date.now())return saved.value;
    if(pending.has(key))return pending.get(key);
    const promise=(async()=>{const value=await operation();cache.delete(key);cache.set(key,{value,expiresAt:Date.now()+ttl});if(cache.size>2200)cache.delete(cache.keys().next().value);return value;})();
    pending.set(key,promise);try{return await promise;}finally{pending.delete(key);}
  }
  async function track(value){const url=soundcloudTrackUrl(value);if(!url)fail(400,'UNSUPPORTED_URL','Нужна ссылка SoundCloud на отдельный трек.');return cached(url,3600000,async()=>{const result=parseSoundcloudTrack(await page(url),url);if(!result)fail(502,'SOUNDCLOUD_METADATA','SoundCloud не открыл данные трека. Попробуй официальную ссылку позже.');return result;});}
  async function search(query){
    const q=String(query).normalize('NFC').trim();if(!q||q.length>200)fail(400,'VALIDATION','Введи запрос до 200 символов.');
    return cached('search:'+q.toLowerCase(),300000,async()=>{
      const html=await page(`${origin}/search/sounds?${new URLSearchParams({q})}`),candidates=/[^\x00-\x7f]/.test(q)?await unicodeCandidates(q,html):parseSoundcloudSearch(html);
      if(!candidates.length){const $=load(html,{scriptingEnabled:false});if(!$('noscript').length||!$('a[href="/search/sounds"]').length)fail(502,'SOUNDCLOUD_FORMAT','SoundCloud изменил страницу поиска. Открой трек по ссылке.');return [];}
      const results=await Promise.allSettled(candidates.map(candidate=>track(candidate.url))),tracks=results.filter(result=>result.status==='fulfilled').map(result=>result.value);
      if(!tracks.length)throw results.find(result=>result.status==='rejected').reason;
      return tracks;
    });
  }
  async function api(route,client,signal){return request(async()=>{
    const url=new URL(route,'https://api-v2.soundcloud.com');
    if(url.origin!=='https://api-v2.soundcloud.com'||url.username||url.password||!/^\/(?:resolve|users\/\d+\/(?:playlists|likes)|tracks)$/.test(url.pathname))fail(400,'INVALID_CURSOR','Неверная страница SoundCloud.');
    url.searchParams.set('client_id',client);
    const response=await fetcher(url,{redirect:'error',headers:{Accept:'application/json'},signal:signal?AbortSignal.any([signal,AbortSignal.timeout(8000)]):AbortSignal.timeout(8000)});
    if(!response.ok){await response.body?.cancel();fail([401,403,404].includes(response.status)?403:response.status===429?429:502,'PUBLIC_COLLECTION_UNAVAILABLE','SoundCloud не открыл публичную коллекцию.');}
    const reader=response.body?.getReader(),chunks=[];let size=0;if(!reader)fail(502,'SOUNDCLOUD_FORMAT','Пустой ответ SoundCloud.');
    try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>maxPageBytes)fail(413,'PUBLIC_IMPORT_TOO_LARGE','Ответ SoundCloud слишком большой.');chunks.push(Buffer.from(value));}}finally{await reader.cancel().catch(()=>{});}
    try{return JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{fail(502,'SOUNDCLOUD_FORMAT','SoundCloud изменил формат данных.');}
  });}
  function target(value){const url=new URL(value),parts=url.pathname.split('/').filter(Boolean);if(url.origin!==origin||!parts.length||parts.some(p=>!/^[\w-]{1,200}$/.test(p))||parts.length>3||parts.length===3&&parts[1]!=='sets'||parts.length===2&&!['sets','likes'].includes(parts[1]))fail(400,'UNSUPPORTED_URL','Нужна ссылка на публичную коллекцию SoundCloud.');return {url:origin+'/'+parts.join('/'),profile:origin+'/'+parts[0],playlist:parts[1]==='sets'&&parts.length===3,likes:parts[1]==='likes'};}
  async function collectionInfo(value,signal){const input=target(value);return cached('collection-info:'+input.url,120000,async()=>{
    const html=await page(input.playlist?input.url:input.profile+'/sets',signal),client=publicSoundcloudClient(html),entries=publicSoundcloudHydration(html);
    if(!client)fail(502,'SOUNDCLOUD_FORMAT','SoundCloud не открыл данные коллекции.');
    let entity=entries.find(e=>e.data?.kind===(input.playlist?'playlist':'user'))?.data;
    if(!entity)entity=await api('/resolve?'+new URLSearchParams({url:input.playlist?input.url:input.profile}),client,signal);
    if(!entity||entity.kind!==(input.playlist?'playlist':'user')||entity.sharing==='private'||!/^\d+$/.test(String(entity.id)))fail(404,'PUBLIC_COLLECTION_UNAVAILABLE','Коллекция SoundCloud закрыта или не найдена.');
    return {input,entity,client};
  });}
  const collection=(value)=>({id:'public-'+Buffer.from(value.permalink_url||'').toString('base64url').slice(0,160),name:String(value.title||'Playlist').slice(0,200),artwork:value.artwork_url||value.user?.avatar_url||'',trackCount:Number(value.track_count)||0,sourceUrl:value.permalink_url});
  function nextPage(value,expected){if(!value)return null;const url=new URL(value,'https://api-v2.soundcloud.com');if(url.origin!=='https://api-v2.soundcloud.com'||url.pathname!==expected||url.username||url.password)fail(502,'INVALID_CURSOR','SoundCloud вернул неверную страницу.');url.searchParams.delete('client_id');return url.pathname+url.search;}
  async function collections(value,{signal}={}){const info=await collectionInfo(value,signal),{input,entity,client}=info;if(input.playlist)return {playlists:[collection(entity)]};
    if(input.likes){const first=await api(`/users/${entity.id}/likes?limit=1&linked_partitioning=true`,client,signal);if(!Array.isArray(first.collection))fail(403,'PUBLIC_COLLECTION_UNAVAILABLE','Лайки SoundCloud закрыты.');return {playlists:[{id:'public-likes-'+entity.id,name:'Лайки',artwork:entity.avatar_url||'',trackCount:Number(entity.likes_count)||first.collection.length,sourceUrl:input.profile+'/likes',kind:'likes'}]};}
    const route=`/users/${entity.id}/playlists`;let data=await api(route+'?limit=200&linked_partitioning=true',client,signal),items=Array.isArray(data)?data:data.collection;if(!Array.isArray(items))fail(502,'SOUNDCLOUD_FORMAT','SoundCloud не открыл плейлисты.');items=[...items];const seen=new Set();for(let pages=1;data.next_href&&pages<5;pages++){const next=nextPage(data.next_href,route);if(seen.has(next))fail(502,'INVALID_CURSOR','SoundCloud повторил страницу.');seen.add(next);data=await api(next,client,signal);if(!Array.isArray(data.collection))fail(502,'SOUNDCLOUD_FORMAT','SoundCloud не открыл плейлисты.');items.push(...data.collection);}
    const result={playlists:items.filter(p=>p&&p.sharing!=='private'&&p.kind==='playlist'&&/^https:\/\/soundcloud\.com\/[\w-]+\/sets\/[\w-]+$/.test(p.permalink_url||'')).map(collection)};
    try{const liked=await api(`/users/${entity.id}/likes?limit=1&linked_partitioning=true`,client,signal);if(Array.isArray(liked.collection))result.liked={id:'public-likes-'+entity.id,name:'Лайки',artwork:entity.avatar_url||'',trackCount:Number(entity.likes_count)||liked.collection.length,sourceUrl:input.profile+'/likes',kind:'likes'};}catch(error){if(![403,404].includes(error.status))throw error;}
    if(data.next_href)Object.assign(result,{partial:true,warnings:['PUBLIC_COLLECTIONS_PARTIAL']});return result;
  }
  async function collectionTracks(value,cursor='',{signal}={}){
    const {input,entity,client}=await collectionInfo(value,signal);let items,total,nextCursor,consumed=0,expectedItems=0;
    if(input.likes){
      const expected=`/users/${entity.id}/likes`;let route=expected+'?limit=100&linked_partitioning=true';
      if(cursor){if(!cursor.startsWith('sc:')||cursor.length>2048)fail(400,'INVALID_CURSOR','Неверная страница SoundCloud.');let decoded;try{decoded=JSON.parse(Buffer.from(cursor.slice(3),'base64url').toString());}catch{fail(400,'INVALID_CURSOR','Неверная страница SoundCloud.');}route=decoded.route;consumed=decoded.offset;let canonical;try{canonical=nextPage(route,expected);}catch{fail(400,'INVALID_CURSOR','Неверная страница SoundCloud.');}if(typeof route!=='string'||!Number.isInteger(consumed)||consumed<0||consumed>10000||canonical!==route)fail(400,'INVALID_CURSOR','Неверная страница SoundCloud.');}
      const data=await api(route,client,signal);if(!Array.isArray(data.collection))fail(502,'SOUNDCLOUD_FORMAT','SoundCloud не открыл лайки.');items=data.collection.map(x=>x.track||x).filter(x=>x?.kind==='track');expectedItems=items.length;total=Number(entity.likes_count)||items.length;const next=nextPage(data.next_href,expected);consumed+=items.length;nextCursor=next?'sc:'+Buffer.from(JSON.stringify({route:next,offset:consumed})).toString('base64url'):null;
    }else{
      if(!input.playlist||cursor&&!/^\d{1,5}$/.test(cursor)||Number(cursor)>10000)fail(400,'INVALID_CURSOR','Неверная страница SoundCloud.');
      if(!Array.isArray(entity.tracks))fail(502,'SOUNDCLOUD_FORMAT','SoundCloud не открыл песни.');
      const start=Number(cursor)||0;consumed=start+Math.min(100,entity.tracks.length-start);items=entity.tracks.slice(start,start+100);expectedItems=items.length;total=Number(entity.track_count)||entity.tracks.length;nextCursor=start+100<entity.tracks.length?String(start+100):null;
      const ids=items.filter(x=>x&&!x.title).map(x=>String(x.id)).filter(id=>/^\d+$/.test(id));
      if(ids.length){const hydrated=await api('/tracks?'+new URLSearchParams({ids:ids.join(',')}),client,signal),byId=new Map((Array.isArray(hydrated)?hydrated:hydrated.collection||[]).map(t=>[String(t.id),t]));items=items.map(x=>x?.title?x:x?byId.get(String(x.id)):null).filter(Boolean);}
    }
    // Return metadata only. Existing provider normalization/own audio pipeline
    // decides playback separately; previews and widgets are never substituted.
    const tracks=items.filter(x=>x&&x.title&&x.sharing!=='private'&&soundcloudTrackUrl(x.permalink_url));
    const partial=!nextCursor&&total>consumed;return {tracks,total,nextCursor,partial:partial||tracks.length<expectedItems,warnings:[...(partial?['PUBLIC_SOURCE_PARTIAL']:[]),...(tracks.length<expectedItems?['PUBLIC_UNAVAILABLE_TRACKS']:[])]};
  }
  return {search,track,collections,collectionTracks};
}
