import {load} from 'cheerio';
import {HttpError,fail} from './util.js';

const maxBytes=1536*1024,maxText=100000;
const unavailable=()=>new HttpError(502,'LYRICS_SOURCE_UNAVAILABLE','Genius сейчас недоступен. Попробуй другой источник или вставь текст вручную.');

export function geniusUrl(input){
  let url;
  try{url=new URL(input);}catch{}
  if(!url||typeof input!=='string'||input.length>2048||url.protocol!=='https:'||
    !['genius.com','www.genius.com'].includes(url.hostname)||url.username||url.password||url.port||
    !/^\/[\p{L}\p{N}_%.'-]+-lyrics\/?$/u.test(url.pathname)||/%(?:2f|5c|0[0-9a-f]|1[0-9a-f]|7f)/i.test(url.pathname))
    fail(400,'LYRICS_SOURCE_URL','Вставь HTTPS-ссылку на страницу песни Genius, которая заканчивается на -lyrics.');
  url.hostname='genius.com';url.search='';url.hash='';url.pathname=url.pathname.replace(/\/$/,'');
  return url.href;
}

// Read only the dedicated lyrics containers, never navigation, annotations or page scripts.
export function parseGeniusLyrics(html,sourceUrl){
  const $=load(html);
  let containers=$('[data-lyrics-container="true"]');
  if(!containers.length)containers=$('.lyrics');
  if(!containers.length)containers=$('[class*="Lyrics__Container"]');
  const selected=new Set(containers.toArray()),parts=[];
  containers.each((_,container)=>{
    let parent=container.parent;
    while(parent){if(selected.has(parent))return;parent=parent.parent;}
    $(container).find('script,style,noscript,button,svg,iframe,[aria-hidden="true"],[data-exclude-from-selection="true"]').remove();
    const text=[];
    const walk=node=>{
      if(node.type==='text'){text.push(node.data);return;}
      if(node.type!=='tag')return;
      if(node.name==='br'){text.push('\n');return;}
      const block=['div','p','section'].includes(node.name);
      if(block&&text.length)text.push('\n');
      for(const child of node.children||[])walk(child);
      if(block)text.push('\n');
    };
    walk(container);parts.push(text.join(''));
  });
  const raw=parts.join('\n\n').replace(/\r/g,'').replace(/\u00a0/g,' ')
    .split('\n').map(line=>line.replace(/[\t ]+/g,' ').trim()).join('\n').replace(/\n{3,}/g,'\n\n').trim();
  if(raw.length>maxText)fail(413,'LYRICS_SOURCE_TOO_LARGE','Текст слишком большой. Выбери другую страницу песни.');
  if(!raw)fail(404,'LYRICS_NOT_FOUND','На этой странице не найден текст песни.');
  // Genius supplies plain text. Bracketed section labels or numbers are not LRC timestamps.
  return {lines:raw.split('\n').filter(Boolean).map(text=>({time:null,text})),synchronized:false,source:'genius',raw,attribution:'Genius',sourceUrl:geniusUrl(sourceUrl)};
}

export function createGeniusProvider(fetcher=fetch,{timeoutMs=8000,maxInflight=4,cacheEntries=100,cacheMs=300000}={}){
  const cache=new Map(),inflight=new Map(),controllers=new Set();let closed=false;
  async function request(sourceUrl){
    if(closed)throw unavailable();
    const controller=new AbortController();controllers.add(controller);
    const timer=setTimeout(()=>controller.abort(),timeoutMs);timer.unref?.();
    try{
      let url=sourceUrl;
      for(let redirects=0;redirects<=2;redirects++){
        const response=await fetcher(url,{redirect:'manual',signal:controller.signal,headers:{Accept:'text/html','User-Agent':'GlukWave/0.1.0 (+https://wave.gluk.tech)'}});
        if([301,302,303,307,308].includes(response.status)){
          await response.body?.cancel();
          if(redirects===2||!response.headers.get('location'))throw unavailable();
          let next;try{next=geniusUrl(new URL(response.headers.get('location'),url).href);}catch{throw unavailable();}
          url=next;continue;
        }
        if(!response.ok){await response.body?.cancel();if(response.status===404)fail(404,'LYRICS_NOT_FOUND','Страница песни не найдена.');throw unavailable();}
        const type=response.headers.get('content-type');
        if(type&&!/^(?:text\/html|application\/xhtml\+xml)(?:;|$)/i.test(type)){await response.body?.cancel();throw unavailable();}
        if(Number(response.headers.get('content-length'))>maxBytes){await response.body?.cancel();fail(413,'LYRICS_SOURCE_TOO_LARGE','Страница слишком большая. Выбери другую страницу песни.');}
        if(!response.body)throw unavailable();
        const reader=response.body.getReader(),chunks=[];let bytes=0;
        try{
          while(true){const {done,value}=await reader.read();if(done)break;bytes+=value.byteLength;if(bytes>maxBytes)fail(413,'LYRICS_SOURCE_TOO_LARGE','Страница слишком большая. Выбери другую страницу песни.');chunks.push(Buffer.from(value));}
        }finally{await reader.cancel().catch(()=>{});reader.releaseLock();}
        return parseGeniusLyrics(Buffer.concat(chunks).toString('utf8'),url);
      }
      throw unavailable();
    }catch(error){if(error instanceof HttpError)throw error;throw unavailable();}
    finally{clearTimeout(timer);controllers.delete(controller);}
  }
  function preview(input){
    const url=geniusUrl(input);if(closed)throw unavailable();
    const cached=cache.get(url);
    if(cached&&cached.expiresAt>Date.now()){cache.delete(url);cache.set(url,cached);return Promise.resolve(structuredClone(cached.lyrics));}
    cache.delete(url);
    if(inflight.has(url))return inflight.get(url).then(structuredClone);
    if(inflight.size>=maxInflight)fail(429,'LYRICS_SOURCE_BUSY','Слишком много запросов текста. Попробуй через несколько секунд.');
    const task=Promise.resolve().then(()=>request(url)).then(lyrics=>{
      if(!closed){cache.set(url,{lyrics,expiresAt:Date.now()+cacheMs});while(cache.size>cacheEntries)cache.delete(cache.keys().next().value);}
      return lyrics;
    }).finally(()=>inflight.delete(url));
    inflight.set(url,task);return task.then(structuredClone);
  }
  return {preview,async close(){closed=true;for(const controller of controllers)controller.abort();await Promise.allSettled(inflight.values());cache.clear();}};
}
