import {randomBytes} from 'node:crypto';
import {Readable,Transform} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import {asyncRoute,fail} from './util.js';
import {audioMatch} from './extractors/matching.js';

export function soundcloudCdn(input){
  let url;try{url=new URL(input);}catch{return null;}
  return url.protocol==='https:'&&!url.username&&!url.password&&!url.port&&
    ['sndcdn.com','soundcloud.com'].some(host=>url.hostname===host||url.hostname.endsWith('.'+host))?url:null;
}
export function rewriteSoundcloudManifest(raw,base,link){
  if(!raw.trimStart().startsWith('#EXTM3U'))fail(502,'AUDIO_FORMAT_UNAVAILABLE','Источник не открыл аудио.');
  return raw.split(/\r?\n/).map(line=>{
    if(!line.trim())return line;
    if(line.startsWith('#'))return line.replace(/URI="([^"]+)"/g,(_,uri)=>`URI="${link(new URL(uri,base).href)}"`);
    return link(new URL(line.trim(),base).href);
  }).join('\n');
}

// API playback and independently licensed downloading are separate paths.
// Session streams never enter the user's permanent MusicCache.
export function setupSoundcloudAudio(app,ctx,fetcher=fetch){
  const grants=new Map(),transfers=new Set(),resolving=new Map();let closed=false,partCount=0;
  const drop=key=>{const value=grants.get(key);if(value)partCount-=value.parts.size;grants.delete(key);};
  const configured=()=>!!(ctx.config.soundcloud.id&&ctx.config.soundcloud.secret);
  async function metadata(track,user){
    const privateTrack=track.public===false;
    const linked=privateTrack?await ctx.store.get('connections',`${user.id}:soundcloud`):null;
    if(privateTrack&&!linked)return null;
    const uid=linked?user.id:null;
    const call=pathname=>ctx.officialSoundcloudCall(pathname,uid);
    let resource;
    if(track.source==='soundcloud'){
      const sid=String(track.sourceId||'');
      const urn=/^(?:soundcloud:tracks:)?\d+$/.test(sid)?(sid.startsWith('soundcloud:tracks:')?sid:`soundcloud:tracks:${sid}`):null;
      resource=await call(urn?`tracks/${encodeURIComponent(urn)}`:`resolve?${new URLSearchParams({url:track.sourceUrl})}`);
    }else{
      if(!['spotify','youtube','yandex'].includes(track.source)||!(track.duration>0)||!track.artist)return null;
      const found=await call(`tracks?${new URLSearchParams({q:track.artist+' '+track.title,access:'playable',limit:'5',linked_partitioning:'true'})}`);
      const target={...track,artist:track.artist.replace(/\s*-\s*Topic$/i,'')};
      const matches=(found.collection||[]).flatMap(item=>{
        const candidates=[{title:item.title,artist:item.metadata_artist||item.user?.username||'',duration:Number(item.duration)/1000}];
        // Some uploaders put the actual artist in "Artist - Title". Only split
        // explicit separators and still require all strict match thresholds.
        const split=String(item.title||'').match(/^(.+?)\s+(?:-|–|—)\s+(.+)$/);
        if(split)candidates.push({title:split[2],artist:split[1],duration:Number(item.duration)/1000});
        return candidates.map(candidate=>({item,match:audioMatch(target,candidate)})).filter(value=>value.match.accepted);
      }).sort((a,b)=>b.match.score-a.match.score);
      resource=matches[0]?.item;
      if(!resource)return null;
    }
    if(resource.access==='blocked'||resource.access==='preview'||resource.streamable===false)return null;
    const identity=resource.urn||String(resource.id||'');
    const urn=/^\d+$/.test(identity)?`soundcloud:tracks:${identity}`:identity;
    if(!/^(?:soundcloud:tracks:)?\d+$/.test(urn))return null;
    const streams=await call(`tracks/${encodeURIComponent(urn)}/streams`);
    const url=streams.hls_aac_160_url||streams.hls_mp3_128_url;
    if(!soundcloudCdn(url))return null;
    return {url,attribution:{source:'soundcloud',artist:resource.user?.username||resource.metadata_artist||track.artist,sourceUrl:resource.permalink_url||track.sourceUrl,creatorUrl:resource.user?.permalink_url||''}};
  }
  ctx.soundcloudPlayback=async(track,user,sessionId)=>{
    if(!configured()||!user||!sessionId||closed)return null;
    const resolutionKey=`${sessionId}:${track.id}`;
    for(const [key,grant]of grants)if(grant.expiresAt<=Date.now())drop(key);
    const existing=[...grants].find(([,grant])=>grant.sessionId===sessionId&&grant.trackId===track.id&&Date.now()-grant.createdAt<300000);
    if(existing)return {...existing[1].descriptor};
    if(resolving.has(resolutionKey))return resolving.get(resolutionKey);
    if(resolving.size>=12)fail(503,'EXTRACTOR_BUSY','Музыка загружается. Повтори чуть позже.');
    const pending=(async()=>{
    const info=await metadata(track,user);if(!info||closed)return null;
    const token=randomBytes(24).toString('base64url'),expiresAt=Date.now()+Math.min(86400000,Math.max(7200000,((Number(track.duration)||0)+300)*1000));
    while(grants.size>=128)drop(grants.keys().next().value);
    const descriptor={kind:'audio',format:'hls',provider:'soundcloud',url:`/api/soundcloud-audio/${encodeURIComponent(track.id)}?grant=${token}`,offline:false,attribution:info.attribution};
    grants.set(token,{trackId:track.id,userId:user.id,sessionId,expiresAt,createdAt:Date.now(),parts:new Map([['root',info.url]]),reverse:new Map([[info.url,'root']]),descriptor,refresh:null});partCount++;
    return descriptor;
    })();resolving.set(resolutionKey,pending);try{return await pending;}finally{resolving.delete(resolutionKey);}
  };
  async function pull(input,signal,range){
    let url=soundcloudCdn(input);if(!url)fail(502,'EXTRACTOR_URL','Источник не открыл аудио.');
    for(let redirects=0;redirects<=3;redirects++){
      const response=await fetcher(url,{redirect:'manual',signal,headers:range?{Range:range}:{}});
      if([301,302,303,307,308].includes(response.status)){await response.body?.cancel();url=soundcloudCdn(new URL(response.headers.get('location')||'',url).href);if(!url)fail(502,'EXTRACTOR_URL','Источник не открыл аудио.');continue;}
      return {response,url};
    }fail(502,'EXTRACTOR_URL','Источник не открыл аудио.');
  }
  app.get('/api/soundcloud-audio/:id',asyncRoute(async(req,res)=>{
    const grant=grants.get(String(req.query.grant||'')),part=String(req.query.part||'root');
    if(!grant||grant.trackId!==req.params.id||grant.expiresAt<=Date.now()||closed)fail(401,'AUTH_REQUIRED','Войди в GlukWave, чтобы продолжить.');
    const [session,user]=await Promise.all([ctx.store.get('sessions',grant.sessionId),ctx.store.get('users',grant.userId)]);
    if(!session||session.userId!==grant.userId||session.expiresAt<=Date.now()||!user||user.blocked)fail(401,'AUTH_REQUIRED','Сессия завершена.');
    if(req.auth?.user&&req.auth.user.id!==grant.userId)fail(403,'TRACK_NOT_FOUND','Трек не найден.');
    const track=await ctx.requireTrack(grant.trackId,user);
    const resource=grant.parts.get(part);if(!resource)fail(404,'TRACK_NOT_FOUND','Трек не найден.');
    const range=req.headers.range;if(range&&!/^bytes=(?:\d+-\d*|-\d+)$/.test(range))fail(416,'INVALID_RANGE','Этот диапазон аудио недоступен.');
    if(transfers.size>=24)fail(503,'EXTRACTOR_BUSY','Музыка загружается. Повтори чуть позже.');
    const controller=new AbortController(),abort=()=>controller.abort();transfers.add(controller);res.once('close',abort);
    const timer=setTimeout(abort,30000);timer.unref();
    try{
      let {response,url}=await pull(resource,controller.signal,range);
      if([401,403].includes(response.status)&&part==='root'){
        await response.body?.cancel();
        grant.refresh??=metadata(track,user).finally(()=>{grant.refresh=null;});
        const fresh=await grant.refresh;
        if(fresh){grant.reverse.delete(resource);grant.parts.set('root',fresh.url);grant.reverse.set(fresh.url,'root');({response,url}=await pull(fresh.url,controller.signal,range));}
      }
      if(!response.ok){await response.body?.cancel();fail(response.status===429?429:502,'EXTRACTOR_UPSTREAM','Источник временно не открыл трек.');}
      const type=response.headers.get('content-type')||'',manifest=/mpegurl/i.test(type)||/\.m3u8(?:\?|$)/i.test(url.href);
      res.set({'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'});
      if(manifest){
        let bytes=0;const chunks=[];
        try{for await(const chunk of response.body){bytes+=chunk.length;if(bytes>512*1024)fail(413,'AUDIO_TOO_LARGE','Источник не открыл аудио.');chunks.push(Buffer.from(chunk));}}finally{await response.body?.cancel().catch(()=>{});}
        const link=value=>{
          if(!soundcloudCdn(value))fail(502,'EXTRACTOR_URL','Источник не открыл аудио.');
          let key=grant.reverse.get(value);
          if(!key){if(grant.parts.size>=8192||partCount>=32768)fail(503,'EXTRACTOR_BUSY','Музыка загружается. Повтори чуть позже.');key=randomBytes(12).toString('base64url');grant.parts.set(key,value);grant.reverse.set(value,key);partCount++;}
          return `/api/soundcloud-audio/${encodeURIComponent(grant.trackId)}?grant=${req.query.grant}&part=${key}`;
        };
        res.type('application/vnd.apple.mpegurl').send(rewriteSoundcloudManifest(Buffer.concat(chunks).toString('utf8'),url,link));
      }else{
        const maximum=32*1024*1024;if(Number(response.headers.get('content-length'))>maximum){await response.body?.cancel();fail(413,'AUDIO_TOO_LARGE','Фрагмент аудио слишком большой.');}
        res.status(response.status===206?206:200).type(type||'application/octet-stream');
        for(const key of ['content-length','content-range','accept-ranges'])if(response.headers.get(key))res.set(key,response.headers.get(key));
        let bytes=0;const limit=new Transform({transform(chunk,_,done){bytes+=chunk.length;done(bytes>maximum?new Error('Audio segment limit'):null,chunk);}});
        if(req.method==='HEAD'){await response.body?.cancel();res.end();}else await pipeline(Readable.fromWeb(response.body),limit,res,{signal:controller.signal});
      }
    }catch(error){if(!controller.signal.aborted&&!res.headersSent)throw error;if(!res.destroyed)res.destroy();}
    finally{clearTimeout(timer);res.removeListener('close',abort);controller.abort();transfers.delete(controller);}
  }));
  ctx.closeSoundcloudAudio=()=>{closed=true;for(const controller of transfers)controller.abort();grants.clear();partCount=0;};
  ctx.soundcloudAudioStats=()=>({configured:configured(),activeTransfers:transfers.size,resolving:resolving.size,grants:grants.size,parts:partCount,limits:{transfers:24,resolving:12,grants:128,parts:32768}});
}
