import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {io} from 'socket.io-client';
import {createAbuseProtection} from '../src/abuse-protection.js';
import {savedThemesSchema,wallpaperSchema} from '../src/presentation-settings.js';
import {createApp} from '../src/app.js';
import {config} from '../src/config.js';
import {applyCommand,initialState,commandSchema} from '../src/rooms.js';

test('previous restarts normally but an explicit second press hops despite a stale remote position',()=>{
  const state={...initialState(),trackId:'current',queue:['prior','current','next'],position:20,playing:true,updatedAt:1000};
  const restart=applyCommand(state,{command:'previous'},1000);
  assert.equal(restart.trackId,'current');assert.equal(restart.position,0);
  const prior=applyCommand(state,commandSchema.parse({command:'previous',restart:false}),1000);
  assert.equal(prior.trackId,'prior');assert.equal(prior.position,0);
  assert.equal(applyCommand(restart,{command:'previous'},1100).trackId,'prior');
});

test('action budgets allow ordinary bursts, continuous recovery and isolate activity',()=>{
  let now=0;const guard=createAbuseProtection({clock:()=>now,maxEntries:3});
  for(let i=0;i<14;i++)guard.check('message','alice',{content:'A different reply '+i});
  assert.throws(()=>guard.check('message','alice',{content:'One more'}),error=>error.status===429&&error.details.retryAfter===2);
  for(let i=0;i<80;i++)guard.check('control','alice');
  guard.check('message','bob',{content:'One more'});
  now=2000;guard.check('message','alice',{content:'Recovered without a fixed cooldown'});
  for(let i=0;i<20;i++)guard.check('state','actor-'+i);
  assert(guard.stats().tracked<=3);guard.close();assert.equal(guard.stats().tracked,0);
});

test('pasted content duplicates are normalized across destinations without blocking short conversation',()=>{
  let now=0;const guard=createAbuseProtection({clock:()=>now});
  const text='This is a pasted promotional paragraph to many rooms';
  guard.check('message','alice',{content:text});guard.check('message','alice',{content:text.toUpperCase().replaceAll(' ','  ')});
  assert.throws(()=>guard.check('message','alice',{content:text+'\u200b'}),error=>error.code==='DUPLICATE_CONTENT');
  for(let i=0;i<5;i++)guard.check('message','alice',{content:'Да'});
  guard.check('comment','alice',{content:text});guard.check('message','bob',{content:text});
  now=31000;guard.check('message','alice',{content:text});
});

test('presentation settings reject executable URLs and ambiguous custom presets',()=>{
  const colors={bg:'#101010',surface:'#202020',ink:'#eeeeee',accent:'#abcdef'},theme={id:'mine',name:'My theme',mode:'dark',colors};
  assert.equal(savedThemesSchema.parse([theme])[0].name,'My theme');
  assert.equal(savedThemesSchema.safeParse([theme,theme]).success,false);
  assert.equal(savedThemesSchema.safeParse([{...theme,html:'unsafe'}]).success,false);
  assert.equal(wallpaperSchema.safeParse({url:'https://tracker.example/image.gif'}).success,false);
  assert.equal(wallpaperSchema.safeParse({url:'javascript:alert(1)'}).success,false);
  assert.equal(wallpaperSchema.safeParse({dim:1}).success,false);
  assert.equal(wallpaperSchema.safeParse({blur:25}).success,false);
});

