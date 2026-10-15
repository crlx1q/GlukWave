import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {visibleLikes,accountAddedDates} from '../src/library.js';
import {createApp} from '../src/app.js';
import {config} from '../src/config.js';

test('likes use personal dates, stable reverse insertion ties and private metadata filtering',()=>{
  const entry={likedIds:['old','legacy1','hidden','new','batch1','batch2','legacy2','old'],likedAt:{old:'2024-01-01T00:00:00.000Z',hidden:'2026-10-15T00:00:00.000Z',new:'2026-10-12T00:00:00.000Z',batch1:'2026-10-11T00:00:00.000Z',batch2:'2026-10-11T00:00:00.000Z',legacy1:'invalid',stray:'2026-10-16T00:00:00.000Z'}};
  const result=visibleLikes(entry,new Set(['old','new','batch1','batch2','legacy1','legacy2','stray']));
  assert.deepEqual(result.likedIds,['new','batch2','batch1','old','legacy2','legacy1']);
  assert.deepEqual(Object.keys(result.likedAt).sort(),['batch1','batch2','new','old']);
  assert.deepEqual(entry.likedIds.slice(0,2),['old','legacy1']);
  assert.deepEqual(visibleLikes({likedIds:['a','b','c']},new Set(['a','b','c'])),{likedIds:['c','b','a'],likedAt:{}});
});

test('account addition dates never use another account catalog discovery or hidden memberships',()=>{
  const result=accountAddedDates({addedAt:{a:'2025-01-01T00:00:00Z',hidden:'2026-01-01T00:00:00Z'},likedIds:['a','b'],likedAt:{a:'2026-01-01T00:00:00Z',b:'2026-02-01T00:00:00Z'}},[{trackIds:['c','a'],trackAddedAt:{c:'2026-03-01T00:00:00Z',a:'2025-02-01T00:00:00Z',stray:'2026-04-01T00:00:00Z'}}],[{id:'a',uploadedBy:'someone-else',createdAt:'2020-01-01T00:00:00Z'},{id:'b'},{id:'c'},{id:'own',uploadedBy:'owner',createdAt:'2024-01-01T00:00:00Z'},{id:'legacy',uploadedBy:'someone-else',createdAt:'2020-01-01T00:00:00Z'}],'owner');
  assert.deepEqual(result,{a:'2025-01-01T00:00:00Z',b:'2026-02-01T00:00:00Z',c:'2026-03-01T00:00:00Z',own:'2024-01-01T00:00:00Z'});
});

