import fsp from 'node:fs/promises';
import {systemText} from './system-text.js';
import {z} from 'zod';
import {id,now,digest,parse,text,fail,asyncRoute,publicUser,mergeSettings,keyboardSuggestion,parseLyrics} from './util.js';
import {sourceUrl,normalizeSpotify,normalizeYoutube,normalizeSoundcloud} from './providers.js';
import rateLimit from 'express-rate-limit';
import {matchedFields,artistsFromTracks,lyricsSignature} from './search.js';

export function parseCSV(raw){const rows=[],row=[];let field='',quoted=false;for(let i=0;i<raw.length;i++){const c=raw[i];if(c==='"'){if(quoted&&raw[i+1]==='"'){field+='"';i++;}else quoted=!quoted;}else if(c===','&&!quoted){row.push(field);field='';}else if((c==='\n'||c==='\r')&&!quoted){if(c==='\r'&&raw[i+1]==='\n')i++;row.push(field);if(row.some(x=>x))rows.push([...row]);row.length=0;field='';}else field+=c;}if(quoted)fail(400,'INVALID_CSV','В CSV не закрыты кавычки.');row.push(field);if(row.some(x=>x))rows.push(row);const [headers,...records]=rows;return records.map(values=>Object.fromEntries((headers||[]).map((h,i)=>[h.trim().toLowerCase().replace(/^\uFEFF/,''),values[i]||''])));}

