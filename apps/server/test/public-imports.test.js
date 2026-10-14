import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {createApp} from '../src/app.js';
import {config} from '../src/config.js';
import {publicImportTarget,parseSpotifyPublic,createPublicImports} from '../src/public-imports.js';
import {createPublicSoundcloud} from '../src/soundcloud-public.js';
import {normalizeSoundcloud} from '../src/providers.js';

const sid='a'.repeat(22),client='b'.repeat(32);
const spotify=(items=[{uri:'spotify:track:'+sid,title:'Original song',subtitle:'Artist',duration:180000}],total=1)=>`<script id="__NEXT_DATA__">${JSON.stringify({props:{pageProps:{state:{data:{entity:{type:'playlist',id:sid,title:'Quiet collection',coverArt:{sources:[{url:'https://i.scdn.co/cover.jpg'}]},trackList:items,...(total==null?{}:{trackCount:total})}}}}}})}</script>`;
const ytrack=id=>({id:String(id),title:'Song '+id,artists:[{name:'Artist '+id}],albums:[{id:55,title:'Album',genre:'ambient'}],coverUri:'avatars.yandex.net/cover/%%',durationMs:120000,available:true});
const strack=id=>({id,urn:'soundcloud:tracks:'+id,kind:'track',sharing:'public',title:'Song '+id,user:{username:'Original'},duration:180000,permalink_url:'https://soundcloud.com/fixture/song-'+id});
function fixtureFetch(seen=[]){return async(input,options={})=>{
  const u=new URL(input);seen.push(u.href);assert(!options.headers?.Authorization,'Public readers do not send OAuth credentials');
  if(u.hostname==='open.spotify.com')return new Response(spotify(),{headers:{'Content-Type':'text/html'}});
  if(u.hostname==='api.music.yandex.net'){
    if(u.pathname.endsWith('/playlists/list'))return Response.json({result:[{kind:1,title:'Public',trackCount:101,visibility:'public'},{kind:2,title:'Private',visibility:'private'}]});
    if(u.pathname.endsWith('/likes/tracks'))return Response.json({result:{library:{tracks:[{id:'7',albumId:'55'}]}}});
    if(u.pathname.endsWith('/playlists/1'))return Response.json({result:{title:'Public',visibility:'public',tracks:Array.from({length:101},(_,i)=>({id:String(i+1),albumId:'55'}))}});
    if(u.pathname==='/tracks')return Response.json({result:new URLSearchParams(options.body).get('track-ids').split(',').map(ytrack)});
  }
  if(u.hostname==='soundcloud.com'){
    const entity=u.pathname.includes('/sets/')?{kind:'playlist',id:9,sharing:'public',title:'Public set',track_count:2,permalink_url:'https://soundcloud.com/fixture/sets/public',tracks:[strack(1),{id:2}]}:{kind:'user',id:4,likes_count:2};
    return new Response(`<script>window.__sc_hydration = ${JSON.stringify([{hydratable:'apiClient',data:{id:client}},{hydratable:'data',data:entity}])};</script>`,{headers:{'Content-Type':'text/html'}});
  }
  if(u.hostname==='api-v2.soundcloud.com'){
    assert.equal(u.searchParams.get('client_id'),client);
    if(u.pathname==='/users/4/playlists')return Response.json({collection:[{kind:'playlist',id:9,sharing:'public',title:'Public set',track_count:2,permalink_url:'https://soundcloud.com/fixture/sets/public'},{kind:'playlist',sharing:'private',title:'Secret'}]});
    if(u.pathname==='/tracks')return Response.json([strack(2)]);
    if(u.pathname==='/users/4/likes')return Response.json({collection:[{track:strack(u.searchParams.get('cursor')?'2':'1')}],next_href:u.searchParams.get('cursor')?null:'https://api-v2.soundcloud.com/users/4/likes?cursor=next&client_id='+client});
  }
  throw Error('Unexpected fixture URL: '+u.href);
};}