test('real library API preserves repeated likes, orders dates independently of catalog, and resets only after re-like',async()=>{
  const qaRoot=path.resolve(config.root,'work/qa');await fs.mkdir(qaRoot,{recursive:true});
  const directory=await fs.mkdtemp(path.join(qaRoot,'library25-server-'));
  const service=await createApp({...config,env:'test',production:false,storage:'sqlite',objectStorage:'local',dataDir:directory,releasesDir:directory,emailVerify:false,turnstileSecret:'',smtp:'',soundcloudPublicSearch:false},{log:pino({level:'silent'})});
  await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}/api`;
  const request=async(route,token,method='GET',body)=>{const response=await fetch(base+route,{method,headers:{'X-GlukWave-Client':'native',...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,data:await response.json()};};
  try{
    const owner=(await request('/auth/register',null,'POST',{email:'library25@qa.test',username:'library25',password:'Fixture-password-2026'})).data;
    for(const id of ['new','legacy','old','hidden'])await service.ctx.store.create('tracks',id,{id,title:id,artist:'Original',source:id==='hidden'?'local':'soundcloud',sourceUrl:'https://soundcloud.com/fixture/'+id,public:id!=='hidden',uploadedBy:'someone-else',duration:180,createdAt:'2020-01-01T00:00:00.000Z'});
    await service.ctx.store.put('libraries',owner.user.id,{id:owner.user.id,likedIds:['legacy','old','hidden','new'],likedAt:{old:'2024-01-01T00:00:00.000Z',new:'2026-01-01T00:00:00.000Z',hidden:'2026-12-01T00:00:00.000Z'},history:[]});
    const first=await request('/library',owner.token);assert.equal(first.status,200);assert.deepEqual(first.data.likedIds,['new','old','legacy']);assert.equal('hidden' in first.data.likedAt,false);
    const repeated=await request('/library/likes/old',owner.token,'PUT',{liked:true});assert.equal(repeated.status,200);assert.equal(repeated.data.likedAt,'2024-01-01T00:00:00.000Z');
    assert.deepEqual((await request('/library',owner.token)).data.likedIds,['new','old','legacy']);
    const unlike=await request('/library/likes/old',owner.token,'PUT',{liked:false});assert.equal(unlike.data.likedAt,null);
    assert.equal((await service.ctx.store.get('libraries',owner.user.id)).likedAt.old,undefined);
    const relike=await request('/library/likes/old',owner.token,'PUT',{liked:true});assert(Number.isFinite(Date.parse(relike.data.likedAt)));
    assert.deepEqual((await request('/library',owner.token)).data.likedIds,['old','new','legacy']);
    const legacy=await request('/library/likes/legacy',owner.token,'PUT',{liked:true});assert.equal(legacy.data.likedAt,null);
    const created=await request('/playlists',owner.token,'POST',{name:'Dates',trackIds:['old','new']});assert.equal(created.status,201);
    const playlist=created.data.playlist,originalDates=playlist.trackAddedAt;
    assert(originalDates.old);assert.equal(originalDates.old,originalDates.new);
    const reordered=await request(`/playlists/${playlist.id}`,owner.token,'PATCH',{trackIds:['new','old']});assert.deepEqual(reordered.data.playlist.trackAddedAt,originalDates);
    const repeatedMembership=await request(`/playlists/${playlist.id}/tracks/old`,owner.token,'PUT',{present:true});assert.deepEqual(repeatedMembership.data.playlist.trackAddedAt,originalDates);
    const removed=await request(`/playlists/${playlist.id}/tracks/old`,owner.token,'PUT',{present:false});assert.equal(removed.data.playlist.trackAddedAt.old,undefined);
    const added=await request(`/playlists/${playlist.id}/tracks/legacy`,owner.token,'PUT',{present:true});assert(added.data.playlist.trackAddedAt.legacy);
    const library=await request('/library',owner.token);assert.equal(library.data.addedAt.legacy,added.data.playlist.trackAddedAt.legacy);
    const beforeFirstPlay=library.data.addedAt.new;
    await request('/history',owner.token,'POST',{trackId:'new',position:1});
    assert.equal((await request('/library',owner.token)).data.addedAt.new,beforeFirstPlay);
    await service.ctx.store.update('libraries',owner.user.id,value=>({...value,history:Array.from({length:100},(_,i)=>({trackId:'heard-'+i,playedAt:'2025-01-01T00:00:00Z'})),addedAt:{...value.addedAt,stale:'2020-01-01T00:00:00Z',...Object.fromEntries(Array.from({length:100},(_,i)=>['heard-'+i,'2025-01-01T00:00:00Z']))}}));
    await request('/history',owner.token,'POST',{trackId:'new',position:2});
    const bounded=await service.ctx.store.get('libraries',owner.user.id);
    assert.equal(bounded.history.length,100);assert.equal(bounded.addedAt.stale,undefined);assert.equal(bounded.addedAt['heard-99'],undefined);assert(Object.keys(bounded.addedAt).length<=103);
    assert.equal((await request('/library')).status,401);
  }finally{
    await service.close();assert(directory.startsWith(qaRoot+path.sep));await fs.rm(directory,{recursive:true,force:true,maxRetries:5,retryDelay:200});
  }
});
