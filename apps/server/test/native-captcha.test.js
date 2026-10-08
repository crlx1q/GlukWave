import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {config as defaults} from '../src/config.js';
import {createApp} from '../src/app.js';

test('Native CAPTCHA bridge is secret protected, one-use and never transfers a session',async()=>{
 const dir=await fs.mkdtemp(path.join(defaults.root,'work/qa/native-captcha-'));
 const service=await createApp({...defaults,env:'test',storage:'sqlite',dataDir:dir,production:false,appUrl:'https://wave.gluk.tech',turnstileSiteKey:'test-site-key',turnstileSecret:'',objectStorage:'local',smtp:'',emailVerify:false},{log:pino({level:'silent'})});
 await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}`;
 const request=async(route,body)=>{const response=await fetch(base+'/api/auth'+route,{method:body?'POST':'GET',headers:{'Content-Type':'application/json','X-GlukWave-Client':'native'},...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,body:await response.json(),headers:response.headers};};
 try{
   const challenge=(await request('/native-captcha',{})).body;
   assert(challenge.url.startsWith('https://wave.gluk.tech/app/?nativeCaptcha='));assert.equal(typeof challenge.expiresAt,'number');
   assert.equal((await request(`/native-captcha/${challenge.id}?secret=wrong`)).status,404);
   const url=`/native-captcha/${challenge.id}?secret=${encodeURIComponent(challenge.secret)}`;
   assert.equal((await request(url)).body.status,'pending');
   assert.equal((await request(`/native-captcha/${challenge.id}/approve`,{secret:'wrong',captchaToken:'test-captcha'})).status,400);
   await request(`/native-captcha/${challenge.id}/approve`,{secret:challenge.secret,captchaToken:'test-captcha'});
   const completed=await Promise.all([request(url),request(url)]);
   assert.equal(completed.filter(r=>r.body.captchaToken==='test-captcha').length,1);
   assert(completed.every(r=>!r.body.user&&!r.body.token));
   assert.equal((await request(url)).body.status,'expired');
   assert.equal((await service.ctx.store.get('challenges',challenge.id)).captchaToken,undefined);
 }finally{await service.close();await fs.rm(dir,{recursive:true,force:true});}
});
