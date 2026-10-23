import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {io} from 'socket.io-client';
import {homeLayoutSchema,homeWidgetTypes} from '../src/home-layout.js';
import {mergeSettings} from '../src/util.js';
import {createApp} from '../src/app.js';
import {config} from '../src/config.js';

const widget=(type,extra={})=>({id:type,type,size:'large',view:'cards',...extra});
const layout=widgets=>({version:1,widgets});

test('home canvas accepts portable order, sizes and views with per-type payloads',()=>{
  const widgets=homeWidgetTypes.map(type=>widget(type,type==='playlist'?{playlistId:'mine'}:type==='mix'?{genre:' Эмбиент ',mood:'calm'}:{}));
  widgets[1].size='small';widgets[1].view='list';
  const parsed=homeLayoutSchema.parse(layout(widgets));
  assert.deepEqual(parsed.widgets.map(w=>w.id),homeWidgetTypes);
  assert.equal(parsed.widgets[1].size,'small');
  assert.equal(parsed.widgets[1].view,'list');
  assert.equal(parsed.widgets.at(-1).genre,'ambient');
  assert.equal(homeLayoutSchema.parse(null),null);
  assert.deepEqual(homeLayoutSchema.parse(layout([])),layout([]));
});

test('home canvas rejects ambiguous identities, duplicated sections and unbounded payloads',()=>{
  const invalid=[
    {...layout([]),version:2}, {...layout([]),width:1280},
    layout([widget('wave'),widget('wave',{id:'wave-copy'})]),
    layout([widget('likes',{id:'same'}),widget('mix',{id:'same',genre:'jazz'})]),
    layout([widget('wave',{playlistId:'unexpected'})]),
    layout([widget('playlist')]),layout([widget('mix',{genre:' '})]),
    layout([widget('likes',{id:'<script>'})]),
    layout([widget('likes',{size:'900px'})]),layout([widget('likes',{view:'iframe'})]),
    layout([widget('mix',{genre:'a'.repeat(41)})]),
    layout(Array.from({length:21},(_,i)=>widget('likes',{id:'like-'+i}))),
  ];
  for(const value of invalid)assert.equal(homeLayoutSchema.safeParse(value).success,false,JSON.stringify(value));
});

test('default/reset and unrelated settings retain legacy pins and replace custom layout atomically',()=>{
  const pins=[{id:'old',type:'likes'}],custom=layout([widget('likes',{size:'small',view:'compact'})]);
  const old=mergeSettings({homePins:pins});
  assert.equal(old.homeLayout,null);
  const changed=mergeSettings(old,{homeLayout:custom});
  assert.deepEqual(changed.homePins,pins);
  assert.deepEqual(mergeSettings(changed,{lyrics:false}).homeLayout,custom);
  assert.equal(mergeSettings(changed,{homeLayout:null}).homeLayout,null);
  assert.deepEqual(mergeSettings(changed,{homeLayout:layout([])}).homeLayout,layout([]));
});

test('home settings enforce ownership and account scope, persist across reads, and broadcast the full layout',async()=>{
  const parent=path.resolve(config.root,'work/qa');
  const directory=await fs.mkdtemp(path.join(parent,'home-canvas-api-'));
  const service=await createApp({...config,env:'test',production:false,storage:'sqlite',objectStorage:'local',dataDir:directory,emailVerify:false,turnstileSecret:'',smtp:'',soundcloudPublicSearch:false,soundcloud:{id:'',secret:''},spotify:{id:'',secret:''},youtubeKey:'',discord:{id:'',secret:''}},{log:pino({level:'silent'})});
  await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${service.server.address().port}/api`;
  let socket;
  const request=async(endpoint,account,body,expectedAccount)=>{
    const response=await fetch(base+endpoint,{method:body?'PATCH':'GET',headers:{'X-GlukWave-Client':'native',...(account?{Authorization:'Bearer '+account.token}:{}),...(body?{'Content-Type':'application/json'}:{}),...(expectedAccount?{'X-GlukWave-Account':expectedAccount}:{})},...(body?{body:JSON.stringify(body)}:{})});
    return {status:response.status,body:await response.json()};
  };
  try{
    const register=async name=>{
      const response=await fetch(base+'/auth/register',{method:'POST',headers:{'Content-Type':'application/json','X-GlukWave-Client':'native'},body:JSON.stringify({email:name+'@test.example',username:name,password:'Home-canvas-test-password'})});
      assert.equal(response.status,201);return response.json();
    };
    const owner=await register('canvas_owner'),other=await register('canvas_other');
    await service.ctx.store.put('playlists','mine',{id:'mine',ownerId:owner.user.id,name:'Mine',trackIds:[],public:false});
    await service.ctx.store.put('playlists','foreign',{id:'foreign',ownerId:other.user.id,name:'Private',trackIds:[],public:false});
    const custom=layout([widget('playlist',{playlistId:'mine',size:'small',view:'compact'}),widget('wave',{view:'compact'}),widget('daily',{size:'medium',view:'list'})]);
    assert.equal((await request('/settings',null,{homeLayout:custom})).status,401);
    assert.equal((await request('/settings',owner)).body.settings.homeLayout,null);
    socket=io(base.replace('/api',''),{auth:{token:owner.token,deviceId:'canvas-sibling',surfaceId:'main',name:'Sibling',kind:'web'},transports:['websocket'],reconnection:false});
    await new Promise((resolve,reject)=>{socket.once('connect',resolve);socket.once('connect_error',reject);});
    const changed=new Promise(resolve=>socket.once('settings:changed',resolve));
    const saved=await request('/settings',owner,{homeLayout:custom,homePins:[{id:'legacy',type:'likes'}]},owner.user.id);
    assert.equal(saved.status,200);
    const event=await Promise.race([changed,new Promise((_,reject)=>{const timer=setTimeout(()=>reject(new Error('No settings broadcast')),2000);timer.unref();})]);
    assert.deepEqual(event.settings.homeLayout,custom);
    assert.equal(event.revision,saved.body.settings.revision);
    assert.deepEqual((await request('/settings',owner)).body.settings.homeLayout,custom);
    assert.equal((await request('/settings',other)).body.settings.homeLayout,null);
    for(const id of ['foreign','missing']){
      assert.equal((await request('/settings',owner,{homeLayout:layout([widget('playlist',{playlistId:id})])})).status,403);
    }
    assert.equal((await request('/settings',owner,{homeLayout:layout([widget('wave'),widget('wave',{id:'duplicate'})])})).status,400);
    assert.equal((await request('/settings',owner,{homeLayout:null},other.user.id)).status,409);
    assert.deepEqual((await request('/settings',owner)).body.settings.homeLayout,custom);
    const unrelated=await request('/settings',owner,{lyrics:false});
    assert.deepEqual(unrelated.body.settings.homeLayout,custom);
    const reset=await request('/settings',owner,{homeLayout:null});
    assert.equal(reset.status,200);
    assert.equal(reset.body.settings.homeLayout,null);
    assert.deepEqual(reset.body.settings.homePins,[{id:'legacy',type:'likes'}]);
    assert.equal(reset.body.settings.revision,saved.body.settings.revision+2);
  }finally{
    socket?.disconnect();await service.close();
    const relative=path.relative(parent,directory);
    assert(relative&&!relative.startsWith('..')&&!path.isAbsolute(relative));
    await fs.rm(directory,{recursive:true,force:true,maxRetries:5,retryDelay:100});
  }
});
