import {parseLyrics,fail,now} from './util.js';
import {lyricsSignature} from './search.js';

const ROOT='https://lrclib.net/api/';
const normalized=value=>String(value||'').normalize('NFKD').replace(/\p{M}/gu,'').toLowerCase().replace(/[^\p{L}\p{N}]+/gu,' ').trim();
const empty={lines:[],synchronized:false,source:null};
const cleanTitle=value=>String(value||'').replace(/\s*[([](?:official\s*)?(?:music\s*)?(?:video|audio|lyrics?|visuali[sz]er|hd|hq)[^\])]*[\])]/gi,'').replace(/\s*[([](?:feat\.?|ft\.?|featuring)\s+[^\])]*[\])]/gi,'').replace(/\s*[|\-]\s*(?:official\s*)?(?:music\s*)?(?:video|audio|lyrics?|visuali[sz]er)\b.*$/i,'').trim();
const cleanArtist=value=>String(value||'').replace(/\s*-\s*Topic$/i,'').trim();
export function lyricsMetadata(track){
  let title=cleanTitle(track.title),artist=cleanArtist(track.artists?.[0]?.name||track.artist);
  const credited=title.match(/^(.{1,100}?)\s+[–—-]\s+(.+)$/);
  if(credited&&(track.source==='youtube'||track.source==='soundcloud')){
    artist=cleanArtist(credited[1]);title=cleanTitle(credited[2]);
  }
  return {title,artist};
}
function matches(record,metadata,track){
  return record&&normalized(cleanTitle(record.trackName))===normalized(metadata.title)&&
    [metadata.artist,track.artist,...(track.artists||[]).map(artist=>artist.name)].some(artist=>normalized(cleanArtist(record.artistName))===normalized(artist))&&
    (!track.duration||Math.abs(Number(record.duration)-track.duration)<=3);
}
export function lrclibLyrics(record){
  if(!record||!Number.isSafeInteger(record.id)||record.id<1)return null;
  const synced=typeof record.syncedLyrics==='string'?record.syncedLyrics.slice(0,100000):'';
  const plain=typeof record.plainLyrics==='string'?record.plainLyrics.slice(0,100000):'';
  const parsed=parseLyrics(synced||plain);
  return {...parsed,source:'lrclib',providerId:record.id,instrumental:record.instrumental===true,raw:synced||plain,attribution:'LRCLIB',sourceUrl:`https://lrclib.net/api/get/${record.id}`};
}
export function createLyricsProvider(ctx,fetcher=fetch){
  const inflight=new Map();
  async function request(path,params,deadline){
    const url=path instanceof URL?path:new URL(path,ROOT);if(params)url.search=new URLSearchParams(params).toString();
    const timeout=AbortSignal.timeout(6000);
    const response=await fetcher(url,{headers:{'User-Agent':'GlukWave/0.1.0 (https://wave.gluk.tech)','Accept':'application/json'},signal:deadline?AbortSignal.any([timeout,deadline]):timeout});
    if(response.status===404)return null;
    if(!response.ok)fail(502,'LYRICS_UNAVAILABLE','Поиск текста временно недоступен. Попробуй позже.');
    const limit=512*1024;if(Number(response.headers.get('content-length'))>limit)throw Error('LRCLIB response too large');
    const reader=response.body.getReader();let bytes=0;const chunks=[];
    try{while(true){const {done,value}=await reader.read();if(done)break;bytes+=value.length;if(bytes>limit)throw Error('LRCLIB response too large');chunks.push(Buffer.from(value));}}finally{await reader.cancel().catch(()=>{});}
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  }
  const signature=lyricsSignature;
  async function lookup(track){
    const key=signature(track),cached=await ctx.store.get('lyricsCache',key);
    if(cached&&cached.providerVersion===2&&cached.expiresAt>Date.now())return cached.lyrics;
    if(inflight.has(key))return inflight.get(key);
    if(inflight.size>=20)return {...empty,unavailable:true};
    const task=(async()=>{
      try{
        const deadline=AbortSignal.timeout(12000),metadata=lyricsMetadata(track);
        const params={track_name:String(track.title||'').slice(0,200),artist_name:String(track.artist||'').slice(0,200)};
        if(track.album)params.album_name=String(track.album).slice(0,200);
        if(track.duration>0)params.duration=String(track.duration);
        let lyrics=null,primaryFailure;
        try{
          const result=await request('get',params,deadline);
          if(matches(result,{title:track.title,artist:track.artist},track))lyrics=lrclibLyrics(result);
          if(!lyrics){
            // Search handles uploader credits and absent/mismatched album names.
            const results=await request('search',{track_name:metadata.title.slice(0,200),artist_name:metadata.artist.slice(0,200)},deadline);
            const candidates=(Array.isArray(results)?results:[]).filter(record=>matches(record,metadata,{...track,duration:0}));
            candidates.sort((a,b)=>(matches(b,metadata,track)&&b.syncedLyrics?1:0)-(matches(a,metadata,track)&&a.syncedLyrics?1:0));
            lyrics=candidates.map(record=>lrclibLyrics(matches(record,metadata,track)?record:{...record,syncedLyrics:'',instrumental:false})).find(value=>value&&(value.lines.length||value.instrumental))||null;
          }
        }catch(error){primaryFailure=error;}
        if(!lyrics?.lines.length&&!lyrics?.instrumental&&metadata.title&&metadata.artist&&!deadline.aborted){
          try{
            const url=new URL(`https://api.lyrics.ovh/v1/${encodeURIComponent(metadata.artist)}/${encodeURIComponent(metadata.title)}`);
            const result=await request(url,null,deadline),raw=typeof result?.lyrics==='string'?result.lyrics.slice(0,100000):'';
            if(raw.trim())lyrics={...parseLyrics(raw),source:'lyrics-ovh',raw,attribution:'lyrics.ovh',sourceUrl:url.href};
          }catch(error){primaryFailure ||= error;}
        }
        const found=lyrics&&(lyrics.lines.length||lyrics.instrumental),output=found?lyrics:{...empty,...(primaryFailure?{unavailable:true}:{})};
        if(primaryFailure&&!found)void ctx.reportError?.({platform:'server',kind:'background',message:primaryFailure.message,code:'LYRICS_LOOKUP',version:'0.1.0'}).catch(()=>{});
        const groups=await ctx.store.list('lyricsCache');if(groups.length>=2000){const old=groups.sort((a,b)=>a.expiresAt-b.expiresAt)[0];await ctx.store.remove('lyricsCache',old.id);}
        await ctx.store.put('lyricsCache',key,{id:key,providerVersion:2,lyrics:output,createdAt:now(),expiresAt:Date.now()+(found?86400000:primaryFailure?60000:1800000)});
        return output;
      }catch(error){
        const output={...empty,unavailable:true};
        void ctx.reportError?.({platform:'server',kind:'background',message:error.message,code:'LRCLIB_LOOKUP',version:'0.1.0'}).catch(()=>{});
        // A short cooldown prevents retry storms without suppressing recovery.
        await ctx.store.put('lyricsCache',key,{id:key,providerVersion:2,lyrics:output,createdAt:now(),expiresAt:Date.now()+60000});
        return output;
      }
    })();inflight.set(key,task);try{return await task;}finally{inflight.delete(key);}
  }
  async function search(title,artist){
    const metadata=lyricsMetadata({title,artist,source:'youtube'});
    let result=await request('search',{track_name:metadata.title,artist_name:metadata.artist});
    if(!Array.isArray(result)||!result.length)result=await request('search',{track_name:metadata.title});
    return (Array.isArray(result)?result:[]).slice(0,20).map(record=>({id:record.id,title:record.trackName,artist:record.artistName,album:record.albumName||'',duration:record.duration,...lrclibLyrics(record)})).filter(record=>record.providerId&&(record.lines.length||record.instrumental)).slice(0,10);
  }
  async function byId(id){const result=await request(`get/${id}`);return lrclibLyrics(result);}
  return {lookup,search,byId};
}
