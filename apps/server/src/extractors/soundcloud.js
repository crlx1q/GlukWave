import {load} from 'cheerio';
import {readSoundcloudPage, publicSoundcloudClient} from '../soundcloud-public.js';

export function soundcloudAdapter(runtime, fetcher = fetch) {
  let cachedClientId=null,cachedClientIdTime=0,clientJob=null,clientRetryAt=0;
  async function getClientId(){
    if(cachedClientId&&Date.now()-cachedClientIdTime<3600000)return cachedClientId;
    if(clientJob)return clientJob;
    if(Date.now()<clientRetryAt)return null;
    clientJob=(async()=>{try{const id=publicSoundcloudClient(await readSoundcloudPage('https://soundcloud.com',fetcher));if(id){cachedClientId=id;cachedClientIdTime=Date.now();return id;}}catch{}clientRetryAt=Date.now()+15000;return null;})().finally(()=>{clientJob=null;});
    return clientJob;
  }
  async function json(response){
    const chunks=[];let size=0;
    try{for await(const chunk of response.body){size+=chunk.length;if(size>512*1024)throw Error('SoundCloud metadata limit');chunks.push(Buffer.from(chunk));}}finally{await response.body?.cancel().catch(()=>{});}
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  }
  async function pureExtract(url) {
    let clientId = await getClientId();
    let sound = null;

    // Fast path: try api-v2.soundcloud.com/resolve with cached client ID
    if (clientId) {
      try {
        const resolveRes = await fetcher(`https://api-v2.soundcloud.com/resolve?url=${encodeURIComponent(url)}&client_id=${clientId}`, {
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            Accept: 'application/json'
          },
          signal: AbortSignal.timeout(8000)
        });
        if (resolveRes.status === 401) {
          await resolveRes.body?.cancel();
          cachedClientId = null;
          clientRetryAt=0;
          clientId = await getClientId();
          if (clientId) {
            const retryRes = await fetcher(`https://api-v2.soundcloud.com/resolve?url=${encodeURIComponent(url)}&client_id=${clientId}`, {
              headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                Accept: 'application/json'
              },
              signal: AbortSignal.timeout(8000)
            });
            if (retryRes.ok) sound = await json(retryRes);else await retryRes.body?.cancel();
          }
        } else if (resolveRes.ok) {
          sound = await json(resolveRes);
        }else await resolveRes.body?.cancel();
      } catch {}
    }

    // Fallback: parse HTML page hydration
    if (!sound?.id) {
      const html = await readSoundcloudPage(url, fetcher);
      if (!clientId) {
        clientId = publicSoundcloudClient(html);
        if (clientId) {
          cachedClientId = clientId;
          cachedClientIdTime = Date.now();
        }
      }
      if (!clientId) throw new Error('SoundCloud client ID not found');
      const $ = load(html);
      let entries;
      for (const el of $('script').toArray()) {
        const text = $(el).text();
        const start = text.indexOf('window.__sc_hydration');
        if (start < 0) continue;
        const match = text.slice(start).match(/^window\.__sc_hydration\s*=\s*(\[.*\])\s*;?\s*$/s);
        if (match) {
          try { entries = JSON.parse(match[1]); } catch {}
          break;
        }
      }
      sound = entries?.find(e => e.hydratable === 'sound')?.data;
    }

    if (!sound?.id) throw new Error('SoundCloud track data not found');
    if(sound.policy==='BLOCK')throw new Error('SoundCloud track unavailable');
    const aac=t=>t.preset?.startsWith('aac')||/audio\/(?:aac|mp4)/i.test(t.format?.mime_type||'');
    const mp3=t=>t.preset?.startsWith('mp3')||/audio\/mpeg/i.test(t.format?.mime_type||'');
    const candidates=(sound.media?.transcodings||[]).filter(t=>!t.snipped&&
      (t.format?.protocol==='hls'&& (aac(t)||mp3(t)) || t.format?.protocol==='progressive'&&mp3(t)))
      .sort((a,b)=>(aac(b)?2:b.format.protocol==='progressive'?1:0)-(aac(a)?2:a.format.protocol==='progressive'?1:0)).slice(0,3);
    let hls,streamData;
    for(const candidate of candidates){
      let endpoint;try{endpoint=new URL(candidate.url);}catch{continue;}
      if(endpoint.protocol!=='https:'||endpoint.hostname!=='api-v2.soundcloud.com'||endpoint.port||endpoint.username||endpoint.password)continue;
      endpoint.searchParams.set('client_id',clientId);
      try{
        const response=await fetcher(endpoint,{headers:{Accept:'application/json'},signal:AbortSignal.timeout(8000),redirect:'error'});
        if(!response.ok){await response.body?.cancel();continue;}
        const data=await json(response);if(!data.url)continue;
        streamData=data;hls=candidate;break;
      }catch{/* Try another full audio encoding before the Python fallback. */}
    }
    if(!streamData?.url)throw new Error('SoundCloud stream not found');

    const artist = sound.user?.username || sound.user?.permalink || '';
    const duration = sound.duration ? Number(sound.duration) / 1000 : 0;
    const rawArtwork = sound.artwork_url || sound.user?.avatar_url || '';
    const cover = rawArtwork ? rawArtwork.replace('-large.', '-t500x500.') : '';

    return {
      track_id: String(sound.id),
      title: String(sound.title || '').slice(0, 300),
      artist: String(artist).slice(0, 300),
      album: '',
      duration,
      cover,
      source: 'soundcloud',
      source_url: sound.permalink_url || url,
      genres:[String(sound.genre||'')].filter(Boolean),tags:(String(sound.tag_list||'').match(/"[^"]+"|\S+/g)||[]).map(value=>value.replace(/^"|"$/g,'')).slice(0,30),
      license: String(sound.license || 'all-rights-reserved').slice(0, 500),
      availability: sound.sharing,
      audio_url: streamData.url,
      codec: aac(hls) ? 'mp4a.40.2' : 'mp3',
      ext: aac(hls) ? 'm4a' : 'mp3',
      protocol: hls.format.protocol==='hls'?'m3u8_native':'https',
      http_headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        Accept: '*/*'
      }
    };
  }

  return {
    id: 'soundcloud',
    async metadata(url) {
      try {
        return await pureExtract(url);
      } catch (err) {
        if (runtime?.hasPython?.('soundcloud')) {
          return await runtime.execute('soundcloud', { action: 'extract', source: 'soundcloud', url });
        }
        throw err;
      }
    }
  };
}
