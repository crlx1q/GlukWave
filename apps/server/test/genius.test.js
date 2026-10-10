import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {geniusUrl,parseGeniusLyrics,createGeniusProvider} from '../src/genius.js';
import {config} from '../src/config.js';
import {createApp} from '../src/app.js';

const url='https://genius.com/Wave-test-lyrics';
// Original test prose: no copied song lyrics or production account data.
const html='<html><body><nav>Not a lyric</nav><div data-lyrics-container="true">[Verse 1]<br>Amber &amp; silver <a href="/annotation">on the water</a><br>[00:01] A number in a poem<button>Translate</button><svg>Icon</svg><span aria-hidden="true">Decoration</span></div><div data-lyrics-container="true"><p>Another original line</p></div><footer>Embed</footer><script>alert(1)</script></body></html>';
const page=value=>new Response(value||html,{headers:{'Content-Type':'text/html; charset=utf-8'}});

test('Genius extracts dedicated containers, section labels and entities without scripts or invented sync',()=>{
 const lyrics=parseGeniusLyrics(html,url);assert.equal(lyrics.synchronized,false);assert.equal(lyrics.source,'genius');assert.equal(lyrics.attribution,'Genius');assert.equal(lyrics.sourceUrl,url);
 assert.deepEqual(lyrics.lines,[{time:null,text:'[Verse 1]'},{time:null,text:'Amber & silver on the water'},{time:null,text:'[00:01] A number in a poem'},{time:null,text:'Another original line'}]);
 assert.equal(parseGeniusLyrics('<div class="lyrics"><p>First<br>Second</p></div>',url).raw,'First\nSecond');
 assert.equal(parseGeniusLyrics('<div data-lyrics-container="true">Outer<div data-lyrics-container="true">Nested</div></div>',url).raw,'Outer\nNested');
 assert.throws(()=>parseGeniusLyrics('<main>Description only</main>',url),{code:'LYRICS_NOT_FOUND'});
});

test('Genius URLs are canonical HTTPS song pages on the fixed host only',()=>{
 assert.equal(geniusUrl('https://www.genius.com/Wave-test-lyrics/?utm_source=ignore#annotation'),url);
 for(const unsafe of ['http://genius.com/Wave-test-lyrics','https://evil.test/Wave-test-lyrics','https://genius.com.evil.test/Wave-test-lyrics','https://genius.com@127.0.0.1/Wave-test-lyrics','https://name:password@genius.com/Wave-test-lyrics','https://genius.com:444/Wave-test-lyrics','https://genius.com/api/search','https://genius.com/a/b-lyrics','https://genius.com/a%2fb-lyrics','file:///Wave-test-lyrics'])assert.throws(()=>geniusUrl(unsafe),{code:'LYRICS_SOURCE_URL'});
});

test('Genius coalesces requests, clones cached results and refuses external redirects',async()=>{
 let count=0;const provider=createGeniusProvider(async()=>{count++;return page();});
 try{const [one,two]=await Promise.all([provider.preview(url),provider.preview(url+'?utm_source=x')]);assert.equal(count,1);one.lines[0].text='Changed';assert.equal(two.lines[0].text,'[Verse 1]');assert.equal((await provider.preview(url)).lines[0].text,'[Verse 1]');assert.equal(count,1);}finally{await provider.close();}
 count=0;const redirect=createGeniusProvider(async()=>{count++;return new Response(null,{status:302,headers:{Location:'https://127.0.0.1/private-lyrics'}});});
 try{await assert.rejects(redirect.preview(url),{code:'LYRICS_SOURCE_UNAVAILABLE'});assert.equal(count,1);}finally{await redirect.close();}
});

test('Genius bounds streamed bytes and concurrency and releases requests on shutdown',async()=>{
 let canceled=false;const huge=createGeniusProvider(async()=>new Response(new ReadableStream({pull(c){c.enqueue(new Uint8Array(256*1024));},cancel(){canceled=true;}}),{headers:{'Content-Type':'text/html'}}));
 try{await assert.rejects(huge.preview(url),{code:'LYRICS_SOURCE_TOO_LARGE'});assert(canceled);}finally{await huge.close();}
 let started=0,aborted=0;const held=createGeniusProvider(async(_url,{signal})=>{started++;return new Promise((_resolve,reject)=>signal.addEventListener('abort',()=>{aborted++;reject(signal.reason);},{once:true}));},{maxInflight:1});
 const pending=assert.rejects(held.preview(url),{code:'LYRICS_SOURCE_UNAVAILABLE'});await new Promise(resolve=>setImmediate(resolve));
 assert.throws(()=>held.preview('https://genius.com/Other-test-lyrics'),{code:'LYRICS_SOURCE_BUSY'});await held.close();await pending;assert.equal(started,1);assert.equal(aborted,1);
 assert.throws(()=>held.preview(url),{code:'LYRICS_SOURCE_UNAVAILABLE'});
});