test('public collection targets canonicalize nicknames and exact provider links, rejecting SSRF and track URLs',()=>{
  assert.equal(publicImportTarget('spotify','person').url,'https://open.spotify.com/user/person');
  assert.equal(publicImportTarget('yandex','https://music.yandex.kz/users/name/playlists/12?utm=test').url,'https://music.yandex.ru/users/name/playlists/12');
  assert.equal(publicImportTarget('soundcloud','https://www.soundcloud.com/name/sets').kind,'profile');
  assert.equal(publicImportTarget('youtube','@name').url,'https://www.youtube.com/@name/playlists');
  assert.equal(publicImportTarget('youtube','https://music.youtube.com/watch?v=abcdefghijk&list=PLabcdefghijk').url,'https://www.youtube.com/playlist?list=PLabcdefghijk');
  for(const input of ['http://open.spotify.com/user/a','https://open.spotify.com.evil.test/user/a','https://x@open.spotify.com/user/a','https://open.spotify.com:444/user/a','https://127.0.0.1/user/a','https://open.spotify.com/user/a%2fb','https://open.spotify.com/track/'+sid,'file:///etc/passwd'])assert.throws(()=>publicImportTarget('spotify',input));
});
test('Spotify public JSON is metadata-only, normalizes durations and reports incomplete embed data honestly',()=>{
  const target=publicImportTarget('spotify','https://open.spotify.com/playlist/'+sid),value=parseSpotifyPublic(spotify(undefined,null),target);
  assert.equal(value.tracks[0].id,'spotify-'+sid);assert.equal(value.tracks[0].duration,180);assert.equal(value.tracks[0].playback.embedUrl,undefined);assert(value.partial);assert.deepEqual(value.warnings,['PUBLIC_SOURCE_PARTIAL']);
  const profile=parseSpotifyPublic(`<script id="__NEXT_DATA__">${JSON.stringify({playlists:[{type:'playlist',uri:'spotify:playlist:'+sid,name:'Visible'}]})}</script>`,publicImportTarget('spotify','person'));
  assert.equal(profile.playlists[0].name,'Visible');assert.equal(profile.playlists[0].sourceUrl,target.url);
});
test('Yandex public playlists and likes hydrate in batches, retain one snapshot across pages, and omit private collections',async()=>{
  const seen=[],service=createPublicImports({persistTracks:async tracks=>tracks},{fetcher:fixtureFetch(seen)});
  try{const found=await service.search('yandex','fixture');assert.equal(found.playlists.length,1);assert(found.liked);
    const first=await service.tracks('yandex',found.playlists[0].sourceUrl),second=await service.tracks('yandex',found.playlists[0].sourceUrl,first.nextCursor);
    assert.equal(first.tracks.length,100);assert.equal(second.tracks.length,1);assert.equal(second.tracks[0].sourceUrl,'https://music.yandex.ru/album/55/track/101');assert.equal(first.tracks[0].duration,120);assert.equal(second.nextCursor,null);
    assert.equal(seen.filter(u=>new URL(u).pathname.endsWith('/playlists/1')).length,1);assert.equal(seen.filter(u=>new URL(u).pathname==='/tracks').length,2);
  }finally{service.close();}
});
test('SoundCloud public module discovers sets/likes, hydrates sparse metadata and keeps cursor credentials server-side',async()=>{
  const seen=[],fetcher=fixtureFetch(seen),soundcloud=createPublicSoundcloud({fetcher}),service=createPublicImports({persistTracks:async tracks=>tracks},{fetcher,soundcloud,normalizeSoundcloud});
  try{const found=await service.search('soundcloud','fixture');assert.equal(found.playlists.length,1);assert.equal(found.liked.kind,'likes');
    const set=await service.tracks('soundcloud',found.playlists[0].sourceUrl);assert.equal(set.tracks.length,2);assert.equal(set.tracks[1].id,'soundcloud-soundcloud:tracks:2');assert.equal(set.tracks[1].playback.embedUrl,undefined);
    const one=await service.tracks('soundcloud',found.liked.sourceUrl);assert(one.nextCursor);assert(!Buffer.from(one.nextCursor.slice(3),'base64url').toString().includes(client));
    const two=await service.tracks('soundcloud',found.liked.sourceUrl,one.nextCursor);assert.equal(two.tracks[0].sourceId,'soundcloud:tracks:2');assert.equal(two.nextCursor,null);assert.equal(two.partial,false);
    const bad='sc:'+Buffer.from(JSON.stringify({route:'https://127.0.0.1/secret',offset:1})).toString('base64url');await assert.rejects(service.tracks('soundcloud',found.liked.sourceUrl,bad));
  }finally{service.close();}
});
test('public readers reject external redirects, cap responses, classify timeouts and bound parallel work',async()=>{
  const ctx={persistTracks:async tracks=>tracks},url='https://open.spotify.com/playlist/'+sid;
  for(const [fetcher,code] of [[async()=>new Response(null,{status:302,headers:{Location:'https://127.0.0.1/secret'}}),'PUBLIC_IMPORT_REDIRECT'],[async()=>new Response('',{headers:{'Content-Length':String(5*1024*1024)}}),'PUBLIC_IMPORT_TOO_LARGE'],[async()=>{throw new DOMException('timeout','TimeoutError');},'PUBLIC_IMPORT_TIMEOUT']]){const s=createPublicImports(ctx,{fetcher});try{await assert.rejects(s.search('spotify',url),{code});}finally{s.close();}}
  const releases=[],s=createPublicImports(ctx,{fetcher:()=>new Promise(resolve=>releases.push(()=>resolve(new Response(spotify()))))});
  const first=s.search('spotify',url),same=s.search('spotify',url),other=s.search('spotify',url.replace(sid,'c'.repeat(22)));
  await assert.rejects(s.search('spotify',url.replace(sid,'d'.repeat(22))),{code:'PUBLIC_IMPORT_BUSY'});releases.forEach(resolve=>resolve());
  const results=await Promise.allSettled([first,same,other]);assert.equal(results[0].status,'fulfilled');assert.equal(results[1].status,'fulfilled');assert.equal(releases.length,2);s.close();
});
test('YouTube flat pages keep normalized IDs, skip private videos, and discover public channel playlists',async()=>{
  const calls=[],items=Array.from({length:101},(_,i)=>({id:'v'+String(i).padStart(10,'0'),title:i===5?'[Private video]':'Song '+i,channel:'Artist',duration:100}));
  const s=createPublicImports({persistTracks:async tracks=>tracks,extractorPublicPlaylist:async request=>{calls.push(request);return request.url.includes('@')?{entries:[{id:'PLabcdefghijk',title:'Channel playlist',url:'https://www.youtube.com/playlist?list=PLabcdefghijk'}]}:{playlist_count:101,entries:items.slice(request.start-1,request.start-1+request.limit)};}});
  try{const found=await s.search('youtube','@creator');assert.equal(found.playlists.length,1);
    const first=await s.tracks('youtube',found.playlists[0].sourceUrl);assert.equal(first.tracks.length,99);assert.equal(first.nextCursor,'100');assert(first.partial);
    const last=await s.tracks('youtube',found.playlists[0].sourceUrl,first.nextCursor);assert.equal(last.tracks.length,1);assert.equal(last.tracks[0].id,'youtube-v0000000100');assert.equal(last.nextCursor,null);assert.equal(last.partial,false);
    assert(calls.every(r=>r.limit===101));await assert.rejects(s.tracks('youtube',found.playlists[0].sourceUrl,'10001'),{code:'INVALID_CURSOR'});
  }finally{s.close();}
});
test('Yandex closed likes are omitted from discovery and cannot be imported',async()=>{
  const s=createPublicImports({persistTracks:async tracks=>tracks},{fetcher:async input=>Response.json({result:new URL(input).pathname.endsWith('/playlists/list')?[]:{library:{visibility:'private',tracks:[{id:'1'}]}}})});
  try{const found=await s.search('yandex','fixture');assert.equal(found.liked,undefined);await assert.rejects(s.tracks('yandex','https://music.yandex.ru/users/fixture/likes'),{code:'PUBLIC_COLLECTION_UNAVAILABLE'});}finally{s.close();}
});
test('public HTTP import needs no provider keys, preserves auth/plans/idempotency, imports chosen IDs and seeds taste',async()=>{
  const directory=await fs.mkdtemp(path.join(config.root,'work/qa/public-import-server-'));
  const extracted=[];
  const service=await createApp({...config,env:'test',production:false,storage:'sqlite',objectStorage:'local',dataDir:directory,releasesDir:directory,emailVerify:false,turnstileSecret:'',smtp:'',spotify:{id:'',secret:''},soundcloud:{id:'',secret:''},youtubeKey:''},{log:pino({level:'silent'}),publicImportFetch:fixtureFetch(),extractors:{run:async(_,request)=>{assert.equal(request.action,'public-playlist');extracted.push(request);return {title:'Public videos',playlist_count:2,entries:[{id:'abcdefghijk',title:'First',uploader:'Artist',duration:180},{id:'lmnopqrstuv',title:'Second',uploader:'Another',duration:120}]};}}});
  await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}/api`;
  const request=async(route,token,body,headers={})=>{const r=await fetch(base+route,{method:'POST',headers:{'X-GlukWave-Client':'native',...(token?{Authorization:'Bearer '+token}:{}),'Content-Type':'application/json',...headers},body:JSON.stringify(body)});return {status:r.status,data:await r.json()};};
  try{
    assert.equal((await request('/public-import/search',null,{provider:'spotify',query:'person'})).status,401);
    const account=(await request('/auth/register',null,{email:'public-import@qa.test',username:'publicimport',password:'Fixture-password-2026'})).data;
    const body={playlistId:'public-list',publicSourceUrl:'https://www.youtube.com/playlist?list=PLabcdefghijk',destination:'likes',trackIds:['youtube-abcdefghijk'],requestId:'public-import-intent'};
    assert.equal((await request('/integrations/youtube/import',account.token,body)).status,403);await service.ctx.store.update('users',account.user.id,u=>({...u,plan:'beta'}));
    for(const provider of ['spotify','yandex','soundcloud','youtube']){
      const query=provider==='spotify'?'https://open.spotify.com/playlist/'+sid:provider==='youtube'?body.publicSourceUrl:'fixture';
      const found=await request('/public-import/search',account.token,{provider,query});assert.equal(found.status,200,JSON.stringify(found.data));assert(found.data.playlists.length);
      const page=await request('/public-import/tracks',account.token,{provider,sourceUrl:found.data.playlists[0].sourceUrl});assert.equal(page.status,200,JSON.stringify(page.data));assert(page.data.tracks.length);assert(page.data.tracks.every(t=>t.id.startsWith(provider+'-')&&t.sourceUrl&&t.playback.kind===provider&&!t.playback.embedUrl));
    }
    const first=await request('/integrations/youtube/import',account.token,body),repeat=await request('/integrations/youtube/import',account.token,body);assert.equal(first.status,201);assert.equal(first.data.imported,1);assert.deepEqual(first.data,repeat.data);
    const dedupe=await request('/integrations/youtube/import',account.token,{...body,requestId:'public-import-another'});assert.equal(dedupe.data.imported,0);assert.equal(dedupe.data.deduplicated,1);
    const library=await service.ctx.store.get('libraries',account.user.id);assert.deepEqual(library.likedIds,['youtube-abcdefghijk']);assert.deepEqual((await service.ctx.store.get('taste',account.user.id)).importedTrackIds,['youtube-abcdefghijk']);
    const saved=await request('/integrations/spotify/import',account.token,{playlistId:'public-spotify',publicSourceUrl:'https://open.spotify.com/playlist/'+sid,destination:'playlist',name:'Original title',requestId:'public-spotify-create'});assert.equal(saved.status,201);assert.equal(saved.data.playlist.name,'Original title');
    assert.equal((await request('/integrations/youtube/import',account.token,body,{'X-GlukWave-Account':'different'})).status,409);assert(extracted.every(r=>r.limit===101&&r.start===1));
  }finally{await service.close();await fs.rm(directory,{recursive:true,force:true,maxRetries:5,retryDelay:200});}
});
