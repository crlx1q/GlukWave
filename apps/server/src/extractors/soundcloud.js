import {load} from 'cheerio';
import {readSoundcloudPage, publicSoundcloudClient} from '../soundcloud-public.js';

let cachedClientId = null;
let cachedClientIdTime = 0;

async function getClientId(fetcher = fetch) {
  if (cachedClientId && Date.now() - cachedClientIdTime < 3600000) {
    return cachedClientId;
  }
  try {
    const html = await readSoundcloudPage('https://soundcloud.com', fetcher);
    const clientId = publicSoundcloudClient(html);
    if (clientId) {
      cachedClientId = clientId;
      cachedClientIdTime = Date.now();
      return clientId;
    }
  } catch {}
  return cachedClientId || null;
}

export function soundcloudAdapter(runtime, fetcher = fetch) {
  async function pureExtract(url) {
    let clientId = await getClientId(fetcher);
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
          cachedClientId = null;
          clientId = await getClientId(fetcher);
          if (clientId) {
            const retryRes = await fetcher(`https://api-v2.soundcloud.com/resolve?url=${encodeURIComponent(url)}&client_id=${clientId}`, {
              headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                Accept: 'application/json'
              },
              signal: AbortSignal.timeout(8000)
            });
            if (retryRes.ok) sound = await retryRes.json();
          }
        } else if (resolveRes.ok) {
          sound = await resolveRes.json();
        }
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
    const transcodings = sound.media?.transcodings || [];
    const hls = transcodings.find(t => t.format?.protocol === 'hls' && t.preset?.startsWith('aac')) ||
                transcodings.find(t => t.format?.protocol === 'hls') ||
                transcodings[0];
    if (!hls?.url) throw new Error('SoundCloud stream not found');

    const streamRes = await fetcher(hls.url + (hls.url.includes('?') ? '&' : '?') + 'client_id=' + clientId, {
      headers: { Accept: 'application/json' },
      signal: AbortSignal.timeout(10000)
    });
    if (!streamRes.ok) throw new Error(`SoundCloud stream fetch failed: ${streamRes.status}`);
    const streamData = await streamRes.json();
    if (!streamData.url) throw new Error('SoundCloud stream URL missing');

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
      license: String(sound.license || 'all-rights-reserved').slice(0, 500),
      availability: sound.sharing,
      audio_url: streamData.url,
      codec: hls.preset?.startsWith('aac') ? 'mp4a.40.2' : 'mp3',
      ext: hls.preset?.startsWith('aac') ? 'm4a' : 'mp3',
      protocol: 'm3u8_native',
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