export function setupLibrary(app,ctx){
  const {store,config,requireAuth}=ctx;
  const trackSchema=z.array(text(200)).max(10000);
  const color=z.string().regex(/^#[0-9a-f]{6}$/i).transform(value=>value.toLowerCase());
  const palette=z.object({bg:color.optional(),surface:color.optional(),ink:color.optional(),accent:color.optional()}).strict();
  const equalizer=z.object({enabled:z.boolean().optional(),preamp:z.number().finite().min(-12).max(12).optional(),bands:z.array(z.number().finite().min(-12).max(12)).length(10).optional()}).strict();
  const appearance=z.object({light:palette.optional(),dark:palette.optional(),amoled:palette.optional(),radius:z.number().int().min(8).max(38).optional(),speed:z.number().finite().min(.3).max(2).optional(),compact:z.boolean().optional(),blur:z.boolean().optional(),waveStyle:z.enum(['silk','particles','bloom']).optional(),cover3d:z.boolean().optional(),coverKind:z.enum(['vinyl','cd']).optional()}).strict();
  async function visibleTracks(user){return (await store.list('tracks',t=>t.public||t.uploadedBy===user?.id)).map(t=>ctx.publicTrack(t,user));}
  async function requireTrack(tid,user){const t=await store.get('tracks',tid);if(!await ctx.canAccessTrack(t,user))fail(404,'TRACK_NOT_FOUND','Трек не найден.');return t;}
  ctx.requireTrack=requireTrack;
  async function createPlaylist(uid,b){return ctx.withLock('playlist:'+uid,async()=>{const user=await store.get('users',uid),existing=await store.list('playlists',p=>p.ownerId===uid);if(existing.length>=(user.plan==='free'?25:1000))fail(403,'PLAN_LIMIT','Лимит плейлистов достигнут.');const ids=[...new Set(b.trackIds||[])];for(const tid of ids)await requireTrack(tid,user);const first=ids.length?await store.get('tracks',ids[0]):null;const p={id:id(),name:b.name,description:b.description||'',artwork:first?.artwork||'',trackIds:ids,ownerId:uid,createdAt:now(),updatedAt:now(),public:false};await store.create('playlists',p.id,p);return p;});}
  ctx.createPlaylist=createPlaylist;
  app.get('/api/tracks',asyncRoute(async(req,res)=>res.json({tracks:await visibleTracks(req.auth?.user)})));
  app.get('/api/search',asyncRoute(async(req,res)=>{
    const q=parse(text(200),req.query.q),source=parse(z.enum(['all','local','youtube','spotify','soundcloud','yandex']),req.query.source||'all'),lower=q.toLowerCase();
    const all=await visibleTracks(req.auth?.user);
    const savedLyrics=new Map((await store.entries('lyrics')).map(({id,value})=>[id,value]));
    const cachedLyrics=new Map((await store.list('lyricsCache')).filter(value=>value.expiresAt>Date.now()).map(value=>[value.id,value.lyrics]));
    const local=all.filter(t=>source==='all'||source===t.source).flatMap(track=>{
      const lyrics=(req.auth?.user&&savedLyrics.get(`${req.auth.user.id}:${track.id}`))||savedLyrics.get(track.id)||cachedLyrics.get(lyricsSignature(track));
      const fields=matchedFields(track,q,lyrics?.lines?.map(line=>line.text).join('\n'));
      return fields.length?[{...track,matchedFields:fields}]:[];
    });
    const providers=ctx.providerConfiguration(),requested=providers.filter(p=>(p.searchAvailable??p.configured)&&(source==='all'||p.id===source));
    const results=await Promise.allSettled(requested.map(p=>ctx.searchProvider(p.id,q,req.auth?.user.id))),tracks=[...local],errors=[];
    results.forEach((result,index)=>{if(result.status==='fulfilled')tracks.push(...result.value);else errors.push({provider:requested[index].id,message:result.reason.message});});
    const provider=providers.find(p=>p.id===source);
    if(source!=='all'&&source!=='local'&&!(provider?.searchAvailable??provider?.configured))errors.push({provider:source,message:`Поиск ${provider?.name||'этого источника'} сейчас недоступен. Можно добавить трек по ссылке.`});
    const exact=tracks.some(track=>`${track.title} ${track.artist} ${track.album}`.toLowerCase().includes(lower));
    const unique=new Map();
    for(const track of tracks){
      const identity=track.source!=='local'&&track.sourceUrl?`${track.source}:${track.sourceUrl.replace(/\/$/,'')}`:track.id;
      const previous=unique.get(identity),quality=value=>(value.duration>0?2:0)+(value.artwork?1:0)+(value.metadataOrigin==='import'?0:1);
      if(!previous||quality(track)>quality(previous))unique.set(identity,track);
    }
    const matches=[...unique.values()].sort((a,b)=>(b.matchedFields?.includes('title')?1:0)-(a.matchedFields?.includes('title')?1:0)).slice(0,100);
    const providerArtists=results.flatMap(result=>result.status==='fulfilled'?result.value.artists||[]:[]);
    res.set('Cache-Control','private, no-store').json({tracks:matches.map(track=>ctx.publicTrack(track,req.auth?.user)),artists:artistsFromTracks([...matches,...all],q,providerArtists).filter(artist=>source==='all'||source===artist.source),suggestion:exact||local.length?null:keyboardSuggestion(q),providers,errors});
  }));
  app.post('/api/tracks/resolve',requireAuth,asyncRoute(async(req,res)=>{const b=parse(z.object({url:z.url().max(2048)}).strict(),req.body);res.json({track:ctx.publicTrack(await ctx.resolveSource(b.url))});}));
  app.get('/api/tracks/:id',asyncRoute(async(req,res)=>res.json({track:ctx.publicTrack(await requireTrack(req.params.id,req.auth?.user),req.auth?.user)})));
  app.get('/api/library',requireAuth,asyncRoute(async(req,res)=>{const uid=req.auth.user.id,entry=await store.get('libraries',uid)||{likedIds:[],history:[]},playlists=await store.list('playlists',p=>p.ownerId===uid);const ids=new Set([...entry.likedIds,...entry.history.map(h=>h.trackId),...playlists.flatMap(p=>p.trackIds)]);const tracks=await store.list('tracks',t=>t.uploadedBy===uid||ids.has(t.id));const accessible=[];for(const t of tracks)if(await ctx.canAccessTrack(t,req.auth.user))accessible.push(ctx.publicTrack(t,req.auth.user));res.json({tracks:accessible,likedIds:entry.likedIds.filter(t=>accessible.some(x=>x.id===t)),playlists,history:entry.history});}));
  app.put('/api/library/likes/:trackId',requireAuth,asyncRoute(async(req,res)=>{const b=parse(z.object({liked:z.boolean()}).strict(),req.body);await requireTrack(req.params.trackId,req.auth.user);await store.update('libraries',req.auth.user.id,v=>{v=v||{id:req.auth.user.id,likedIds:[],history:[]};const set=new Set(v.likedIds);b.liked?set.add(req.params.trackId):set.delete(req.params.trackId);return {...v,likedIds:[...set]};});res.json({ok:true,liked:b.liked});}));
  app.post('/api/history',requireAuth,asyncRoute(async(req,res)=>{const b=parse(z.object({trackId:text(200),position:z.number().finite().min(0).max(86400).optional()}).strict(),req.body);await requireTrack(b.trackId,req.auth.user);await store.update('libraries',req.auth.user.id,v=>{v=v||{id:req.auth.user.id,likedIds:[],history:[]};return {...v,history:[{trackId:b.trackId,position:b.position||0,playedAt:now()},...v.history.filter(h=>h.trackId!==b.trackId)].slice(0,100)};});res.json({ok:true});}));
  app.get('/api/playlists',requireAuth,asyncRoute(async(req,res)=>res.json({playlists:await store.list('playlists',p=>p.ownerId===req.auth.user.id)})));
  app.post('/api/playlists',requireAuth,asyncRoute(async(req,res)=>{const b=parse(z.object({name:text(120),description:z.string().max(1000).optional(),trackIds:trackSchema.optional()}).strict(),req.body);res.status(201).json({playlist:await createPlaylist(req.auth.user.id,b)});}));
  app.patch('/api/playlists/:id',requireAuth,asyncRoute(async(req,res)=>{const b=parse(z.object({name:text(120).optional(),description:z.string().max(1000).optional(),trackIds:trackSchema.optional()}).strict(),req.body);if(b.trackIds)for(const tid of b.trackIds)await requireTrack(tid,req.auth.user);const p=await store.update('playlists',req.params.id,v=>{if(!v||v.ownerId!==req.auth.user.id)fail(404,'PLAYLIST_NOT_FOUND','Плейлист не найден.');return {...v,...b,...(b.trackIds?{trackIds:[...new Set(b.trackIds)]}:{}),updatedAt:now()};});res.json({playlist:p});}));
  app.delete('/api/playlists/:id',requireAuth,asyncRoute(async(req,res)=>{const p=await store.get('playlists',req.params.id);if(!p||p.ownerId!==req.auth.user.id)fail(404,'PLAYLIST_NOT_FOUND','Плейлист не найден.');await store.remove('playlists',p.id);res.json({ok:true});}));
  app.get('/api/settings',requireAuth,asyncRoute(async(req,res)=>res.json({settings:mergeSettings(await store.get('settings',req.auth.user.id)||{})})));
  app.patch('/api/settings',requireAuth,asyncRoute(async(req,res)=>{
    const expectedAccount=req.headers['x-glukwave-account'];
    if(expectedAccount!==undefined&&expectedAccount!==req.auth.user.id)fail(409,'SESSION_CHANGED','Аккаунт изменился. Открой настройки снова.');
    const b=parse(z.object({autoCache:z.boolean().optional(),cacheLimitMB:z.number().int().min(128).max(req.auth.user.plan==='free'?2048:32768).optional(),lyrics:z.boolean().optional(),discordPresence:z.boolean().optional(),notifications:z.boolean().optional(),language:z.enum(['auto','en','ru','kk','uk','de','es']).optional(),theme:z.enum(['light','dark','amoled','system']).optional(),reducedMotion:z.boolean().optional(),appearance:appearance.optional(),equalizer:equalizer.optional(),playbackRate:z.number().finite().min(.5).max(2).optional()}).strict(),req.body);
    // Serialize persistence and its notification together so devices receive revisions in order.
    const settings=await ctx.withLock('settings:'+req.auth.user.id,async()=>{
      const saved=await store.update('settings',req.auth.user.id,v=>({...mergeSettings(v||{},b),revision:(Number.isSafeInteger(v?.revision)?v.revision:0)+1}));
      ctx.io?.to(`user:${req.auth.user.id}`).emit('settings:changed',{settings:saved,revision:saved.revision});
      return saved;
    });
    res.json({settings});
  }));
  app.get('/api/profile/:id',asyncRoute(async(req,res)=>{const u=await store.get('users',req.params.id);if(!u||u.blocked)fail(404,'PROFILE_NOT_FOUND','Профиль не найден.');const {email,emailVerified,role,...user}=publicUser(u);res.json({user,playlists:await store.list('playlists',p=>p.ownerId===u.id&&p.public)});}));
  app.patch('/api/profile',requireAuth,asyncRoute(async(req,res)=>{const b=parse(z.object({displayName:text(60).optional(),username:z.string().regex(/^[a-zA-Z0-9_]{3,24}$/).transform(x=>x.toLowerCase()).optional(),bio:z.string().max(500).optional(),tags:z.array(text(24)).max(6).optional()}).strict(),req.body);try{const user=await store.update('users',req.auth.user.id,u=>({...u,...b}));res.json({user:publicUser(user)});}catch(err){if(err.code===11000||String(err.message).includes('UNIQUE'))fail(409,'USERNAME_TAKEN','Имя пользователя уже занято.');throw err;}}));
  app.get('/api/tracks/:id/comments',asyncRoute(async(req,res)=>{await requireTrack(req.params.id,req.auth?.user);const comments=await store.list('comments',c=>c.trackId===req.params.id);res.json({comments:comments.sort((a,b)=>a.createdAt.localeCompare(b.createdAt)).slice(-500)});}));
  app.post('/api/tracks/:id/comments',requireAuth,asyncRoute(ctx.quotaRoute('comment',async(req,res)=>{const t=await requireTrack(req.params.id,req.auth.user),b=parse(z.object({text:text(1000),position:z.number().finite().min(0).max(t.duration||86400).optional()}).strict(),req.body);const recent=await store.list('comments',c=>c.userId===req.auth.user.id&&Date.now()-Date.parse(c.createdAt)<60000);if(recent.length>=10)fail(429,'COMMENT_LIMIT','Подожди минуту перед новым комментарием.');const c={id:id(),trackId:t.id,userId:req.auth.user.id,displayName:req.auth.user.displayName,avatarUrl:req.auth.user.avatarUrl,text:b.text,position:b.position||0,createdAt:now()};await store.create('comments',c.id,c);res.status(201).json({comment:c});})));
  app.delete('/api/comments/:id',requireAuth,asyncRoute(async(req,res)=>{const c=await store.get('comments',req.params.id);if(!c||c.userId!==req.auth.user.id&&req.auth.user.role!=='admin')fail(404,'COMMENT_NOT_FOUND','Комментарий не найден.');await store.remove('comments',c.id);res.json({ok:true});}));
  const lyricsLimiter=rateLimit({windowMs:60000,limit:20,standardHeaders:'draft-8',legacyHeaders:false});
  app.get('/api/tracks/:id/lyrics',lyricsLimiter,asyncRoute(async(req,res)=>{
    const track=await requireTrack(req.params.id,req.auth?.user);
    const personal=req.auth?.user?await store.get('lyrics',`${req.auth.user.id}:${req.params.id}`):null;
    res.set('Cache-Control','private, no-store').json(personal||await store.get('lyrics',req.params.id)||await ctx.lyricsProvider.lookup(track));
  }));
  app.get('/api/tracks/:id/lyrics/search',lyricsLimiter,asyncRoute(async(req,res)=>{
    const track=await requireTrack(req.params.id,req.auth?.user),query=parse(z.object({title:text(200).optional(),artist:text(200).optional()}).strict(),req.query);
    const candidates=await ctx.lyricsProvider.search(query.title||track.title,query.artist||track.artist);
    res.set('Cache-Control','private, no-store').json({candidates});
  }));
  app.post('/api/tracks/:id/lyrics/lrclib',requireAuth,lyricsLimiter,asyncRoute(async(req,res)=>{
    const track=await requireTrack(req.params.id,req.auth.user);
    if(track.source==='local'&&track.uploadedBy!==req.auth.user.id&&req.auth.user.role!=='admin')fail(403,'OWNER_REQUIRED','Текст может добавить автор загрузки.');
    const body=parse(z.object({providerId:z.number().int().positive().max(2147483647)}).strict(),req.body),lyrics=await ctx.lyricsProvider.byId(body.providerId);
    if(!lyrics||!lyrics.lines.length&&!lyrics.instrumental)fail(404,'LYRICS_NOT_FOUND','Текст не найден.');
    const key=track.source==='local'?track.id:`${req.auth.user.id}:${track.id}`;
    await store.put('lyrics',key,lyrics);res.json(lyrics);
  }));
  app.put('/api/tracks/:id/lyrics',requireAuth,asyncRoute(async(req,res)=>{
    const t=await requireTrack(req.params.id,req.auth.user);
    if(t.source==='local'&&t.uploadedBy!==req.auth.user.id&&req.auth.user.role!=='admin')fail(403,'OWNER_REQUIRED','Текст может добавить автор загрузки.');
    const b=parse(z.object({text:z.string().max(100000)}).strict(),req.body),lyrics=parseLyrics(b.text);
    if(!lyrics.lines.length)fail(400,'LYRICS_EMPTY','Добавь хотя бы одну строку текста.');
    const key=t.source==='local'?t.id:`${req.auth.user.id}:${t.id}`;
    await store.put('lyrics',key,lyrics);res.json(lyrics);
  }));
  app.post('/api/integrations/import-file',requireAuth,ctx.importUpload.single('file'),asyncRoute(async(req,res)=>{
    if(!req.file)fail(400,'FILE_REQUIRED','Выбери CSV или JSON.');
    try{
      const raw=await fsp.readFile(req.file.path,'utf8');let rows;
      if(req.file.originalname.toLowerCase().endsWith('.json')){
        let json;try{json=JSON.parse(raw);}catch{fail(400,'IMPORT_FORMAT','Не удалось прочитать JSON. Проверь формат файла.');}
        rows=Array.isArray(json)?json:json?.tracks;
        if(!Array.isArray(rows))fail(400,'IMPORT_FORMAT','JSON должен содержать массив tracks.');
      }else rows=parseCSV(raw);
      if(rows.length>10000)fail(413,'IMPORT_TOO_LARGE','Максимум 10 000 треков за импорт.');
      const imported=[],errors=[];
      for(const [i,row] of rows.entries()){
        try{
          if(!row||typeof row!=='object'||Array.isArray(row))fail(400,'IMPORT_ROW','Строка должна содержать данные трека.');
          const r=Object.fromEntries(Object.entries(row).map(([k,v])=>[k.toLowerCase(),v]));
          let url=r.sourceurl||r.url||r.link||r['track url']||r['track uri']||r.uri||'';
          if(typeof url!=='string'||url.length>2048)fail(400,'IMPORT_URL','Нужна корректная ссылка на трек.');
          if(url.startsWith('spotify:track:'))url='https://open.spotify.com/track/'+url.split(':').at(-1);
          const titleValue=r.title||r.name||r['track name']||'',artist=r.artist||r['artist name(s)']||r['artist name']||'',album=r.album||r['album name']||'';
          if(typeof titleValue!=='string'||!titleValue.trim()||titleValue.length>200)fail(400,'IMPORT_TITLE','Нет корректного названия трека.');
          if(typeof artist!=='string'||artist.length>200||typeof album!=='string'||album.length>200)fail(400,'IMPORT_METADATA','Исполнитель и альбом должны быть текстом до 200 символов.');
          const source=sourceUrl(url);let track;
          const ms=Number(r.duration_ms),durationMs=Number.isFinite(ms)&&ms>0&&ms<=86400000?ms:0;
          if(source.source==='spotify')track=normalizeSpotify({id:source.sourceId,name:titleValue,artists:[{name:artist}],album:{name:album,images:[]},duration_ms:durationMs});
          if(source.source==='youtube')track=normalizeYoutube({id:source.sourceId,snippet:{title:titleValue,channelTitle:artist,thumbnails:{}}});
          if(source.source==='soundcloud')track=normalizeSoundcloud({urn:source.sourceId,title:titleValue,user:{username:artist},permalink_url:source.url});
          if(source.source==='yandex')track=await ctx.resolveSource(url,{title:titleValue,artist,album},{persist:false});
          if(track){
            const verified=await store.get('tracks',track.id);
            if(verified?.public){imported.push(verified.id);continue;}
            // User exports must never overwrite shared provider metadata.
            track={...track,id:`import-${req.auth.user.id}-${digest(source.source+':'+source.sourceId).slice(0,24)}`,public:false,uploadedBy:req.auth.user.id,metadataOrigin:'import'};
            await ctx.persistTracks([track]);imported.push(track.id);
          }
        }catch(err){errors.push({row:i+2,message:err.message});}
      }
      if(!imported.length)fail(422,'EMPTY_IMPORT','В файле не найдено треков со ссылками площадок.',errors.slice(0,20));
      const name=req.body.name?parse(text(120),req.body.name):req.file.originalname.replace(/\.(csv|json)$/i,'');
      const playlist=await createPlaylist(req.auth.user.id,{name:name.trim().slice(0,120)||systemText('importedMusic',req.language),trackIds:[...new Set(imported)]});
      res.status(201).json({playlist,imported:playlist.trackIds.length,errors});
    }finally{await fsp.unlink(req.file.path).catch(()=>{});}
  }));
}
