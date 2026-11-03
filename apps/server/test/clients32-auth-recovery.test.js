import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {config as defaults} from '../src/config.js';
import {createApp} from '../src/app.js';
import {digest,secret} from '../src/util.js';

test('native authentication recovers only the same approved delivery after a lost response',async t=>{
  const parent=path.join(defaults.root,'work','qa');
  await fs.mkdir(parent,{recursive:true});
  const directory=await fs.mkdtemp(path.join(parent,'clients32-auth-recovery-'));
  const app=await createApp({...defaults,env:'test',production:false,storage:'sqlite',objectStorage:'local',dataDir:directory,emailVerify:false,turnstileSiteKey:'test-site-key',turnstileSecret:'',smtp:'',soundcloudPublicSearch:false,soundcloud:{id:'',secret:''},discord:{id:'',secret:''}},{log:pino({level:'silent'})});
  await new Promise(resolve=>app.server.listen(0,'127.0.0.1',resolve));
  t.after(async()=>{
    await app.close();
    const relative=path.relative(parent,directory);
    assert(relative&&!relative.startsWith('..')&&!path.isAbsolute(relative));
    await fs.rm(directory,{recursive:true,force:true,maxRetries:5,retryDelay:100});
  });
  const base=`http://127.0.0.1:${app.server.address().port}/api/auth`;
  const request=async(route,{body,token,headers={}}={})=>{
    const response=await fetch(base+route,{method:body?'POST':'GET',headers:{'X-GlukWave-Client':'native',...(body?{'Content-Type':'application/json'}:{}),...(token?{Authorization:'Bearer '+token}:{}),...headers},...(body?{body:JSON.stringify(body)}:{})});
    return {status:response.status,headers:response.headers,body:await response.json()};
  };
  const owner=(await request('/register',{body:{email:'recovery_owner@test.example',username:'recovery_owner',password:'Long-clients32-auth-password'}})).body;
  assert(owner.token);
  const claimHeaders=()=>({'X-GlukWave-Auth-Claim':randomUUID(),'X-GlukWave-Device':'recovery-android','X-GlukWave-Kind':'android','X-GlukWave-Surface':'main-surface'});
  const create=async(kind='native')=>{
    const result=await request('/'+kind,{body:kind==='native'?{method:'email'}:{}});
    assert.equal(result.status,201,JSON.stringify(result.body));
    return result.body;
  };
  const poll=(kind,bridge,headers)=>request(`/${kind}/${bridge.id}?secret=${encodeURIComponent(bridge.secret)}`,{headers});
  const approve=async(kind,bridge)=>{
    const result=await request(`/${kind}/${bridge.id}/approve`,{token:kind==='native-captcha'?undefined:owner.token,body:kind==='qr'?{}:kind==='native'?{secret:bridge.secret}:{secret:bridge.secret,captchaToken:'fixture-one-use-captcha'}});
    assert.equal(result.status,200,JSON.stringify(result.body));
  };
  const sessions=()=>app.ctx.store.list('sessions');

  await t.test('pending does not approve and concurrent retries issue exactly one native session',async()=>{
    const bridge=await create(),headers=claimHeaders(),before=(await sessions()).length;
    assert.equal((await poll('native',bridge,headers)).body.status,'pending');
    assert.equal((await sessions()).length,before);
    await approve('native',bridge);
    // Ignore the first completed HTTP result, as if the response was lost after
    // the server committed it. The following attempt must recover that result.
    await poll('native',bridge,headers);
    const repeats=await Promise.all(Array.from({length:8},()=>poll('native',bridge,headers)));
    assert(repeats.every(result=>result.status===200&&result.body.status==='approved'));
    assert.equal(new Set(repeats.map(result=>result.body.token)).size,1);
    assert.equal((await sessions()).length,before+1);
    assert.equal(repeats[0].body.user.id,owner.user.id);
    assert.equal(repeats[0].headers.get('Cache-Control'),'no-store');
    assert(repeats[0].headers.get('Set-Cookie').includes('HttpOnly'));
    assert.equal((await request('/me',{token:repeats[0].body.token})).body.user.id,owner.user.id);
    const stored=await app.ctx.store.get('challenges',bridge.id);
    assert.equal(stored.status,'consumed');
    assert.equal(stored.token,undefined);
    assert.equal(stored.claim,undefined);
  });

  await t.test('QR still requires explicit authenticated approval',async()=>{
    const bridge=await create('qr'),headers=claimHeaders(),before=(await sessions()).length;
    assert.equal((await poll('qr',bridge,headers)).body.status,'pending');
    assert.equal((await request(`/qr/${bridge.id}/approve`,{body:{}})).status,401);
    assert.equal((await poll('qr',bridge,headers)).body.status,'pending');
    await approve('qr',bridge);
    const first=await poll('qr',bridge,headers),second=await poll('qr',bridge,headers);
    assert.equal(first.body.status,'approved');
    assert.equal(second.body.token,first.body.token);
    assert.equal((await sessions()).length,before+1);
  });

  await t.test('CAPTCHA delivery recovers its token without transferring an account or session',async()=>{
    const bridge=await create('native-captcha'),headers=claimHeaders(),before=(await sessions()).length;
    assert.equal((await poll('native-captcha',bridge,headers)).body.status,'pending');
    await approve('native-captcha',bridge);
    await poll('native-captcha',bridge,headers);
    const result=await poll('native-captcha',bridge,headers);
    assert.equal(result.body.captchaToken,'fixture-one-use-captcha');
    assert.equal(result.body.user,undefined);
    assert.equal(result.body.token,undefined);
    assert.equal(result.headers.get('Set-Cookie'),null);
    assert.equal((await sessions()).length,before);
    assert.equal((await app.ctx.store.get('challenges',bridge.id)).captchaToken,undefined);
  });

  await t.test('wrong claim, device, surface, kind, client and secret cannot recover an approved response',async()=>{
    const bridge=await create(),headers=claimHeaders();
    await approve('native',bridge);
    assert.equal((await poll('native',bridge,{...headers,'X-GlukWave-Auth-Claim':'invalid'})).status,400);
    const first=await poll('native',bridge,headers),before=(await sessions()).length;
    assert.equal(first.body.status,'approved');
    for(const changed of [
      {'X-GlukWave-Auth-Claim':randomUUID()},
      {'X-GlukWave-Device':'another-device'},
      {'X-GlukWave-Surface':'another-surface'},
      {'X-GlukWave-Kind':'ios'},
      {'X-GlukWave-Client':'web'},
      {'X-GlukWave-Device':''},
    ]){
      const denied=await poll('native',bridge,{...headers,...changed});
      assert.equal(denied.status,403,JSON.stringify(denied.body));
      assert.equal(denied.body.token,undefined);
    }
    assert.equal((await poll('native',{...bridge,secret:'wrong-secret'},headers)).status,404);
    assert.equal((await poll('native',bridge,{})).body.status,'expired');
    assert.equal((await poll('native',bridge,headers)).body.token,first.body.token);
    assert.equal((await sessions()).length,before);
  });

  await t.test('revoked and blocked sessions cannot be recovered',async()=>{
    const revoked=await create(),revokedHeaders=claimHeaders();
    await approve('native',revoked);
    const issued=await poll('native',revoked,revokedHeaders);
    await request('/logout',{body:{},token:issued.body.token});
    const denied=await poll('native',revoked,revokedHeaders);
    assert.equal(denied.status,403);
    assert.equal(denied.body.error.code,'AUTH_RECOVERY_REVOKED');
    const blocked=await create(),blockedHeaders=claimHeaders();
    await approve('native',blocked);
    await poll('native',blocked,blockedHeaders);
    await app.ctx.store.update('users',owner.user.id,user=>({...user,blocked:true}));
    try{assert.equal((await poll('native',blocked,blockedHeaders)).status,403);}
    finally{await app.ctx.store.update('users',owner.user.id,user=>({...user,blocked:false}));}
  });

  await t.test('challenge expiry and the 60 second recovery deadline remain terminal',async sub=>{
    const bridge=await create(),headers=claimHeaders();
    await approve('native',bridge);
    await poll('native',bridge,headers);
    await app.ctx.store.update('challenges',bridge.id,entry=>({...entry,expiresAt:Date.now()-1}));
    assert.equal((await poll('native',bridge,headers)).body.status,'expired');
    const lease=await create(),leaseHeaders=claimHeaders();
    await approve('native',lease);
    await poll('native',lease,leaseHeaders);
    const actualNow=Date.now;
    const clock=sub.mock.method(Date,'now',()=>actualNow()+61000);
    try{assert.equal((await poll('native',lease,leaseHeaders)).body.status,'expired');}
    finally{clock.mock.restore();}
  });

  await t.test('failed session issuance leaves approval available for a safe GET retry',async()=>{
    const bridge=await create(),headers=claimHeaders(),before=(await sessions()).length;
    await approve('native',bridge);
    const original=app.ctx.store.create;
    let failures=1;
    app.ctx.store.create=async(collection,...args)=>{
      if(collection==='sessions'&&failures-- >0)throw new Error('Isolated session storage failure');
      return original(collection,...args);
    };
    try{assert.equal((await poll('native',bridge,headers)).status,500);}
    finally{app.ctx.store.create=original;}
    assert.equal((await app.ctx.store.get('challenges',bridge.id)).status,'approved');
    assert.equal((await sessions()).length,before);
    assert.equal((await poll('native',bridge,headers)).body.status,'approved');
    assert.equal((await sessions()).length,before+1);
  });

  await t.test('legacy native, QR and CAPTCHA polling stays exactly once',async()=>{
    for(const kind of ['native','qr','native-captcha']){
      const bridge=await create(kind);
      await approve(kind,bridge);
      const completed=await Promise.all([poll(kind,bridge,{}),poll(kind,bridge,{})]);
      assert.equal(completed.filter(result=>result.body.status==='approved').length,1);
      assert.equal((await poll(kind,bridge,{})).body.status,'expired');
    }
    const bridge=await create('qr');
    await approve('qr',bridge);
    const web=await poll('qr',bridge,{'X-GlukWave-Client':'web'});
    assert.equal(web.body.status,'approved');
    assert.equal(web.body.token,undefined);
    assert(web.headers.get('Set-Cookie').includes('HttpOnly'));
  });

  await t.test('memory recovery is bounded and never persists approved payloads',async()=>{
    const headers=claimHeaders(),bridges=[];
    for(let index=0;index<1025;index++){
      const bridge={id:randomUUID(),secret:secret()};
      bridges.push(bridge);
      await app.ctx.store.create('challenges',bridge.id,{id:bridge.id,kind:'captcha',secretHash:digest(bridge.secret),status:'approved',captchaToken:'bounded-fixture',expiresAt:Date.now()+120000});
      assert.equal((await poll('native-captcha',bridge,headers)).body.status,'approved');
    }
    assert.equal((await poll('native-captcha',bridges[0],headers)).body.status,'expired');
    assert.equal((await poll('native-captcha',bridges.at(-1),headers)).body.captchaToken,'bounded-fixture');
    const consumed=await app.ctx.store.list('challenges',entry=>entry.status==='consumed');
    assert(consumed.every(entry=>entry.captchaToken===undefined&&entry.token===undefined&&entry.payload===undefined));
  });
});
