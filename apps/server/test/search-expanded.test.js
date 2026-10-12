import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {config as defaults} from '../src/config.js';
import {createApp} from '../src/app.js';
import {normalizeSoundcloud} from '../src/providers.js';
import {createLyricsProvider,lyricsMetadata} from '../src/lrclib.js';

test('Search finds artist, genre and personal lyric words without leaking them',async()=>{
 const dir=await fs.mkdtemp(path.join(defaults.root,'work/qa/search-'));
 const service=await createApp({...defaults,env:'test',storage:'sqlite',dataDir:dir,production:false,turnstileSecret:'',soundcloudPublicSearch:false,youtubeKey:'',spotify:{id:'',secret:''},objectStorage:'local',smtp:'',emailVerify:false},{log:pino({level:'silent'})});
 await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));
 const base=`http://127.0.0.1:${service.server.address().port}`;
 const request=async(route,body,token)=>{const response=await fetch(base+'/api'+route,{method:body?'POST':'GET',headers:{'Content-Type':'application/json','X-GlukWave-Client':'native',...(token?{Authorization:'Bearer '+token}:{})},...(body?{body:JSON.stringify(body)}:{})});return response.json();};
 try{
   const owner=await request('/auth/register',{email:'search@example.test',username:'search_owner',password:'long-search-password'});
   const track=normalizeSoundcloud({id:443,title:'Moonlight',genre:'Ambient',tag_list:'"deep house" chill',user:{id:15,username:'Élan',avatar_url:'https://example.test/avatar.png'},permalink_url:'https://soundcloud.com/elan/moonlight'});
   await service.ctx.persistTracks([track]);
   const artist=await request('/search?q=elan');assert.equal(artist.artists[0].name,'Élan');assert.deepEqual(artist.artists[0].trackIds,[track.id]);
   assert.equal((await request('/search?q=ambient')).tracks[0].id,track.id);
   assert.equal((await request('/search?q=deep%20house')).tracks[0].id,track.id);
   await service.ctx.store.put('lyrics',`${owner.user.id}:${track.id}`,{lines:[{time:1,text:'Hidden silver river'}],source:'user'});
   assert.equal((await request('/search?q=silver%20river',null,owner.token)).tracks[0].id,track.id);
   assert.deepEqual((await request('/search?q=silver%20river')).tracks,[]);
   const combined=await request('/search?q=elan%20moonlight');assert.equal(combined.tracks[0].id,track.id);assert.equal(combined.artists[0].name,'Élan');
   const pub=await request('/playlists',{name:'Moonlight collection',trackIds:[track.id],public:true},owner.token);
   const own=await request('/playlists',{name:'Moonlight private',trackIds:[track.id],public:false},owner.token);
   const publicResults=await request('/search?q=moonlight');assert(publicResults.playlists.some(p=>p.id===pub.playlist.id));assert(!publicResults.playlists.some(p=>p.id===own.playlist.id));
   const personal=await request('/search?q=moonlight',null,owner.token);assert(personal.playlists.some(p=>p.id===own.playlist.id));
   await service.ctx.store.put('playlists','invalid-public',{...pub.playlist,id:'invalid-public',trackIds:['missing-private-track']});
   assert(!(await request('/search?q=moonlight',null,owner.token)).playlists.some(p=>p.id==='invalid-public'));
   const challenge=await request('/auth/native',{method:'email'});assert.equal(typeof challenge.expiresAt,'number');
 }finally{await service.close();await fs.rm(dir,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
});

test('Automatic lyrics recover a failed exact request and use the manual title-only fallback',async()=>{
 const cache=new Map(),calls=[];
 const ctx={store:{get:async(c,k)=>cache.get(k),list:async()=>[...cache.values()],put:async(c,k,v)=>cache.set(k,v),remove:async(c,k)=>cache.delete(k)}};
 const record={id:123,trackName:'Example',artistName:'Test Artist',duration:180,syncedLyrics:'[00:03]Verified text',plainLyrics:'Verified text'};
 const provider=createLyricsProvider(ctx,async url=>{
  calls.push(url.href);if(url.pathname.endsWith('/get'))return new Response('',{status:503});
  if(url.searchParams.has('artist_name'))return Response.json([]);
  return Response.json([{...record,id:124,artistName:'Unrelated Artist'},record]);
 });
 const track={title:'Example (Official Audio)',artist:'Test Artist',duration:180,source:'youtube'};
 const result=await provider.lookup(track);assert.equal(result.providerId,123);assert.equal(result.lines[0].time,3);assert.equal(calls.length,3);
 assert.equal((await provider.lookup(track)).providerId,123);assert.equal(calls.length,3);
 assert.equal([...cache.values()][0].providerVersion,3);
});

test('Lyrics normalize video credits, recover album mismatch and keep timing honest',async()=>{
 const cache=new Map();const ctx={store:{get:async(c,k)=>cache.get(k),list:async()=>[...cache.values()],put:async(c,k,v)=>cache.set(k,v),remove:async(c,k)=>cache.delete(k)}};
 const record={id:91,trackName:'Sample Song',artistName:'Sample Artist',duration:123,syncedLyrics:'[00:01.50]Original test line',plainLyrics:'Original test line'};
 const requests=[];
 const provider=createLyricsProvider(ctx,async url=>{requests.push(url.href);if(url.hostname==='api.lyrics.ovh')return Response.json({lyrics:'Plain fallback test line'});return url.pathname.endsWith('/search')?Response.json([record]):new Response('',{status:404});});
 const track={title:'Sample Artist - Sample Song (Official Video)',artist:'Uploader',album:'Wrong album',duration:123,source:'youtube'};
 assert.deepEqual(lyricsMetadata(track),{title:'Sample Song',artist:'Sample Artist'});
 const synced=await provider.lookup(track);assert.equal(synced.source,'lrclib');assert.equal(synced.lines[0].time,1.5);assert.equal(requests.length,2);
 const plain=await provider.lookup({...track,title:'Other Song',artist:'Other Artist'});assert.equal(plain.source,'lyrics-ovh');assert.equal(plain.synchronized,false);assert.equal(plain.lines[0].time,null);
 const remix=await provider.lookup({...track,title:'Sample Song (Remix)',artist:'Sample Artist'});assert.notEqual(remix.source,'lrclib');
 const extended=await provider.lookup({...track,duration:140});assert.equal(extended.source,'lrclib');assert.equal(extended.synchronized,false);assert.equal(extended.lines[0].time,null);
 const feature=await provider.lookup({...track,source:'spotify',title:'Sample Song (feat. Second Singer)',artist:'Sample Artist, Second Singer',artists:[{name:'Sample Artist'},{name:'Second Singer'}]});assert.equal(feature.synchronized,true);
});