test('real settings, GIF wallpaper ownership, native/web QR exchange and smart content protection',async()=>{
  const parent=path.resolve(config.root,'work/qa'),directory=await fs.mkdtemp(path.join(parent,'studio31-server-'));
  const app=await createApp({...config,env:'test',production:false,storage:'sqlite',objectStorage:'local',dataDir:directory,emailVerify:false,turnstileSecret:'',smtp:'',adminEmails:['studio_owner@test.example'],soundcloudPublicSearch:false,soundcloud:{id:'',secret:''},spotify:{id:'',secret:''},youtubeKey:'',discord:{id:'',secret:''}},{log:pino({level:'silent'})});
  await new Promise(resolve=>app.server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${app.server.address().port}/api`;
  let sibling;
  const request=async(route,account,body,method=body?'POST':'GET',headers={})=>{
    const response=await fetch(base+route,{method,headers:{...(account?{Authorization:'Bearer '+account.token}:{}),...(body&&!(body instanceof FormData)?{'Content-Type':'application/json'}:{}),...headers},...(body?{body:body instanceof FormData?body:JSON.stringify(body)}:{})});
    const type=response.headers.get('Content-Type');return{status:response.status,headers:response.headers,body:type?.includes('application/json')?await response.json():await response.arrayBuffer()};
  };
  try{
    const register=async username=>(await request('/auth/register',null,{email:username+'@test.example',username,password:'Long-safe-studio31-password'},'POST',{'X-GlukWave-Client':'native'})).body;
    const owner=await register('studio_owner'),other=await register('studio_other');
    sibling=io(base.replace('/api',''),{auth:{token:owner.token,deviceId:'studio-sibling',surfaceId:'main',name:'Sibling',kind:'web'},transports:['websocket'],reconnection:false});
    await new Promise((resolve,reject)=>{sibling.once('connect',resolve);sibling.once('connect_error',reject);});
    const ownHeader={'X-GlukWave-Account':owner.user.id};
    const colors={bg:'#121215',surface:'#222228',ink:'#eeeeee',accent:'#abcdef'};
    const changed=await request('/settings',owner,{powerSaving:true,savedThemes:[{id:'mine',name:'My night',mode:'dark',colors}],appearance:{miniBackground:'pixels'},wallpaper:{dim:.6,blur:12}},'PATCH',ownHeader);
    assert.equal(changed.status,200,JSON.stringify(changed.body));assert.equal(changed.body.settings.powerSaving,true);
    const gif=Buffer.from('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7','base64');
    const upload=async(account=owner,header=ownHeader)=>{const form=new FormData();form.append('file',new Blob([gif],{type:'image/gif'}),'wall.gif');return request('/settings/wallpaper',account,form,'POST',header);};
    const broadcast=new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('Wallpaper settings did not reach sibling')),3000);sibling.once('settings:changed',event=>{clearTimeout(timer);resolve(event);});});
    const image=await upload();assert.equal(image.status,201,JSON.stringify(image.body));
    const event=await broadcast;assert.deepEqual(event.settings.wallpaper,image.body.wallpaper);assert.equal(event.revision,image.body.revision);
    const wallpaper=image.body.wallpaper;assert.equal(wallpaper.dim,.6);assert.equal(wallpaper.blur,12);assert(wallpaper.url.startsWith('/api/profile-assets/'));
    assert.equal((await request(wallpaper.url.replace('/api',''))).headers.get('Content-Type'),'image/gif');
    assert.equal((await request('/settings',other,{wallpaper},'PATCH')).status,403);
    assert.equal((await upload(owner,{'X-GlukWave-Account':other.user.id})).status,409);
    const sparse=await request('/settings',owner,{wallpaper:{blur:3}},'PATCH');assert.equal(sparse.body.settings.wallpaper.url,wallpaper.url);assert.equal(sparse.body.settings.wallpaper.dim,.6);
    assert.equal((await request('/settings',other)).body.settings.wallpaper.url,'');
    assert.equal((await request('/settings',owner,{wallpaper:{url:'https://untrusted.example/a.gif'}},'PATCH')).status,400);
    const second=await upload();assert.equal(second.status,201);assert.equal((await request(wallpaper.url.replace('/api',''))).status,404);
    // QR exchange stays secret-bound, native receives a bearer, web only a cookie.
    for(const native of [true,false]){
      const challenge=(await request('/auth/qr',null,{deviceName:native?'Windows':'Chrome'})).body;
      assert.equal((await request(`/auth/qr/${challenge.id}?secret=wrong`)).status,404);
      assert.equal((await request(`/auth/qr/${challenge.id}/approve`,null,{})).status,401);
      assert.equal((await request(`/auth/qr/${challenge.id}/approve`,owner,{})).status,200);
      const exchange=await request(`/auth/qr/${challenge.id}?secret=${challenge.secret}`,null,null,'GET',native?{'X-GlukWave-Client':'native'}:{});
      assert.equal(exchange.body.status,'approved');assert.equal(exchange.headers.get('Cache-Control'),'no-store');
      if(native)assert.equal((await request('/auth/me',{token:exchange.body.token})).body.user.id,owner.user.id);else assert.equal(exchange.body.token,undefined);
      assert(exchange.headers.get('Set-Cookie').includes('HttpOnly'));
      assert.equal((await request(`/auth/qr/${challenge.id}?secret=${challenge.secret}`)).body.status,'expired');
    }
    // Cheap polling no longer burns an all-endpoint shared IP allowance.
    for(let offset=0;offset<330;offset+=30){const polls=await Promise.all(Array.from({length:30},()=>request('/auth/me',owner)));assert(polls.every(row=>row.status===200));}
    const room=(await request('/rooms',owner,{name:'Studio'})).body.room;
    const repeated='One pasted message repeated in several rooms is not normal conversation';
    for(let i=0;i<2;i++)assert.equal((await request(`/rooms/${room.id}/messages`,owner,{text:repeated})).status,201);
    const duplicate=await request(`/rooms/${room.id}/messages`,owner,{text:repeated.toUpperCase()});
    assert.equal(duplicate.status,429);assert.equal(duplicate.body.error.code,'DUPLICATE_CONTENT');assert(duplicate.headers.get('Retry-After'));
    assert.equal((await request(`/rooms/${room.id}/messages`,owner,{text:'A different natural reply'})).status,201);
    assert.equal((await request('/settings',owner)).status,200);
    assert.equal((await request('/admin/overview',other)).status,403);assert.equal((await request('/admin/overview',owner)).status,200);
  }finally{
    sibling?.disconnect();await app.close();const relative=path.relative(parent,directory);assert(relative&&!relative.startsWith('..')&&!path.isAbsolute(relative));await fs.rm(directory,{recursive:true,force:true,maxRetries:5,retryDelay:100});
  }
});