test('Genius timeouts and failures do not poison subsequent previews',async()=>{
 let calls=0;const timeout=createGeniusProvider(async(_url,{signal})=>{if(++calls>1)return page();return new Promise((_resolve,reject)=>signal.addEventListener('abort',()=>reject(signal.reason),{once:true}));},{timeoutMs:20});
 const keepalive=setTimeout(()=>{},200);
 try{await assert.rejects(timeout.preview(url),{code:'LYRICS_SOURCE_UNAVAILABLE'});assert.equal((await timeout.preview(url)).source,'genius');}finally{clearTimeout(keepalive);await timeout.close();}
});

test('Genius preview is authenticated and non-persistent; save respects track access and owner rights',async()=>{
 const qa=path.join(config.root,'work/qa');await fs.mkdir(qa,{recursive:true});const directory=await fs.mkdtemp(path.join(qa,'genius-test-'));let calls=0,failed=false,hold=null,started=null;
 const service=await createApp({...config,env:'test',production:false,storage:'sqlite',objectStorage:'local',dataDir:directory,releasesDir:directory,emailVerify:false,turnstileSecret:'',turnstileSiteKey:'',smtp:'',adminEmails:[],soundcloudPublicSearch:false,google:{id:'',secret:''},spotify:{id:'',secret:''},youtubeOAuth:{id:'',secret:''},soundcloud:{id:'',secret:''},discord:{id:'',secret:''},youtubeKey:'',stripe:{secret:'',webhook:'',price:''}},
  {log:pino({level:'silent'}),geniusFetch:async()=>{calls++;started?.();if(hold)await hold;return failed?new Response(null,{status:403}):page();},lyricsFetch:async()=>new Response('[]')});
 try{
  await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}/api`;
  const req=async(route,token,body,method=body?'POST':'GET')=>{const response=await fetch(base+route,{method,headers:{'X-GlukWave-Client':'native','Accept-Language':'en',...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,data:await response.json()};};
  const register=async username=>{const result=await req('/auth/register',null,{username,email:username+'@example.test',password:'Private-original-Genius-test-2026'});assert.equal(result.status,201);return result.data;};
  const owner=await register('genius_owner'),viewer=await register('genius_viewer'),store=service.ctx.store;
  for(const track of [{id:'external',source:'youtube',public:true},{id:'local',source:'local',uploadedBy:owner.user.id,public:true},{id:'private',source:'local',uploadedBy:owner.user.id,public:false}])await store.put('tracks',track.id,{title:'Original Test',artist:'Wave Tests',duration:10,...track});
  const preview='/tracks/external/lyrics/genius/preview',save='/tracks/external/lyrics/genius';
  assert.equal((await req(preview,null,{url})).status,401);assert.equal((await req('/tracks/private/lyrics/genius/preview',viewer.token,{url})).status,404);assert.equal(calls,0);
  const invalid=await req(preview,owner.token,{url:'https://evil.test/test-lyrics'});assert.equal(invalid.status,400);assert.match(invalid.data.error.message,/HTTPS Genius/);assert.equal(calls,0);
  assert.equal((await req(preview,owner.token,{url})).data.source,'genius');assert.deepEqual(await store.list('lyrics'),[]);
  assert.equal((await req(save,owner.token,{url})).status,200);assert.equal(calls,1);assert.equal((await store.get('lyrics',owner.user.id+':external')).sourceUrl,url);assert.equal(await store.get('lyrics','external'),null);assert.equal(await store.get('lyrics',viewer.user.id+':external'),null);
  assert.equal((await req('/tracks/local/lyrics/genius',viewer.token,{url})).status,404);
  await store.put('rooms','lyrics-test-room',{id:'lyrics-test-room',members:[{userId:viewer.user.id}],state:{trackId:'local',queue:['local']}});
  assert.equal((await req('/tracks/local/lyrics/genius',viewer.token,{url})).status,403);assert.equal((await req('/tracks/local/lyrics/genius',owner.token,{url})).status,200);assert.equal((await store.get('lyrics','local')).source,'genius');
  assert.equal((await req('/tracks/external/lyrics',owner.token,{text:'My original edited line'},'PUT')).status,200);
  failed=true;const result=await req(save,owner.token,{url:'https://genius.com/Unavailable-test-lyrics'});assert.equal(result.status,502);assert.match(result.data.error.message,/unavailable/);assert.equal((await store.get('lyrics',owner.user.id+':external')).source,'user');
  failed=false;let release;hold=new Promise(resolve=>{release=resolve;});const fetching=new Promise(resolve=>{started=resolve;});
  const pending=req(save,owner.token,{url:'https://genius.com/Pending-test-lyrics'});await fetching;assert.equal((await req('/auth/logout',owner.token,{})).status,200);release();
  assert.equal((await pending).status,401);assert.equal((await store.get('lyrics',owner.user.id+':external')).raw,undefined);assert.equal((await store.get('lyrics',owner.user.id+':external')).lines[0].text,'My original edited line');
 }finally{await service.close();assert(directory.startsWith(qa+path.sep));await fs.rm(directory,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
});
