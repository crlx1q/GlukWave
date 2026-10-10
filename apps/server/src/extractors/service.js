import fs from 'node:fs/promises';
import path from 'node:path';
import {Readable,Transform} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import {spawn} from 'node:child_process';
import ffmpeg from 'ffmpeg-static';
import {z} from 'zod';
import rateLimit from 'express-rate-limit';
import {asyncRoute,digest,fail,now,parse,text} from '../util.js';
import {sourceUrl} from '../providers.js';
import {createExtractorRuntime} from './runtime.js';
import {soundcloudAdapter} from './soundcloud.js';
import {youtubeAdapter} from './youtube.js';
import {spotifyAdapter} from './spotify.js';
import {audioMatch} from './matching.js';
import {setupExtractedHls} from './hls.js';

// A playable URL is never itself a license. Only verified source licenses or an
// administrator's recorded, track-specific permission enable native delivery.
export function licensePermission(value){
  const license=String(value||'').toLowerCase().trim();
  const open=/^https?:\/\/creativecommons\.org\/(?:licenses\/by(?:-sa)?\/[1-4]\.0|publicdomain\/zero\/1\.0)\/?$/i.test(license)||['cc0','cc-by','cc-by-sa','creative commons attribution license (reuse allowed)'].includes(license);
  return open?{stream:true,download:true,convert:true,basis:'source-license',evidence:license}:null;
}
export function safeCdn(value,kind='audio'){
  let url;try{url=new URL(value);}catch{return null;}
  if(url.protocol!=='https:'||url.username||url.password||url.port)return null;
  const domains=kind==='cover'?['sndcdn.com','ytimg.com','ggpht.com','googleusercontent.com','scdn.co']:['sndcdn.com','soundcloud.com','soundcloud.cloud','googlevideo.com'];
  if(!domains.some(domain=>url.hostname===domain||url.hostname.endsWith('.'+domain)))return null;
  if(kind==='audio'&&/\.m3u8(?:$|\?)/i.test(url.pathname+url.search))return null;
  return url;
}
export function createBoundedCache(limit=200){
  const values=new Map();return {get(key){const value=values.get(key);if(!value||value.expiresAt<=Date.now()){values.delete(key);return null;}values.delete(key);values.set(key,value);return value.data;},set(key,data,ttl){values.delete(key);values.set(key,{data,expiresAt:Date.now()+ttl});while(values.size>limit)values.delete(values.keys().next().value);},delete:key=>values.delete(key),clear:()=>values.clear(),size:()=>values.size};
}
export function setupExtractors(app,ctx,overrides={}){
  const {store,config,requireAuth,requireAdmin}=ctx,runtime=createExtractorRuntime(config,{run:overrides.run}),metadata=createBoundedCache(200),pending=new Map(),fetcher=overrides.fetch||fetch;
  const adapters={soundcloud:soundcloudAdapter(runtime),youtube:youtubeAdapter(runtime),spotify:spotifyAdapter(runtime,config)};
  let streams=0,conversion=false,versions=null,versionsAt=0;const transfers=new Set();
  const directory=path.join(config.dataDir,'extractor-covers');
  const limiter=rateLimit({windowMs:60000,limit:24,standardHeaders:'draft-8',legacyHeaders:false});
  async function cached(key,operation,ttl=300000){const value=metadata.get(key);if(value)return value;if(pending.has(key))return pending.get(key);if(pending.size>=16)fail(503,'EXTRACTOR_BUSY','Музыка загружается. Повтори чуть позже.');const task=operation().then(result=>{metadata.set(key,result,ttl);return result;});pending.set(key,task);try{return await task;}finally{pending.delete(key);}}
  async function details(source,url){const canonical=sourceUrl(url);if(canonical.source!==source||!adapters[source])fail(400,'UNSUPPORTED_URL','Этот источник недоступен.');return cached('metadata:'+canonical.url,()=>adapters[source].metadata(canonical.url),240000);}
  async function rightFor(track){
    const record=await store.get('audioPermissions',track.id);
    if(record?.expiresAt&&record.expiresAt<=Date.now())return null;
    if(record)return record;
    if(config.extractors?.permissive&&config.env!=='test')return {stream:true,download:true,convert:true,basis:'direct-audio',evidence:'permissive'};
    // Creator-enabled personal downloads do not by themselves license a music
    // service to relay or redistribute the track. Keep that flag as metadata.
    return licensePermission(track.sourcePermission?.license);
  }
  async function candidateAudio(track,{force=false}={}){
    if(!(track.duration>0)||!track.artist)return null;
    const target={...track,artist:track.artist.replace(/\s*-\s*Topic$/i,'')};
    const found=await cached('audio-candidates:'+track.id,async()=>{
      if(track.source==='spotify'&&runtime.available('spotify')){
        try{const result=await adapters.spotify.matches(target);if(result.candidates?.some(candidate=>candidate.match.accepted))return result.candidates;}catch{/* Independent YouTube Music metadata fallback. */}
      }
      return adapters.youtube.search(target.artist+' '+target.title);
    },240000);
    const candidates=found.filter(candidate=>audioMatch(target,candidate).accepted).slice(0,3);
    for(const candidate of candidates){
      try{const identity=sourceUrl(candidate.source_url);if(!runtime.available(identity.source))continue;if(force)metadata.delete('metadata:'+identity.url);
        const info=await details(identity.source,identity.url),permission=await rightFor(track)||licensePermission(info.license);
        const credit={...info,artist:String(info.artist||'').replace(/\s*-\s*Topic$/i,'')};
        if(permission?.stream&&audioMatch(target,credit).accepted&&safeCdn(info.audio_url,'hls'))return {info,permission};
      }catch{/* A broken candidate must not block another exact licensed match. */}
    }
    return null;
  }
  async function resolved(track,{force=false}={}){
    const rights=await rightFor(track),url=rights?.audioSourceUrl||track.sourceUrl;
    if(rights&&rights.stream===false)return null;
    if(!['soundcloud','youtube','spotify','yandex'].includes(track.source))return null;
    if(['spotify','yandex'].includes(track.source)&&!rights?.audioSourceUrl)return candidateAudio(track,{force});
    const identity=sourceUrl(url);if(!['soundcloud','youtube'].includes(identity.source))return null;
    if(!runtime.available(identity.source)){if(rights?.stream)fail(503,'EXTRACTOR_UNAVAILABLE','Трек временно недоступен. Повтори позже.');return null;}
    if(force)metadata.delete('metadata:'+identity.url);
    const info=await details(identity.source,identity.url),permission=await rightFor(track)||licensePermission(info.license);
    if(!permission?.stream)return null;
    if(track.source==='spotify'&&!audioMatch(track,info).accepted)fail(409,'AUDIO_MATCH_REJECTED','Не найдено точное совпадение этого трека.');
    if(!safeCdn(info.audio_url,'hls'))fail(502,'AUDIO_FORMAT_UNAVAILABLE','Этот формат пока недоступен в плеере.');
    return {info,permission};
  }
  ctx.extractorAvailable=source=>!!adapters[source]&&runtime.available(source);
  ctx.extractorExpected=async track=>!!(await rightFor(track))?.stream;
  const hls=setupExtractedHls(app,ctx,{cdn:value=>safeCdn(value,'hls'),resolve:resolved,fetcher});
  ctx.extractorStats=()=>({...runtime.stats(),streams,metadataEntries:metadata.size(),pending:pending.size,conversion,hls:hls.stats()});
  ctx.extractorMetadata=async(source,url)=>details(source,url);
  ctx.extractorSearch=async query=>cached('music-search:'+query.normalize('NFC').toLowerCase(),()=>adapters.youtube.search(query));
  ctx.extractorPlayback=async(track,user,sessionId)=>{
    const result=await resolved(track);if(!result)return null;
    if(/m3u8/i.test(result.info.protocol||'')||/\.m3u8(?:\?|$)/i.test(result.info.audio_url))return hls.issue(track,result,user,sessionId);
    return {kind:'audio',url:`/api/external-audio/${encodeURIComponent(track.id)}`,offline:!!result.permission.download,...(result.permission.download?{downloadUrl:`/api/external-audio/${encodeURIComponent(track.id)}/download`}:{}),audioSource:result.info.source,license:result.permission.basis,attribution:{source:result.info.source,artist:result.info.artist||track.artist,sourceUrl:result.info.source_url||track.sourceUrl}};
  };
  async function pull(url,options={}){
    let current=safeCdn(url,options.kind||'audio');if(!current)fail(502,'EXTRACTOR_URL','Источник не открыл аудио.');
    for(let redirects=0;redirects<=3;redirects++){
      const response=await fetcher(current,{redirect:'manual',signal:options.signal||AbortSignal.timeout(15000),headers:options.headers});
      if([301,302,303,307,308].includes(response.status)){await response.body?.cancel();current=safeCdn(new URL(response.headers.get('location')||'',current).href,options.kind||'audio');if(!current)fail(502,'EXTRACTOR_URL','Источник не открыл аудио.');continue;}return response;
    }fail(502,'EXTRACTOR_URL','Источник не открыл аудио.');
  }
  async function coverFile(track){
    if(!safeCdn(track.artwork,'cover'))fail(404,'IMAGE_NOT_FOUND','Обложка не найдена.');
    const key=digest(track.artwork),location=path.join(directory,key+'.image'),meta=location+'.json';
    try{const info=JSON.parse(await fs.readFile(meta,'utf8'));if(info.expiresAt>Date.now()){await fs.access(location);return {location,...info};}}catch{}
    return cached('cover:'+key,async()=>{
      const response=await pull(track.artwork,{kind:'cover'});if(!response.ok){await response.body?.cancel();fail(502,'IMAGE_NOT_FOUND','Обложка временно недоступна.');}
      const type=response.headers.get('content-type')?.split(';')[0];if(!['image/jpeg','image/png','image/webp','image/avif'].includes(type)){await response.body?.cancel();fail(502,'IMAGE_FORMAT','Обложка временно недоступна.');}
      const chunks=[];let size=0;try{for await(const chunk of response.body){size+=chunk.length;if(size>5*1024*1024)fail(413,'IMAGE_FORMAT','Обложка слишком большая.');chunks.push(Buffer.from(chunk));}}finally{await response.body?.cancel().catch(()=>{});}
      await fs.mkdir(directory,{recursive:true});const partial=location+'.partial';await fs.writeFile(partial,Buffer.concat(chunks));await fs.rename(partial,location);
      const info={type,size,expiresAt:Date.now()+7*86400000};await fs.writeFile(meta,JSON.stringify(info));
      // Bounded on-disk image cache; audio stays on the listening device.
      const files=await Promise.all((await fs.readdir(directory)).filter(name=>/^[a-f\d]{64}\.image$/.test(name)).map(async name=>({name,...await fs.stat(path.join(directory,name))})));let total=files.reduce((sum,file)=>sum+file.size,0),maximum=(config.extractors?.cacheMB||512)*1024*1024;
      for(const file of files.sort((a,b)=>a.mtimeMs-b.mtimeMs))if(total>maximum&&file.name!==key+'.image'){await fs.unlink(path.join(directory,file.name)).catch(()=>{});await fs.unlink(path.join(directory,file.name+'.json')).catch(()=>{});total-=file.size;}
      return {location,...info};
    },60000);
  }
  ctx.externalCoverUrl=track=>safeCdn(track.artwork,'cover')?`/api/external-covers/${encodeURIComponent(track.id)}`:track.artwork;
  app.get('/api/external-covers/:id',asyncRoute(async(req,res)=>{const track=await ctx.requireTrack(req.params.id,req.auth?.user),file=await coverFile(track);await ctx.requireTrack(track.id,req.auth?.user);res.set({'Content-Type':file.type,'Cache-Control':track.public?'public, max-age=86400':'private, no-store','X-Content-Type-Options':'nosniff'}).sendFile(file.location);}));
  async function serveAudio(req,res,download=false){
    if(req.headers.range&&!/^bytes=(?:\d+-\d*|-\d+)$/.test(req.headers.range))fail(416,'INVALID_RANGE','Этот диапазон аудио недоступен.');
    const track=await ctx.requireTrack(req.params.id,req.auth.user);let result=await resolved(track);
    if(!result)fail(403,'DIRECT_AUDIO_UNAVAILABLE','Этот трек доступен только на площадке источника.');
    const isHls=/m3u8/i.test(result.info.protocol||'')||/\.m3u8(?:\?|$)/i.test(result.info.audio_url);
    if(!isHls&&!safeCdn(result.info.audio_url))fail(422,'AUDIO_FORMAT_UNAVAILABLE','Этот трек доступен для потокового прослушивания.');
    if(isHls&&(!download||!safeCdn(result.info.audio_url,'hls')))fail(422,'AUDIO_FORMAT_UNAVAILABLE','Этот трек доступен для потокового прослушивания.');
    if(download&&!result.permission.download)fail(403,'OFFLINE_UNAVAILABLE','Скачивание этого трека недоступно.');
    const mp3=download&&(req.query.format==='mp3'||isHls);if(req.query.format&&req.query.format!=='mp3'&&req.query.format!=='original')fail(400,'AUDIO_FORMAT','Выбери исходный формат или MP3.');
    if(mp3&&(!result.permission.convert||!ffmpeg))fail(403,'CONVERSION_UNAVAILABLE','Конвертация этого трека недоступна.');
    if(streams>=16||mp3&&conversion)fail(503,'EXTRACTOR_BUSY','Повтори загрузку чуть позже.');
    streams++;if(mp3)conversion=true;
    const controller=new AbortController(),abort=()=>controller.abort();transfers.add(controller);res.once('close',abort);const timeout=setTimeout(abort,Math.max(120000,(track.duration||600)*1000+120000));timeout.unref();let converter;
    try{
      const max=(download?Math.min(config.uploadLimitMB||256,512):512)*1024*1024;
      if(download&&!await rightFor(track)&&!licensePermission(result.info.license))fail(403,'OFFLINE_UNAVAILABLE','Разрешение на скачивание изменилось.');
      let bytes=0;const bounded=new Transform({transform(chunk,_encoding,callback){bytes+=chunk.length;callback(bytes>max?new Error('Audio byte limit'):null,chunk);}});
      if(isHls){
        res.status(200).set({'Content-Type':'audio/mpeg','Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff',...(download?{'Content-Disposition':`attachment; filename="glukwave-${digest(track.id).slice(0,20)}.mp3"`}:{})});
        if(req.method==='HEAD')return res.end();
        const ffmpegArgs=['-hide_banner','-loglevel','error','-nostdin','-threads','1','-protocol_whitelist','file,http,https,tcp,tls,crypto','-i',result.info.audio_url,'-vn','-codec:a','libmp3lame','-q:a','2','-f','mp3','pipe:1'];
        if(result.info.http_headers?.['User-Agent'])ffmpegArgs.splice(6,0,'-user_agent',result.info.http_headers['User-Agent']);
        converter=spawn(ffmpeg,ffmpegArgs,{windowsHide:true,stdio:['ignore','pipe','pipe']});converter.stderr.resume();
        const done=new Promise((resolve,reject)=>{converter.once('error',reject);converter.once('close',code=>code===0?resolve():reject(new Error('Conversion failed')));});
        await Promise.all([pipeline(converter.stdout,bounded,res,{signal:controller.signal}),done]);
      }else{
        const headers={...(result.info.http_headers||{}),...(req.headers.range&&!mp3?{Range:req.headers.range}:{})};
        let upstream=await pull(result.info.audio_url,{signal:controller.signal,headers});
        if([401,403,410].includes(upstream.status)){await upstream.body?.cancel();result=await resolved(track,{force:true});if(!result)fail(403,'DIRECT_AUDIO_UNAVAILABLE','Этот трек сейчас недоступен.');upstream=await pull(result.info.audio_url,{signal:controller.signal,headers});}
        if(upstream.status===416){await upstream.body?.cancel();if(upstream.headers.get('content-range'))res.set('Content-Range',upstream.headers.get('content-range'));return res.status(416).end();}
        if(!upstream.ok){await upstream.body?.cancel();fail(upstream.status===429?429:502,'EXTRACTOR_UPSTREAM','Источник временно не открыл трек.');}
        if(Number(upstream.headers.get('content-length'))>max){await upstream.body?.cancel();fail(413,'AUDIO_TOO_LARGE','Трек слишком большой для этой загрузки.');}
        const type=mp3?'audio/mpeg':({m4a:'audio/mp4',mp3:'audio/mpeg',opus:'audio/ogg',ogg:'audio/ogg',webm:'audio/webm'}[result.info.ext]||upstream.headers.get('content-type')||'application/octet-stream');
        res.status(!mp3&&upstream.status===206?206:200).set({'Content-Type':type,'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff',...(!mp3?{'Accept-Ranges':'bytes'}:{})});
        if(!mp3)for(const name of ['content-length','content-range'])if(upstream.headers.get(name))res.set(name,upstream.headers.get(name));
        if(download)res.set('Content-Disposition',`attachment; filename="glukwave-${digest(track.id).slice(0,20)}.${mp3?'mp3':/^(mp3|m4a|opus|ogg|webm)$/.test(result.info.ext)?result.info.ext:'audio'}"`);
        if(req.method==='HEAD'){await upstream.body?.cancel();return res.end();}
        const input=Readable.fromWeb(upstream.body);
        if(mp3){
          converter=spawn(ffmpeg,['-hide_banner','-loglevel','error','-nostdin','-threads','1','-protocol_whitelist','file,pipe','-i','pipe:0','-vn','-codec:a','libmp3lame','-q:a','2','-f','mp3','pipe:1'],{windowsHide:true,stdio:['pipe','pipe','pipe']});converter.stderr.resume();
          const done=new Promise((resolve,reject)=>{converter.once('error',reject);converter.once('close',code=>code===0?resolve():reject(new Error('Conversion failed')));});
          await Promise.all([pipeline(input,bounded,converter.stdin,{signal:controller.signal}),pipeline(converter.stdout,res,{signal:controller.signal}),done]);
        }else await pipeline(input,bounded,res,{signal:controller.signal});
      }
    }catch(error){if(!controller.signal.aborted&&!res.headersSent)throw error;if(!res.destroyed)res.destroy();}
    finally{clearTimeout(timeout);res.removeListener('close',abort);controller.abort();transfers.delete(controller);converter?.kill();streams--;if(mp3)conversion=false;}
  }
  app.get('/api/external-audio/:id',requireAuth,asyncRoute((req,res)=>serveAudio(req,res)));
  app.get('/api/external-audio/:id/download',requireAuth,limiter,asyncRoute((req,res)=>serveAudio(req,res,true)));
  app.get('/api/catalog/search',limiter,asyncRoute(async(req,res)=>{const query=parse(text(200),req.query.q),source=parse(z.enum(['youtube','soundcloud','spotify']),req.query.source||'youtube');const tracks=source==='youtube'?await ctx.extractorSearch(query):await ctx.searchProvider(source,query,req.auth?.user?.id);res.set('Cache-Control','private, no-store').json({tracks:tracks.map(track=>({title:track.title,artist:track.artist,album:track.album,duration:track.duration,cover:track.cover||track.artwork,source,track_id:track.track_id||track.sourceId,audio_url:null}))});}));
  app.get('/api/tracks/:id/audio-matches',requireAuth,limiter,asyncRoute(async(req,res)=>{const track=await ctx.requireTrack(req.params.id,req.auth.user);if(track.source!=='spotify')fail(400,'UNSUPPORTED_URL','Сопоставление доступно для Spotify.');res.set('Cache-Control','private, no-store').json(await cached('matches:'+track.id,()=>adapters.spotify.matches(track)));}));
  app.get('/api/admin/extractors',requireAdmin,asyncRoute(async(req,res)=>{if(Date.now()-versionsAt>300000){versions=await runtime.versions();versionsAt=Date.now();}res.set('Cache-Control','no-store').json({adapters:Object.keys(adapters).map(id=>({id,available:runtime.available(id)})),versions,queue:runtime.stats(),streaming:streams,metadataEntries:metadata.size(),pending:pending.size,conversion,hls:hls.stats(),ffmpeg:!!ffmpeg});}));
  const permissionSchema=z.object({stream:z.boolean(),download:z.boolean(),convert:z.boolean(),basis:z.enum(['owner-permission','license-agreement']),evidenceUrl:z.url().max(2048),audioSourceUrl:z.url().max(2048).optional(),expiresAt:z.number().int().positive().optional()}).strict();
  app.get('/api/admin/tracks/:id/audio-permission',requireAdmin,asyncRoute(async(req,res)=>{await ctx.requireTrack(req.params.id,req.auth.user);res.set('Cache-Control','no-store').json({permission:await store.get('audioPermissions',req.params.id)});}));
  app.put('/api/admin/tracks/:id/audio-permission',requireAdmin,asyncRoute(async(req,res)=>{const track=await ctx.requireTrack(req.params.id,req.auth.user),body=parse(permissionSchema,req.body);if(body.download&&!body.stream||body.convert&&!body.download)fail(400,'VALIDATION','Проверь разрешения аудио.');if(new URL(body.evidenceUrl).protocol!=='https:')fail(400,'INVALID_URL','Нужна HTTPS-ссылка на разрешение.');if(track.source==='spotify'&&!body.audioSourceUrl)fail(400,'AUDIO_MATCH_REQUIRED','Укажи точный источник аудио для Spotify.');if(body.audioSourceUrl&&!['soundcloud','youtube'].includes(sourceUrl(body.audioSourceUrl).source))fail(400,'UNSUPPORTED_URL','Нужен источник SoundCloud или YouTube.');const permission={id:track.id,...body,updatedBy:req.auth.user.id,updatedAt:now()};await store.put('audioPermissions',track.id,permission);await ctx.audit('audio.permission',req.auth.user.id,{trackId:track.id,stream:body.stream,download:body.download,convert:body.convert});res.json({permission});}));
  app.delete('/api/admin/tracks/:id/audio-permission',requireAdmin,asyncRoute(async(req,res)=>{await store.remove('audioPermissions',req.params.id);metadata.clear();await ctx.audit('audio.permission.remove',req.auth.user.id,{trackId:req.params.id});res.json({ok:true});}));
  ctx.closeExtractors=async()=>{hls.close();for(const controller of transfers)controller.abort();metadata.clear();await runtime.close();await Promise.allSettled([...pending.values()]);};
}
