import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {createApp} from '../src/app.js';
import {config} from '../src/config.js';

test('room visibility, short invitations, concurrent participation quotas and profile asset cleanup are enforced',async()=>{
  const qa=path.join(config.root,'work/qa');await fs.mkdir(qa,{recursive:true});const directory=await fs.mkdtemp(path.join(qa,'rooms-profile-'));
  const service=await createApp({...config,env:'test',storage:'sqlite',objectStorage:'local',dataDir:directory,production:false,emailVerify:false,turnstileSecret:'',turnstileSiteKey:'',smtp:'',soundcloudPublicSearch:false},{log:pino({level:'silent'})});
  try{
    await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}`;
    const request=async(route,auth,body,method=body?'POST':'GET')=>{const response=await fetch(base+'/api'+route,{method,headers:{...(auth?{Authorization:`Bearer ${auth.token}`}:{ }),'X-GlukWave-Client':'native',...(body&&!(body instanceof FormData)?{'Content-Type':'application/json'}:{})},...(body?{body:body instanceof FormData?body:JSON.stringify(body)}:{})});return {status:response.status,data:await response.json()};};
    const signup=async username=>(await request('/auth/register',null,{email:username+'@example.test',username,password:'Room-profile-pass-2026'})).data;
    const owner=await signup('owner'),listener=await signup('listener');
    const created=await request('/rooms',owner,{name:'Public evening',visibility:'public'});assert.equal(created.status,201);const room=created.data.room;assert.match(room.inviteCode,/^\d{5}$/);
    assert.equal((await request('/rooms',owner,{name:'Exceeds free limit'})).status,403);
    const directoryResponse=(await request('/rooms',listener)).data;assert.equal(directoryResponse.publicRooms[0].id,room.id);assert.equal(directoryResponse.publicRooms[0].inviteCode,undefined);assert.equal(directoryResponse.publicRooms[0].state,undefined);
    await service.ctx.store.update('users',owner.user.id,user=>({...user,plan:'beta'}));
    const privateRoom=(await request('/rooms',owner,{name:'Private',visibility:'private'})).data.room;assert.match(privateRoom.inviteCode,/^\d{5}$/);assert.notEqual(privateRoom.inviteCode,room.inviteCode);
    assert.equal((await request('/rooms/join',listener,{roomId:privateRoom.id})).status,404);
    const simultaneous=await Promise.all([request('/rooms/join',listener,{roomId:room.id}),request('/rooms/join',listener,{inviteCode:privateRoom.inviteCode})]);assert.equal(simultaneous.filter(result=>result.status===200).length,1);assert.equal(simultaneous.filter(result=>result.status===403).length,1);
    const joined=simultaneous.find(result=>result.status===200).data.room;assert.equal((await request('/rooms/'+joined.id+'/leave',listener,{})).status,200);
    assert.equal((await request('/rooms/join',listener,{inviteCode:privateRoom.inviteCode})).status,200);
    const outsider=await signup('outsider');await service.ctx.store.update('users',owner.user.id,user=>({...user,plan:'free'}));
    await service.ctx.store.update('rooms',room.id,value=>({...value,members:[value.members[0],...Array.from({length:9},(_,index)=>({userId:'fixture-'+index,displayName:'Member',role:'member',canControl:false}))]}));
    assert.equal((await request('/rooms/join',outsider,{roomId:room.id})).data.error.code,'ROOM_FULL');
    const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWZQAAAAASUVORK5CYII=','base64');
    const upload=async kind=>{const form=new FormData();form.append('kind',kind);form.append('file',new Blob([png],{type:'image/png'}),'photo.png');return request('/profile/media',owner,form);};
    const first=(await upload('avatar')).data.user.avatarUrl,firstId=first.split('/').at(-1),firstAsset=await service.ctx.store.get('assets',firstId);assert(firstAsset);await fs.access(path.join(directory,'media',firstAsset.key));
    assert.equal((await upload('avatar')).status,200);assert.equal(await service.ctx.store.get('assets',firstId),null);await assert.rejects(fs.access(path.join(directory,'media',firstAsset.key)));
    const banner=(await upload('banner')).data.user.bannerUrl,bannerId=banner.split('/').at(-1),bannerAsset=await service.ctx.store.get('assets',bannerId);
    const removed=await request('/profile/media/banner',owner,undefined,'DELETE');assert.equal(removed.status,200);assert.equal(removed.data.user.bannerUrl,'');assert.equal(await service.ctx.store.get('assets',bannerId),null);await assert.rejects(fs.access(path.join(directory,'media',bannerAsset.key)));
    const gif=new FormData();gif.append('kind','avatar');gif.append('file',new Blob([Buffer.from('R0lGODlhAQABAPAAAP///wAAACH5BAAAAAAALAAAAAABAAEAAAICRAEAOw==','base64')]),'animated.gif');assert.equal((await request('/profile/media',owner,gif)).data.error.code,'PLAN_LIMIT');
    assert.equal((await request('/profile/media/other',owner,undefined,'DELETE')).status,400);
  }finally{await service.close();assert(directory.startsWith(qa+path.sep));await fs.rm(directory,{recursive:true,force:true,maxRetries:8,retryDelay:150});}
});
