import {audioCapabilities} from '../audio-capabilities.js';
import {Readable,Transform} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import {asyncRoute,fail} from '../util.js';
import {rewriteSoundcloudManifest} from '../soundcloud-audio.js';

// Never expose signed CDN URLs. A grant is bound to one live account session;
// every manifest, encryption key and segment is checked against that session.
export function setupExtractedHls(app,ctx,{cdn,resolve,fetcher=fetch}){
  const grants=new Map(),transfers=new Set(),restoring=new Map(),capabilities=audioCapabilities(ctx.config.encryptionKey,'extracted-hls');let closed=false,parts=0;
  const drop=key=>{const grant=grants.get(key);if(grant)parts-=grant.parts.size;grants.delete(key);};
  const sweep=()=>{for(const [key,grant] of grants)if(grant.expiresAt<=Date.now())drop(key);};
  const timer=setInterval(sweep,60000);timer.unref();
  function issue(track,result,user,sessionId){
    if(closed||!user||!sessionId)return null;
    sweep();
    const prior=[...grants.values()].find(grant=>grant.trackId===track.id&&grant.sessionId===sessionId&&Date.now()-grant.createdAt<240000);
    if(prior)return {...prior.descriptor};
    while(grants.size>=128)drop(grants.keys().next().value);
    const createdAt=Date.now(),expiresAt=createdAt+Math.min(86400000,Math.max(7200000,((Number(track.duration)||0)+300)*1000));
    const token=capabilities.issueRoot({trackId:track.id,userId:user.id,sessionId,createdAt,expiresAt});
    const attribution={source:result.info.source,artist:result.info.artist||track.artist,sourceUrl:result.info.source_url||track.sourceUrl};
    const offline=!!(result.permission?.download&&ctx.config.env!=='test');
    const descriptor={kind:'audio',format:'hls',audioSource:result.info.source,offline,...(result.permission?.download?{downloadUrl:`/api/external-audio/${encodeURIComponent(track.id)}/download`}:{}),url:`/api/stream-audio/${encodeURIComponent(track.id)}?grant=${token}`,attribution};
    grants.set(token,{trackId:track.id,userId:user.id,sessionId,createdAt,expiresAt,parts:new Map([['root',result.info.audio_url]]),partVersions:new Map([['root',0]]),sourceVersion:0,reverse:new Map([[result.info.audio_url,'root']]),headers:result.info.http_headers||{},descriptor,refresh:null});parts++;
    return descriptor;
  }
  async function pull(input,signal,headers){
    let url=cdn(input);if(!url)fail(502,'EXTRACTOR_URL','Источник не открыл аудио.');
    for(let count=0;count<=3;count++){
      const response=await fetcher(url,{redirect:'manual',signal,headers});
      if([301,302,303,307,308].includes(response.status)){await response.body?.cancel();url=cdn(new URL(response.headers.get('location')||'',url).href);if(!url)fail(502,'EXTRACTOR_URL','Источник не открыл аудио.');continue;}
      return {response,url};
    }
    fail(502,'EXTRACTOR_URL','Источник не открыл аудио.');
  }
  app.get('/api/stream-audio/:id',asyncRoute(async(req,res)=>{
    sweep();const token=String(req.query.grant||''),part=String(req.query.part||'root');let grant=grants.get(token)||capabilities.root(token);
    if(!grant||grant.trackId!==req.params.id||closed)fail(401,'AUDIO_EXPIRED','Ссылка на аудио обновилась. Запусти трек ещё раз.');
    const [session,user]=await Promise.all([ctx.store.get('sessions',grant.sessionId),ctx.store.get('users',grant.userId)]);
    if(!session||session.userId!==grant.userId||session.expiresAt<=Date.now()||!user||user.blocked)fail(401,'AUTH_REQUIRED','Сессия завершена.');
    if(req.auth?.user&&req.auth.user.id!==grant.userId)fail(403,'TRACK_NOT_FOUND','Трек не найден.');
    let track=await ctx.requireTrack(grant.trackId,user);
    if(!grant.parts){
      if(!restoring.has(token)){
        if(restoring.size>=12)fail(503,'EXTRACTOR_BUSY','Музыка загружается. Повтори чуть позже.');
        const identity=grant;
        const work=(async()=>{const result=await resolve(track);if(!result?.permission.stream)fail(403,'DIRECT_AUDIO_UNAVAILABLE','Этот трек сейчас недоступен.');
          const value={...identity,parts:new Map([['root',result.info.audio_url]]),partVersions:new Map([['root',0]]),sourceVersion:0,reverse:new Map([[result.info.audio_url,'root']]),headers:result.info.http_headers||{},descriptor:{kind:'audio',format:'hls',audioSource:result.info.source,offline:false,url:`/api/stream-audio/${encodeURIComponent(identity.trackId)}?grant=${token}`,attribution:{source:result.info.source,artist:result.info.artist||track.artist,sourceUrl:result.info.source_url||track.sourceUrl}},refresh:null};
          while(grants.size>=128)drop(grants.keys().next().value);if(closed)fail(503,'EXTRACTOR_BUSY','Музыка загружается.');grants.set(token,value);parts++;return value;})().finally(()=>restoring.delete(token));restoring.set(token,work);
      }
      grant=await restoring.get(token);
    }
    if(part!=='root'&&!grant.parts.has(part)){const resource=capabilities.part(token,part);if(!resource||!cdn(resource))fail(404,'TRACK_NOT_FOUND','Трек не найден.');if(grant.parts.size>=8192||parts>=32768)fail(503,'EXTRACTOR_BUSY','Музыка загружается.');grant.parts.set(part,resource);grant.partVersions.set(part,0);grant.reverse.set(resource,part);parts++;}
    if(part==='root'){
      const result=await resolve(track);
      if(!result?.permission.stream)fail(403,'DIRECT_AUDIO_UNAVAILABLE','Этот трек сейчас недоступен.');
    }else{
      const record=await ctx.store.get('audioPermissions',grant.trackId);
      if(record&&record.stream===false)fail(403,'DIRECT_AUDIO_UNAVAILABLE','Этот трек сейчас недоступен.');
    }
    const resource=grant.parts.get(part),requestedVersion=grant.partVersions.get(part)||0;if(!resource)fail(404,'TRACK_NOT_FOUND','Трек не найден.');
    const range=req.headers.range;if(range&&!/^bytes=(?:\d+-\d*|-\d+)$/.test(range))fail(416,'INVALID_RANGE','Этот диапазон аудио недоступен.');
    if(transfers.size>=24)fail(503,'EXTRACTOR_BUSY','Музыка загружается. Повтори чуть позже.');
    if(req.aborted||res.destroyed||res.writableEnded)return;
    const controller=new AbortController(),abort=()=>controller.abort();transfers.add(controller);res.once('close',abort);req.once('aborted',abort);
    const timeout=setTimeout(abort,30000);timeout.unref();
    try{
      let {response,url}=await pull(resource,controller.signal,{...grant.headers,...(range?{Range:range}:{})}),responseVersion=requestedVersion;
      if([401,403,410].includes(response.status)){
        await response.body?.cancel();
        if(requestedVersion>=grant.sourceVersion){
          track??=await ctx.requireTrack(grant.trackId,user);
          grant.refresh??=resolve(track,{force:true}).then(fresh=>{
            if(!fresh?.permission.stream)fail(403,'DIRECT_AUDIO_UNAVAILABLE','Этот трек сейчас недоступен.');
            grant.reverse.delete(grant.parts.get('root'));grant.parts.set('root',fresh.info.audio_url);grant.reverse.set(fresh.info.audio_url,'root');grant.headers=fresh.info.http_headers||{};
            grant.partVersions.set('root',++grant.sourceVersion);return fresh;
          }).finally(()=>{grant.refresh=null;});await grant.refresh;
        }
        // An expired segment cannot be replaced by arbitrary new bytes. Ask the
        // player to reload the now-fresh manifest and retain its playback time.
        if(part!=='root')fail(410,'AUDIO_EXPIRED','Аудиопоток обновлён. Продолжи воспроизведение.');
        ({response,url}=await pull(grant.parts.get('root'),controller.signal,grant.headers));responseVersion=grant.sourceVersion;
      }
      if(response.status===416){await response.body?.cancel();if(response.headers.get('content-range'))res.set('Content-Range',response.headers.get('content-range'));return res.status(416).end();}
      if(!response.ok){await response.body?.cancel();fail(response.status===429?429:502,'EXTRACTOR_UPSTREAM','Источник временно не открыл трек.');}
      if(controller.signal.aborted||req.aborted||res.destroyed||res.writableEnded){await response.body?.cancel();return;}
      const type=response.headers.get('content-type')||'',manifest=/mpegurl/i.test(type)||/\.m3u8(?:\?|$)/i.test(url.href);
      res.set({'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'});
      if(manifest){
        const chunks=[];let bytes=0;
        try{for await(const chunk of response.body){bytes+=chunk.length;if(bytes>512*1024)fail(413,'AUDIO_TOO_LARGE','Источник не открыл аудио.');chunks.push(Buffer.from(chunk));}}finally{await response.body?.cancel().catch(()=>{});}
        const link=value=>{if(!cdn(value))fail(502,'EXTRACTOR_URL','Источник не открыл аудио.');let key=grant.reverse.get(value);if(!key){if(grant.parts.size>=8192||parts>=32768)fail(503,'EXTRACTOR_BUSY','Музыка загружается. Повтори чуть позже.');key=capabilities.issuePart(token,value,grant.expiresAt);grant.parts.set(key,value);grant.partVersions.set(key,responseVersion);grant.reverse.set(value,key);parts++;}return `/api/stream-audio/${encodeURIComponent(grant.trackId)}?grant=${token}&part=${key}`;};
        res.type('application/vnd.apple.mpegurl').send(rewriteSoundcloudManifest(Buffer.concat(chunks).toString('utf8'),url,link));
      }else{
        const max=32*1024*1024;if(Number(response.headers.get('content-length'))>max){await response.body?.cancel();fail(413,'AUDIO_TOO_LARGE','Фрагмент аудио слишком большой.');}
        res.status(response.status===206?206:200).type(type||'application/octet-stream');for(const name of ['content-length','content-range','accept-ranges'])if(response.headers.get(name))res.set(name,response.headers.get(name));
        if(req.method==='HEAD'){await response.body?.cancel();res.end();}else{let bytes=0;const limit=new Transform({transform(chunk,_,done){bytes+=chunk.length;done(bytes>max?new Error('Audio segment limit'):null,chunk);}});await pipeline(Readable.fromWeb(response.body),limit,res,{signal:controller.signal});}
      }
    }catch(error){if(!controller.signal.aborted&&!req.aborted&&!res.destroyed&&!res.headersSent)throw error;if(!res.destroyed)res.destroy();}
    finally{clearTimeout(timeout);res.removeListener('close',abort);req.removeListener('aborted',abort);controller.abort();transfers.delete(controller);}
  }));
  return {issue,stats:()=>({grants:grants.size,parts,transfers:transfers.size}),close(){closed=true;clearInterval(timer);for(const controller of transfers)controller.abort();grants.clear();parts=0;}};
}
