import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {createApp} from '../src/app.js';
import {config} from '../src/config.js';
import {unseal} from '../src/util.js';

test('personal tokens prove permissions, remain encrypted, and private Yandex collections use shared idempotent import',async()=>{
  const directory=await fs.mkdtemp(path.join(config.root,'work/qa/personal27-'));
  const calls=[],sid='a'.repeat(22),personalToken='personal-fixture-credential-not-live';
  let denied=false;
  const fetcher=async(input,options)=>{
    const url=new URL(input);calls.push({host:url.hostname,path:url.pathname,authorization:options.headers.Authorization});
    assert.equal(options.redirect,'error');assert(options.signal);
    if(denied)return new Response('',{status:403});
    if(url.hostname==='api.spotify.com'){
      if(url.pathname.endsWith('/me'))return Response.json({id:'fixture',display_name:'Spotify fixture'});
      if(url.pathname.endsWith('/me/tracks'))return Response.json({items:[],total:5});
      if(url.pathname.endsWith('/me/playlists'))return Response.json({items:[],total:2});
    }
    if(url.hostname==='api.music.yandex.net'){
      if(url.pathname==='/account/status')return Response.json({result:{account:{uid:123,login:'fixture'}}});
      if(url.pathname.endsWith('/playlists/list'))return Response.json({result:[{kind:9,title:'Private collection',trackCount:1}]});
      if(url.pathname.endsWith('/likes/tracks'))return Response.json({result:{library:{visibility:'private',tracks:[{id:'42',albumId:7}]}}});
      if(url.pathname==='/tracks')return Response.json({result:[{id:42,title:'Private favourite',artists:[{name:'Artist'}],albums:[{id:7,title:'Album',genre:'ambient'}],durationMs:180000}]});
    }
    throw Error('Unexpected personal fixture route');
  };
  const service=await createApp({...config,env:'test',production:false,storage:'sqlite',objectStorage:'local',dataDir:directory,releasesDir:directory,emailVerify:false,turnstileSecret:'',smtp:'',spotify:{id:'',secret:''},youtubeKey:'',soundcloudPublicSearch:false,extractors:{...config.extractors,enabled:false}},
    {log:pino({level:'silent'}),personalImportFetch:fetcher});
  await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}/api`;
  const call=async(route,token,body,method)=>{
    const response=await fetch(base+route,{method:method||(body?'POST':'GET'),headers:{'X-GlukWave-Client':'native','Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,body:await response.json()};
  };
  try{
    const signup=(await call('/auth/register',null,{email:'personal@qa.test',username:'personal_qa',password:'Fixture-password-2026'})).body;
    assert.equal((await call('/auth/login',null,{email:'@personal_qa',password:'Fixture-password-2026'})).status,200);
    assert.equal((await call('/public-import/spotify/token',null,{accessToken:personalToken})).status,401);
    assert.equal((await call('/public-import/spotify/token',signup.token,{accessToken:personalToken})).status,403);
    await service.ctx.store.update('users',signup.user.id,user=>({...user,plan:'beta'}));
    const spotify=await call('/public-import/spotify/token',signup.token,{accessToken:personalToken});
    assert.equal(spotify.status,200);assert.equal(spotify.body.connection.discoveredTracks,5);
    assert.equal(JSON.stringify(spotify.body).includes(personalToken),false);
    const saved=await service.ctx.store.get('connections',`${signup.user.id}:spotify`);
    assert.equal(saved.token.includes(personalToken),false);assert.equal(unseal(saved.token,config.encryptionKey).access_token,personalToken);
    denied=true;assert.equal((await call('/public-import/spotify/token',signup.token,{accessToken:'another-fixture-token'})).status,403);
    assert.equal((await service.ctx.store.get('connections',saved.id)).token,saved.token);denied=false;
    assert.equal((await call('/integrations/yandex/token',signup.token,{accessToken:personalToken})).status,200);
    const lists=await call('/integrations/yandex/playlists',signup.token);assert.equal(lists.body.liked.trackCount,1);assert.equal(lists.body.playlists[0].name,'Private collection');
    const tracks=await call('/integrations/yandex/playlists/liked/tracks',signup.token);
    assert.equal(tracks.status,200);assert.equal(tracks.body.tracks.length,1);
    const track=tracks.body.tracks[0];assert.equal(track.public,false);assert.equal(track.uploadedBy,signup.user.id);
    const importBody={playlistId:'liked',destination:'likes',trackIds:[track.id],requestId:'private-likes-fixture'};
    const imported=await call('/integrations/yandex/import',signup.token,importBody);assert.equal(imported.status,201);assert.equal(imported.body.imported,1);assert.equal(imported.body.tasteSeeded,true);
    assert.equal((await call('/integrations/yandex/import',signup.token,importBody)).body.imported,1);
    assert((await service.ctx.store.get('taste',signup.user.id)).importedTrackIds.includes(track.id));
    const connections=await call('/integrations',signup.token);assert(connections.body.connections.find(x=>x.provider==='yandex').importAvailable);
    assert.equal(JSON.stringify(connections.body).includes(personalToken),false);
    const playlist=(await call('/playlists',signup.token,{name:'Pinned private music',trackIds:[track.id]})).body.playlist;
    const pins=[{id:'liked',type:'likes'},{id:'mine',type:'playlist',playlistId:playlist.id},{id:'genre',type:'mix',genre:'Ambient',mood:'calm'}];
    const settings=await call('/settings',signup.token,{homePins:pins},'PATCH');assert.equal(settings.status,200);assert.equal(settings.body.settings.homePins[2].genre,'ambient');
    assert.equal((await call('/settings',signup.token,{homePins:[{id:'foreign',type:'playlist',playlistId:'missing'}]},'PATCH')).status,403);
    assert.equal((await call('/settings',signup.token,{homePins:[{id:'same',type:'likes'},{id:'same',type:'likes'}]},'PATCH')).status,400);
    const mix=await call('/recommendations?genre=ambient&mix=evening&day=2026-10-18&limit=4',signup.token);assert.equal(mix.status,200);assert.equal(mix.body.mood,'calm');assert(mix.body.tracks.some(x=>x.id===track.id));
    const excluded=await call('/recommendations/exclude',signup.token,{trackId:track.id,artist:true});assert.equal(excluded.status,200);assert(excluded.body.taste.excludedArtistNames.includes('artist'));
    assert.equal((await call('/recommendations?genre=ambient&limit=4',signup.token)).body.tracks.length,0);
    await call('/recommendations/exclude',signup.token,{trackId:track.id,artist:true,remove:true});assert((await call('/recommendations?genre=ambient&limit=4',signup.token)).body.tracks.some(x=>x.id===track.id));
    assert(calls.every(x=>['api.music.yandex.net','api.spotify.com'].includes(x.host)));
  }finally{await service.close();assert(directory.startsWith(path.join(config.root,'work/qa')+path.sep));await fs.rm(directory,{recursive:true,force:true,maxRetries:8,retryDelay:150});}
});
