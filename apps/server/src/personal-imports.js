import {z} from 'zod';
import {asyncRoute,fail,parse,seal,unseal,now} from './util.js';
import {planLimits} from './plans.js';
import {systemText} from './system-text.js';

// Personal credentials never enter public-import caches, audit payloads or URLs.
export function createPersonalImports(app,ctx,{normalizeSpotify,persist,fetcher=fetch}){
  const {store,config}=ctx,active=new Map();
  const tokenSchema=z.object({accessToken:z.string().trim().min(16).max(8192).regex(/^[^\s\x00-\x1f]+$/)}).strict();
  const requirePlan=user=>{if(!planLimits(user).libraryImport)fail(403,'PLAN_LIMIT','Импорт доступен в Beta и Unbound.');};
  async function request(provider,route,access,{method='GET',body}={}){
    const base=provider==='spotify'?'https://api.spotify.com/v1/':'https://api.music.yandex.net/';
    const url=new URL(route,base),allowed=new URL(base);
    if(url.origin!==allowed.origin||!url.pathname.startsWith(allowed.pathname)||url.username||url.password)fail(400,'INVALID_CURSOR','Неверная страница коллекции.');
    let response;
    try{response=await fetcher(url,{method,body:body?new URLSearchParams(body):undefined,redirect:'error',signal:AbortSignal.timeout(8000),headers:{Authorization:`${provider==='spotify'?'Bearer':'OAuth'} ${access}`,Accept:'application/json',...(body?{'Content-Type':'application/x-www-form-urlencoded'}:{})}});}catch{fail(504,'IMPORT_TIMEOUT','Площадка не ответила вовремя. Попробуй снова.');}
    if(!response.ok){await response.body?.cancel();fail(response.status===401?401:response.status===403?403:response.status===429?429:502,response.status===401?'PROVIDER_TOKEN_EXPIRED':response.status===403?'PROVIDER_SCOPE_REQUIRED':'PROVIDER_UNAVAILABLE',response.status===401?'Токен площадки истёк. Подключи её снова.':response.status===403?'Токену не хватает доступа к личной библиотеке.':'Площадка временно недоступна. Попробуй позже.');}
    const reader=response.body?.getReader();if(!reader)fail(502,'PROVIDER_UNAVAILABLE','Пустой ответ площадки.');
    const chunks=[];let bytes=0;try{for(;;){const {done,value}=await reader.read();if(done)break;bytes+=value.length;if(bytes>4*1024*1024)fail(413,'IMPORT_TOO_LARGE','Ответ площадки слишком большой.');chunks.push(Buffer.from(value));}}catch(error){if(error.status)throw error;fail(504,'IMPORT_TIMEOUT','Площадка не ответила вовремя.');}finally{await reader.cancel().catch(()=>{});}
    let data;try{data=JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{fail(502,'PROVIDER_UNAVAILABLE','Площадка вернула непонятный ответ.');}
    if(data.error)fail(403,'PROVIDER_SCOPE_REQUIRED','Площадка не открыла личную библиотеку.');return provider==='yandex'?data.result:data;
  }
  async function credential(provider,uid){
    const record=await store.get('connections',`${uid}:${provider}`);if(!record)fail(409,'CONNECT_REQUIRED','Подключи личный аккаунт площадки.');
    let value;try{value=unseal(record.token,config.encryptionKey);}catch{fail(409,'RECONNECT_REQUIRED','Подключи площадку снова.');}
    if(!value.access_token||value.expiresAt<=Date.now())fail(409,'RECONNECT_REQUIRED','Доступ площадки истёк. Вставь новый токен.');return {record,access:value.access_token};
  }
  async function bounded(uid,work){
    if((active.get(uid)||0)>=1||active.size>=8&&!active.has(uid))fail(429,'IMPORT_BUSY','Проверка площадки уже выполняется.');
    active.set(uid,1);try{return await work();}finally{active.delete(uid);}
  }
  const clean=value=>String(value||'').replace(/[\x00-\x1f]/g,'').slice(0,300);
  const image=value=>{const url=String(value||'').replace(/%%/g,'400x400');try{const u=new URL(url.startsWith('https:')?url:'https://'+url);return u.protocol==='https:'&&!u.username&&!u.password?u.href:'';}catch{return '';}};
  function yandexTrack(track){
    const id=String(track?.id||''),album=track?.albums?.[0];
    if(!/^\d+$/.test(id)||!track.title||!/^\d+$/.test(String(album?.id||''))||track.available===false)return null;
    return {id:`yandex-${id}`,sourceId:id,source:'yandex',title:clean(track.title),artist:clean((track.artists||[]).map(a=>a.name).join(', ')),
      album:clean(album.title),artwork:image(track.coverUri||album.coverUri),duration:Math.max(0,Math.min(86400,Number(track.durationMs||0)/1000)),
      sourceUrl:`https://music.yandex.ru/album/${album.id}/track/${id}`,tags:[album.genre].filter(Boolean),public:false,createdAt:now(),playback:{kind:'yandex',offline:false}};
  }
  async function connect(provider,req,res){
    if(req.headers['x-glukwave-account']&&req.headers['x-glukwave-account']!==req.auth.user.id)fail(409,'ACCOUNT_CHANGED','Аккаунт изменился. Повтори подключение.');
    requirePlan(req.auth.user);const {accessToken}=parse(tokenSchema,req.body),uid=req.auth.user.id;
    const result=await bounded(uid,async()=>{
      const info=await request(provider,provider==='spotify'?'me':'account/status',accessToken);
      const account=provider==='spotify'?info:info.account;
      const identity=String(provider==='spotify'?account?.id:account?.uid||'');
      if(!identity||identity.length>150||!account)fail(502,'PROVIDER_IDENTITY','Площадка не подтвердила аккаунт.');
      // Prove both required read capabilities before replacing a good connection.
      const [likes,lists]=await Promise.all(provider==='spotify'?
        [request(provider,'me/tracks?limit=1',accessToken),request(provider,'me/playlists?limit=1',accessToken)]:
        [request(provider,`users/${encodeURIComponent(identity)}/likes/tracks`,accessToken),request(provider,`users/${encodeURIComponent(identity)}/playlists/list`,accessToken)]);
      const record={id:`${uid}:${provider}`,provider,userId:uid,providerUserId:identity,manual:true,
        displayName:clean(account.display_name||account.displayName||account.login||identity),
        token:seal({access_token:accessToken,expiresAt:Date.now()+(provider==='spotify'?3600000:30*86400000)},config.encryptionKey),updatedAt:now()};
      const [session,user]=await Promise.all([store.get('sessions',req.auth.session.id),store.get('users',uid)]);
      if(!session||session.expiresAt<=Date.now()||!user||user.blocked)fail(401,'AUTH_REQUIRED','Сессия завершена.');
      requirePlan(user);
      await store.put('connections',record.id,record);
      ctx.io?.to(`user:${uid}`).emit('integrations:changed',{});
      await ctx.audit('integration.connect',uid,{provider,method:'personal-token'});
      return {provider,connected:true,displayName:record.displayName,importAvailable:true,manual:true,
        discoveredTracks:provider==='spotify'?Number(likes.total)||0:likes.library?.tracks?.length||0,
        discoveredPlaylists:provider==='spotify'?Number(lists.total)||0:Array.isArray(lists)?lists.length:0};
    });
    res.set('Cache-Control','private, no-store').json({connection:result});
  }
  app.post('/api/public-import/spotify/token',ctx.requireAuth,asyncRoute((req,res)=>connect('spotify',req,res)));
  app.post('/api/integrations/spotify/token',ctx.requireAuth,asyncRoute((req,res)=>connect('spotify',req,res)));
  app.post('/api/integrations/yandex/token',ctx.requireAuth,asyncRoute((req,res)=>connect('yandex',req,res)));
  async function yandexPlaylists(uid,language){
    const {record,access}=await credential('yandex',uid),owner=encodeURIComponent(record.providerUserId);
    const [lists,liked]=await Promise.all([request('yandex',`users/${owner}/playlists/list`,access),request('yandex',`users/${owner}/likes/tracks`,access)]);
    return {playlists:(Array.isArray(lists)?lists:[]).slice(0,1000).filter(x=>/^\d+$/.test(String(x.kind))).map(x=>({id:String(x.kind),name:clean(x.title),artwork:image(x.cover?.uri||x.cover?.itemsUri?.[0]),trackCount:Number(x.trackCount)||0})),
      liked:{id:'liked',name:systemText('likedTracks',language),trackCount:liked.library?.tracks?.length||0}};
  }
  async function yandexTracks(uid,pid,cursor){
    if(pid!=='liked'&&!/^\d{1,20}$/.test(pid)||cursor&&!/^\d{1,5}$/.test(cursor))fail(400,'INVALID_CURSOR','Неверная страница.');
    const offset=Number(cursor)||0;if(offset>10000)fail(413,'IMPORT_TOO_LARGE','Слишком много треков.');
    const {record,access}=await credential('yandex',uid),owner=encodeURIComponent(record.providerUserId);
    const data=await request('yandex',pid==='liked'?`users/${owner}/likes/tracks`:`users/${owner}/playlists/${pid}`,access);
    const all=pid==='liked'?data.library?.tracks||[]:data.tracks||[],page=all.slice(offset,offset+50);
    const missing=page.filter(x=>!x.track?.title&&!x.title).map(x=>String(x.id)+(x.albumId?':'+x.albumId:''));
    if(missing.some(x=>!/^\d+(?::\d+)?$/.test(x)))fail(502,'PROVIDER_UNAVAILABLE','Площадка вернула неизвестный трек.');
    const resolved=missing.length?await request('yandex','tracks',access,{method:'POST',body:{'track-ids':missing.join(',')}}):[];
    const byId=new Map((Array.isArray(resolved)?resolved:[]).map(x=>[String(x.id),x]));
    const raw=page.map(x=>x.track||x.title&&x||byId.get(String(x.id))).map(yandexTrack).filter(Boolean);
    return {tracks:await persist(raw,{ownerId:uid}),nextCursor:offset+50<all.length?String(offset+50):null,
      partial:raw.length<page.length,warnings:raw.length<page.length?['SOURCE_TRACKS_UNAVAILABLE']:[]};
  }
  // The system token is deliberately only used for global/public catalog calls.
  ctx.yandexCatalogCall=route=>config.yandexToken?request('yandex',route,config.yandexToken):Promise.reject(Object.assign(new Error('Yandex catalog unavailable'),{code:'PROVIDER_NOT_CONFIGURED',status:503}));
  return {yandexPlaylists,yandexTracks,request,credential,yandexTrack};
}
