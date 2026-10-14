import {load} from 'cheerio';
import {z} from 'zod';
import rateLimit from 'express-rate-limit';
import {asyncRoute,parse,text,fail,digest,now} from './util.js';

const providers=z.enum(['spotify','yandex','soundcloud','youtube']);
const pageSize=100,maxTracks=10000;
const clean=value=>String(value??'').trim().slice(0,500);
const image=value=>{try{const u=new URL(String(value).replace(/^\/\//,'https://'));return u.protocol==='https:'&&!u.username&&!u.password&&!u.port?u.href:'';}catch{return '';}};
const art=value=>image((Array.isArray(value?.sources)?value.sources.at(-1)?.url:'')||(Array.isArray(value?.images)?value.images.at(-1)?.url:'')||(Array.isArray(value)?value.at(-1)?.url:'')||value?.url||(typeof value==='string'?value:''));
const warnings=(partial,missing=false)=>[...(partial?['PUBLIC_SOURCE_PARTIAL']:[]),...(missing?['PUBLIC_UNAVAILABLE_TRACKS']:[])];

/** Exact provider hosts and collection paths only. Never accepts an upstream URL/cursor. */
export function publicImportTarget(provider,query){
  let input=String(query||'').normalize('NFC').trim(),u;
  if(!input||input.length>2048)fail(400,'PUBLIC_IMPORT_QUERY','Введи никнейм или HTTPS-ссылку на публичный профиль/плейлист.');
  if(!/^https:\/\//i.test(input)){
    if(/[:/?#\\\s]/.test(input))fail(400,'PUBLIC_IMPORT_QUERY','Нужен никнейм или полная HTTPS-ссылка.');
    input=input.replace(/^@/,'');
    if(!/^[\p{L}\p{N}_.-]{1,100}$/u.test(input))fail(400,'PUBLIC_IMPORT_QUERY','Проверь никнейм.');
    input=provider==='spotify'?`https://open.spotify.com/user/${encodeURIComponent(input)}`:provider==='yandex'?`https://music.yandex.ru/users/${encodeURIComponent(input)}`:provider==='soundcloud'?`https://soundcloud.com/${encodeURIComponent(input)}`:`https://www.youtube.com/@${encodeURIComponent(input)}/playlists`;
  }
  try{u=new URL(input);}catch{fail(400,'PUBLIC_IMPORT_QUERY','Проверь ссылку.');}
  if(u.protocol!=='https:'||u.username||u.password||u.port||/%2f|%5c|%00/i.test(u.pathname))fail(400,'PUBLIC_IMPORT_QUERY','Нужна HTTPS-ссылка площадки.');
  const hosts={spotify:['open.spotify.com'],yandex:['music.yandex.ru','music.yandex.com','music.yandex.kz'],soundcloud:['soundcloud.com','www.soundcloud.com'],youtube:['youtube.com','www.youtube.com','music.youtube.com','m.youtube.com']};
  if(!hosts[provider]?.includes(u.hostname))fail(400,'PUBLIC_IMPORT_QUERY','Ссылка не относится к выбранной площадке.');
  let match;
  if(provider==='spotify'){
    match=u.pathname.match(/^\/(?:intl-[a-z]{2}\/)?(?:embed\/)?(playlist|user)\/([\w.%~-]{1,150})\/?$/i);
    if(!match||match[1]==='playlist'&&!/^[a-z\d]{22}$/i.test(match[2]))fail(400,'PUBLIC_IMPORT_QUERY','Нужна ссылка на профиль или плейлист Spotify.');
    return {provider,kind:match[1]==='user'?'profile':'playlist',id:match[2],url:`https://open.spotify.com/${match[1]}/${match[2]}`};
  }
  if(provider==='yandex'){
    match=u.pathname.match(/^\/users\/([^/]+)(?:\/playlists\/(\d+)|\/(likes))?\/?$/);
    if(!match||!/^[\p{L}\p{N}_.%-]{1,150}$/u.test(match[1]))fail(400,'PUBLIC_IMPORT_QUERY','Нужна ссылка на пользователя, лайки или плейлист Яндекс Музыки.');
    return {provider,owner:match[1],id:match[2]||'likes',kind:match[2]?'playlist':match[3]?'likes':'profile',url:`https://music.yandex.ru/users/${match[1]}${match[2]?'/playlists/'+match[2]:match[3]?'/likes':''}`};
  }
  if(provider==='soundcloud'){
    match=u.pathname.match(/^\/([a-z\d_-]{1,100})(?:\/(sets)(?:\/([a-z\d_-]{1,200}))?|\/(likes))?\/?$/i);
    if(!match||['search','discover','you','settings','upload'].includes(match[1]))fail(400,'PUBLIC_IMPORT_QUERY','Нужна ссылка на профиль, sets или likes SoundCloud.');
    return {provider,owner:match[1],id:match[3]||'likes',kind:match[3]?'playlist':match[4]?'likes':'profile',url:`https://soundcloud.com/${match[1]}${match[3]?'/sets/'+match[3]:match[4]?'/likes':''}`};
  }
  const list=u.searchParams.get('list');
  if(list&&/^[\w-]{10,150}$/.test(list)&&['/playlist','/watch'].includes(u.pathname))return {provider,kind:'playlist',id:list,url:`https://www.youtube.com/playlist?list=${list}`};
  match=u.pathname.match(/^\/(@[\p{L}\p{N}_.%~-]{1,150}|channel\/UC[\w-]{22}|user\/[\w.-]{1,100})(?:\/playlists)?\/?$/u);
  if(!match)fail(400,'PUBLIC_IMPORT_QUERY','Нужна ссылка на плейлист или канал YouTube.');
  return {provider,kind:'profile',id:match[1],url:`https://www.youtube.com/${match[1]}/playlists`};
}

async function readPublic(url,{fetcher=fetch,signal,method='GET',body}={}){
  let u=new URL(url);const allowed=new Set(['open.spotify.com','api.music.yandex.net']);
  for(let redirects=0;redirects<4;redirects++){
    if(u.protocol!=='https:'||!allowed.has(u.hostname)||u.username||u.password||u.port)fail(400,'PUBLIC_IMPORT_QUERY','Недопустимый адрес площадки.');
    const response=await fetcher(u,{method,body,redirect:'manual',signal:signal?AbortSignal.any([signal,AbortSignal.timeout(8000)]):AbortSignal.timeout(8000),headers:{Accept:'application/json, text/html','User-Agent':'GlukWave/1.0 (+https://wave.gluk.tech)',...(body?{'Content-Type':'application/x-www-form-urlencoded'}:{})}});
    if([301,302,303,307,308].includes(response.status)){await response.body?.cancel();if(!response.headers.get('location'))break;const next=new URL(response.headers.get('location'),u);if(next.origin!==u.origin)fail(502,'PUBLIC_IMPORT_REDIRECT','Площадка перенаправила запрос на другой сайт.');u=next;continue;}
    if(!response.ok){await response.body?.cancel();fail(response.status===429?429:response.status===404?404:[401,403].includes(response.status)?403:502,[401,403,404].includes(response.status)?'PUBLIC_COLLECTION_UNAVAILABLE':'PUBLIC_IMPORT_UPSTREAM','Площадка не открыла коллекцию. Проверь, что профиль и плейлист публичные.');}
    if(Number(response.headers.get('content-length'))>4*1024*1024){await response.body?.cancel();fail(413,'PUBLIC_IMPORT_TOO_LARGE','Ответ площадки слишком большой. Открой отдельный плейлист.');}
    const chunks=[];let length=0;const reader=response.body?.getReader();if(!reader)fail(502,'PUBLIC_IMPORT_FORMAT','Пустой ответ площадки.');
    try{for(;;){const {done,value}=await reader.read();if(done)break;length+=value.length;if(length>4*1024*1024)fail(413,'PUBLIC_IMPORT_TOO_LARGE','Ответ площадки слишком большой.');chunks.push(Buffer.from(value));}}finally{await reader.cancel().catch(()=>{});}
    return Buffer.concat(chunks).toString('utf8');
  }
  fail(502,'PUBLIC_IMPORT_REDIRECT','Слишком много перенаправлений площадки.');
}
function json(value){try{return JSON.parse(value);}catch{fail(502,'PUBLIC_IMPORT_FORMAT','Площадка изменила формат открытых данных.');}}
function objects(root){const found=[],stack=[[root,0]];while(stack.length&&found.length<50000){const [value,depth]=stack.pop();if(!value||typeof value!=='object'||depth>22)continue;found.push(value);for(const item of Object.values(value))if(item&&typeof item==='object')stack.push([item,depth+1]);}return found;}
function baseTrack(provider,id,title,artist,album,artwork,duration,sourceUrl,extra={}){return {id:`${provider}-${id}`,sourceId:String(id),source:provider,title:clean(title),artist:clean(artist),album:clean(album),artwork:image(artwork),duration:Math.max(0,Math.min(86400,Number(duration)||0)),sourceUrl,public:true,createdAt:now(),playback:{kind:provider,offline:false},...extra};}
function collection(url,name,artwork,trackCount,extra={}){return {id:'public-'+digest(url).slice(0,32),name:clean(name)||'Playlist',artwork:image(artwork),trackCount:Math.max(0,Number(trackCount)||0),sourceUrl:url,...extra};}

export function parseSpotifyPublic(html,target){
  const $=load(html),roots=[];for(const element of $('script#__NEXT_DATA__,script[type="application/ld+json"]').toArray()){try{roots.push(JSON.parse($(element).text()));}catch{}}
  const nodes=roots.flatMap(objects);
  if(target.kind==='profile'){
    const lists=new Map();for(const item of nodes){const sid=String(item.uri||item.id||'').match(/(?:spotify:playlist:|^)([a-z\d]{22})$/i)?.[1];if(!sid||!(item.type==='playlist'||String(item.uri||'').startsWith('spotify:playlist:')))continue;const url=`https://open.spotify.com/playlist/${sid}`;lists.set(url,collection(url,item.name||item.title,art(item.coverArt||item.images),item.trackCount||item.tracks?.total||0));}
    $('a[href]').each((_,node)=>{const a=$(node),href=a.attr('href');let parsed;try{parsed=publicImportTarget('spotify',new URL(href,'https://open.spotify.com').href);}catch{return;}if(parsed.kind!=='playlist')return;if(!lists.has(parsed.url))lists.set(parsed.url,collection(parsed.url,a.attr('aria-label')||a.text().trim(),a.find('img').attr('src'),0));});
    if(!lists.size)fail(422,'PUBLIC_COLLECTION_UNAVAILABLE','Spotify не открыл плейлисты профиля. Попробуй прямую ссылку на публичный плейлист.');
    return {playlists:[...lists.values()].slice(0,1000),partial:true,warnings:['PUBLIC_COLLECTIONS_PARTIAL']};
  }
  const entity=nodes.find(item=>Array.isArray(item.trackList)&&(item.id===target.id||item.uri===`spotify:playlist:${target.id}`));
  if(!entity)fail(422,'PUBLIC_COLLECTION_UNAVAILABLE','Spotify не открыл список песен. Проверь публичную ссылку.');
  const artwork=art(entity.coverArt||entity.visualIdentity?.image),tracks=[];
  for(const item of entity.trackList){if(!item||typeof item!=='object')continue;const sid=String(item.uri||'').match(/^spotify:track:([a-z\d]{22})$/i)?.[1];if(!sid||!item.title)continue;tracks.push(baseTrack('spotify',sid,item.title,item.subtitle||item.artists?.map(a=>a.name).join(', '),item.album?.name||'',art(item.coverArt||item.album?.images)||artwork,(Number(item.duration)||0)/1000,`https://open.spotify.com/track/${sid}`));}
  const total=Number(entity.trackCount??entity.tracks?.total??entity.totalCount),partial=!Number.isFinite(total)||total>tracks.length;
  return {playlist:collection(target.url,entity.name||entity.title,artwork,Number.isFinite(total)?total:tracks.length),tracks,total:Number.isFinite(total)?total:tracks.length,partial,warnings:warnings(partial,entity.trackList.length>tracks.length)};
}
function yandexCover(value){return image(String(value?.uri||value?.coverUri||value||'').replace(/%%/g,'400x400').replace(/^(?!https?:\/\/)(.+)$/,'https://$1'));}
function yandexTrack(item){const id=String(item.id||''),album=item.albums?.[0];if(!/^\d+$/.test(id)||!item.title||!/^\d+$/.test(String(album?.id||''))||item.available===false)return null;return baseTrack('yandex',id,item.title,item.artists?.map(a=>a.name).join(', '),album?.title,yandexCover(item.coverUri||album?.coverUri),(Number(item.durationMs)||0)/1000,`https://music.yandex.ru/album/${album.id}/track/${id}`,{tags:[item.genre,album?.genre].filter(Boolean)});}
function offset(cursor){if(!cursor)return 0;if(!/^\d{1,5}$/.test(cursor)||Number(cursor)>maxTracks)fail(400,'INVALID_CURSOR','Неверная страница импорта.');return Number(cursor);}

export function createPublicImports(ctx,{fetcher=fetch,soundcloud,normalizeSoundcloud}={}){
  const cache=new Map(),pending=new Map(),snapshots=new Map(),snapshotJobs=new Map(),shutdown=new AbortController();let closed=false;
  async function cached(key,operation){
    const old=cache.get(key);
    if(old?.until>Date.now())return old.value;
    if(pending.has(key))return pending.get(key);
    if(closed||pending.size>=2)fail(503,'PUBLIC_IMPORT_BUSY','Публичный импорт занят. Попробуй чуть позже.');
    const signal=AbortSignal.any([AbortSignal.timeout(22000),shutdown.signal]);
    let onAbort;
    const aborted=new Promise((_,reject)=>{onAbort=()=>reject(new DOMException('Public source timeout','TimeoutError'));signal.addEventListener('abort',onAbort,{once:true});});
    const work=Promise.resolve().then(()=>operation(signal)).then(value=>{
      if(!closed&&!signal.aborted){cache.delete(key);cache.set(key,{value,until:Date.now()+120000});while(cache.size>64)cache.delete(cache.keys().next().value);}
      return value;
    });
    const task=Promise.race([work,aborted]).catch(error=>{
      if(error.name==='AbortError'||error.name==='TimeoutError'||error.code==='EXTRACTOR_TIMEOUT')fail(504,'PUBLIC_IMPORT_TIMEOUT','Площадка не ответила вовремя. Повтори поиск или открой отдельный плейлист.');
      throw error;
    }).finally(()=>signal.removeEventListener('abort',onAbort));
    pending.set(key,task);
    // Keep the resource slot until the underlying bounded fetch/process exits,
    // even if the HTTP deadline wins first. Repeated clients cannot spawn work.
    void work.finally(()=>{if(pending.get(key)===task)pending.delete(key);}).catch(()=>{});
    return task;
  }
  async function snapshot(key,read){const old=snapshots.get(key);if(old?.until>Date.now())return old.value;if(snapshotJobs.has(key))return snapshotJobs.get(key);const task=read().then(value=>{if(!closed){snapshots.delete(key);snapshots.set(key,{value,until:Date.now()+120000});while(snapshots.size>16)snapshots.delete(snapshots.keys().next().value);}return value;});snapshotJobs.set(key,task);try{return await task;}finally{snapshotJobs.delete(key);}}
  const spotify=(target,signal)=>snapshot('spotify:'+target.url,async()=>parseSpotifyPublic(await readPublic(target.kind==='playlist'?target.url.replace('/playlist/','/embed/playlist/'):target.url,{fetcher,signal}),target));
  const yandex=async(path,signal,body)=>{const data=json(await readPublic('https://api.music.yandex.net'+path,{fetcher,signal,...(body?{method:'POST',body:new URLSearchParams(body)}:{})}));if(data.error)fail(403,'PUBLIC_COLLECTION_UNAVAILABLE','Яндекс Музыка не открыла коллекцию.');return data.result;};
  async function youtube(target,start=0){if(!ctx.extractorPublicPlaylist)fail(503,'EXTRACTOR_UNAVAILABLE','Поиск YouTube пока недоступен.');try{return await ctx.extractorPublicPlaylist({url:target.url,start:start+1,limit:101});}catch(error){if(['EXTRACTOR_UPSTREAM','EXTRACTOR_FORMAT'].includes(error.code))fail(422,'PUBLIC_COLLECTION_UNAVAILABLE','YouTube не открыл публичный список. Проверь ссылку и доступность плейлиста.');throw error;}}
  async function search(provider,query){const target=publicImportTarget(provider,query);return cached('search:'+provider+':'+target.url,async signal=>{
    if(provider==='soundcloud')return soundcloud.collections(target.url,{signal});
    if(provider==='spotify'){const result=await spotify(target,signal);return target.kind==='playlist'?{playlists:[{...result.playlist,partial:result.partial}],partial:result.partial,warnings:result.warnings}:result;}
    if(provider==='yandex'){
      if(target.kind!=='profile'){const value=await snapshot('yandex:'+target.url,()=>target.kind==='likes'?yandex(`/users/${target.owner}/likes/tracks`,signal):yandex(`/users/${target.owner}/playlists/${target.id}`,signal));if(!value||(value.visibility==='private'||value.library?.visibility==='private'))fail(404,'PUBLIC_COLLECTION_UNAVAILABLE','Коллекция закрыта.');return {playlists:[collection(target.url,value.title||'Лайки',yandexCover(value.cover),value.trackCount??value.library?.tracks?.length??value.tracks?.length??0,{kind:target.kind})]};}
      const [lists,likes]=await Promise.allSettled([yandex(`/users/${target.owner}/playlists/list`,signal),yandex(`/users/${target.owner}/likes/tracks`,signal)]);if(lists.status==='rejected')throw lists.reason;
      if(!Array.isArray(lists.value))fail(502,'PUBLIC_IMPORT_FORMAT','Яндекс Музыка изменила список плейлистов.');
      const available=lists.value.filter(p=>p&&p.visibility!=='private'&&/^\d+$/.test(String(p.kind)));
      const result={playlists:available.slice(0,1000).map(p=>collection(`https://music.yandex.ru/users/${target.owner}/playlists/${p.kind}`,p.title,yandexCover(p.cover),p.trackCount))};
      if(likes.status==='fulfilled'&&likes.value?.visibility!=='private'&&likes.value?.library?.visibility!=='private'&&Array.isArray(likes.value?.library?.tracks||likes.value?.tracks))result.liked=collection(target.url+'/likes','Лайки','',(likes.value.library?.tracks||likes.value.tracks).length,{kind:'likes'});
      if(available.length>1000)Object.assign(result,{partial:true,warnings:['PUBLIC_COLLECTIONS_PARTIAL']});return result;
    }
    const value=await youtube(target);if(target.kind==='playlist')return {playlists:[collection(target.url,value.title,art(value.thumbnails),value.playlist_count??value.entries?.length??0)]};
    const playlists=[];for(const item of value.entries||[]){if(!item)continue;let link;try{link=publicImportTarget('youtube',item.webpage_url||item.url||`https://www.youtube.com/playlist?list=${item.id}`);}catch{continue;}if(link.kind==='playlist')playlists.push(collection(link.url,item.title,art(item.thumbnails),item.playlist_count||0));}return {playlists:playlists.slice(0,100),partial:(value.entries||[]).length>=101,warnings:(value.entries||[]).length>=101?['PUBLIC_COLLECTIONS_PARTIAL']:[]};
  });}
  async function tracks(provider,sourceUrl,cursor='',uid){const target=publicImportTarget(provider,sourceUrl);if(target.kind==='profile')fail(400,'PUBLIC_IMPORT_QUERY','Сначала выбери плейлист.');const result=await cached('tracks:'+provider+':'+target.url+':'+cursor,async signal=>{
    if(provider==='soundcloud'){const page=await soundcloud.collectionTracks(target.url,cursor,{signal});return {...page,tracks:page.tracks.map(normalizeSoundcloud).map(track=>({...track,playback:{kind:'soundcloud',offline:false}}))};}
    const start=offset(cursor);
    if(provider==='spotify'){const result=await spotify(target,signal);return {...result,tracks:result.tracks.slice(start,start+pageSize),nextCursor:start+pageSize<result.tracks.length?String(start+pageSize):null};}
    if(provider==='yandex'){
      const value=await snapshot('yandex:'+target.url,()=>target.kind==='likes'?yandex(`/users/${target.owner}/likes/tracks`,signal):yandex(`/users/${target.owner}/playlists/${target.id}`,signal));if(!value||(value.visibility==='private'||value.library?.visibility==='private'))fail(404,'PUBLIC_COLLECTION_UNAVAILABLE','Коллекция закрыта.');const all=value.library?.tracks||value.tracks;if(!Array.isArray(all))fail(502,'PUBLIC_IMPORT_FORMAT','Площадка не открыла песни.');if(all.length>maxTracks)fail(413,'IMPORT_TOO_LARGE','Максимум 10 000 треков за импорт.');const items=all.slice(start,start+pageSize),refs=items.filter(x=>x&&!x.track&&!x.title).map(x=>String(x.id)).filter(x=>/^\d+$/.test(x));const hydrated=refs.length?await yandex('/tracks',signal,{'track-ids':refs.join(',')}):[],byId=new Map((Array.isArray(hydrated)?hydrated:[]).map(x=>[String(x.id),x]));const normalized=items.map(x=>x?yandexTrack(x.track||x.title&&x||byId.get(String(x.id))||{}):null).filter(Boolean);return {tracks:normalized,total:all.length,nextCursor:start+pageSize<all.length?String(start+pageSize):null,partial:normalized.length<items.length,warnings:warnings(false,normalized.length<items.length)};
    }
    const value=await youtube(target,start),items=(value.entries||[]).slice(0,pageSize),normalized=items.filter(x=>x&&/^[\w-]{11}$/.test(x.id||'')&&x.title&&!/^\[?(?:private|deleted) video\]?$/i.test(x.title)&&!['Private video','Deleted video','private','premium_only','subscriber_only'].includes(x.title)&&!['private','premium_only','subscriber_only'].includes(x.availability)).map(x=>baseTrack('youtube',x.id,x.title,x.artist||x.uploader||x.channel,x.album,art(x.thumbnails)||`https://i.ytimg.com/vi/${x.id}/hqdefault.jpg`,x.duration,`https://www.youtube.com/watch?v=${x.id}`));return {tracks:normalized,total:value.playlist_count??start+items.length,nextCursor:(value.entries||[]).length>pageSize?String(start+pageSize):null,partial:normalized.length<items.length||Number(value.skipped_entries)>0||!(value.entries||[]).slice(pageSize).length&&Number(value.playlist_count)>start+items.length,warnings:warnings(false,normalized.length<items.length||Number(value.skipped_entries)>0||!(value.entries||[]).slice(pageSize).length&&Number(value.playlist_count)>start+items.length)};
  });
    const normalized=[...new Map(result.tracks.map(track=>[track.id,track])).values()],saved=[];for(let at=0;at<normalized.length;at+=8)saved.push(...(await Promise.all(normalized.slice(at,at+8).map(track=>ctx.persistTracks([track],{ownerId:uid})))).flat());return {...result,tracks:saved};
  }
  return {search,tracks,close(){closed=true;shutdown.abort();cache.clear();snapshots.clear();}};
}

export function setupPublicImports(app,ctx,service){
  const limiter=rateLimit({windowMs:60000,limit:30,standardHeaders:'draft-8',legacyHeaders:false});
  app.post('/api/public-import/search',ctx.requireAuth,limiter,asyncRoute(async(req,res)=>{const b=parse(z.object({provider:providers,query:text(2048)}).strict(),req.body);res.set('Cache-Control','private, no-store').json(await service.search(b.provider,b.query));}));
  app.post('/api/public-import/tracks',ctx.requireAuth,limiter,asyncRoute(async(req,res)=>{const b=parse(z.object({provider:providers,sourceUrl:text(2048),cursor:z.string().max(2048).optional()}).strict(),req.body);res.set('Cache-Control','private, no-store').json(await service.tracks(b.provider,b.sourceUrl,b.cursor,req.auth.user.id));}));
}
