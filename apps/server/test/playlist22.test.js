import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {createApp} from '../src/app.js';
import {config} from '../src/config.js';

test('atomic playlist membership retains concurrent additions, is idempotent, and enforces owner/public access',async()=>{
  const directory=await fs.mkdtemp(path.join(config.root,'work/qa/playlist22-server-'));
  const service=await createApp({...config,env:'test',production:false,storage:'sqlite',objectStorage:'local',dataDir:directory,releasesDir:directory,emailVerify:false,turnstileSecret:'',smtp:'',soundcloudPublicSearch:false},{log:pino({level:'silent'})});
  await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}/api`;
  const request=async(route,token,method='GET',body)=>{const response=await fetch(base+route,{method,headers:{'X-GlukWave-Client':'native',...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,data:await response.json()};};
  try{
    const owner=(await request('/auth/register',null,'POST',{email:'playlist22@qa.test',username:'playlist22',password:'Fixture-password-2026'})).data;
    const guest=(await request('/auth/register',null,'POST',{email:'playlist22-guest@qa.test',username:'playlist22guest',password:'Fixture-password-2026'})).data;
    const tracks=Array.from({length:120},(_,index)=>({id:'playlist22-'+index,title:'Song '+index,artist:'Original',source:index===119?'local':'soundcloud',sourceUrl:'https://soundcloud.com/fixture/song-'+index,playback:{kind:'soundcloud'},public:index!==119,uploadedBy:owner.user.id,artwork:'/fixture-cover.jpg',duration:180,createdAt:new Date().toISOString()}));
    for(const track of tracks)await service.ctx.store.create('tracks',track.id,track);
    const created=await request('/playlists',owner.token,'POST',{name:'Collection',public:true});assert.equal(created.status,201);const id=created.data.playlist.id;
    const writes=await Promise.all(tracks.slice(0,12).map(track=>request(`/playlists/${id}/tracks/${track.id}`,owner.token,'PUT',{present:true})));
    assert(writes.every(value=>value.status===200),JSON.stringify(writes));assert.equal((await service.ctx.store.get('playlists',id)).trackIds.length,12);
    assert.equal((await request(`/playlists/${id}/tracks/${tracks[0].id}`,owner.token,'PUT',{present:true})).data.playlist.trackIds.length,12);
    assert.equal((await request(`/playlists/${id}/tracks/${tracks[0].id}`,guest.token,'PUT',{present:false})).status,404);
    assert.equal((await request(`/playlists/${id}/tracks/${tracks[119].id}`,owner.token,'PUT',{present:true})).status,403);
    assert.equal((await request(`/playlists/${id}/tracks/${tracks[0].id}`,owner.token,'PUT',{present:false})).data.playlist.trackIds.length,11);
    assert.equal((await request(`/playlists/${id}/tracks/${tracks[0].id}`,owner.token,'PUT',{present:false})).data.playlist.trackIds.length,11);
    // A different worker may change visibility or membership after the initial
    // lookup. Revalidate the actual compare-and-set document on every attempt.
    const race=(await request('/playlists',owner.token,'POST',{name:'Race'})).data.playlist.id;
    const originalUpdate=service.ctx.store.update;
    let injected=false;
    service.ctx.store.update=async(collection,key,fn)=>{
      if(collection==='playlists'&&key===race&&!injected){injected=true;await originalUpdate(collection,key,value=>({...value,public:true}));}
      return originalUpdate(collection,key,fn);
    };
    assert.equal((await request(`/playlists/${race}/tracks/${tracks[119].id}`,owner.token,'PUT',{present:true})).status,403);
    service.ctx.store.update=originalUpdate;
    await originalUpdate('playlists',race,value=>({...value,public:false}));injected=false;
    service.ctx.store.update=async(collection,key,fn)=>{
      if(collection==='playlists'&&key===race&&!injected){injected=true;await originalUpdate(collection,key,value=>({...value,trackIds:[tracks[119].id]}));}
      return originalUpdate(collection,key,fn);
    };
    assert.equal((await request(`/playlists/${race}`,owner.token,'PATCH',{public:true})).status,403);
    service.ctx.store.update=originalUpdate;
    assert.equal((await service.ctx.store.get('playlists',race)).public,false);
    const all=await request('/playlists',owner.token,'POST',{name:'Large',trackIds:tracks.map(track=>track.id)});assert.equal(all.status,201);assert.deepEqual(all.data.playlist.coverArtworks,['/fixture-cover.jpg']);
    // Library already loads all its tracks. Collage decoration must reuse that
    // snapshot, rather than issuing one get() per song for every playlist.
    const original=service.ctx.store.get;let trackReads=0;
    service.ctx.store.get=async(collection,...args)=>{if(collection==='tracks')trackReads++;return original(collection,...args);};
    const library=await request('/library',owner.token);assert.equal(library.status,200);assert.equal(library.data.tracks.length,120);assert.equal(trackReads,0);
    const liked=await request(`/library/likes/${tracks[0].id}`,owner.token,'PUT',{liked:true});assert.equal(liked.status,200);
    assert((await service.ctx.store.get('libraries',owner.user.id)).likedIds.includes(tracks[0].id));
  }finally{await service.close();await fs.rm(directory,{recursive:true,force:true,maxRetries:5,retryDelay:200});}
});
