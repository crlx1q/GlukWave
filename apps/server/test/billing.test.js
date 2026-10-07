import test,{before,after} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {config as defaults} from '../src/config.js';
import {createApp} from '../src/app.js';

let service,base,dir,user;
const webhookSecret='whsec_glukwave_signature_validation';
async function request(route,body,headers={}){
  const response=await fetch(base+route,{method:body===undefined?'GET':'POST',headers:{...(user?{Authorization:`Bearer ${user.token}`}:{ }),...(body!==undefined?{'Content-Type':'application/json'}:{ }),...headers},...(body!==undefined?{body:typeof body==='string'?body:JSON.stringify(body)}:{ })});
  return {status:response.status,data:await response.json()};
}
async function event(id,type,object,created=100){
  const payload=JSON.stringify({id,type,created,data:{object}});
  const signature=service.ctx.stripe.webhooks.generateTestHeaderString({payload,secret:webhookSecret});
  return request('/api/billing/webhook',payload,{'stripe-signature':signature});
}
before(async()=>{
  await fs.mkdir(path.join(defaults.root,'work/qa'),{recursive:true});
  dir=await fs.mkdtemp(path.join(defaults.root,'work/qa/billing-test-'));
  service=await createApp({...defaults,env:'test',dataDir:dir,storage:'sqlite',production:false,smtp:'',emailVerify:false,turnstileSecret:'',turnstileSiteKey:'',objectStorage:'local',stripe:{secret:'sk_test_local_signature_test',webhook:webhookSecret,price:'price_glukwave_unbound'}},{log:pino({level:'silent'})});
  await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));
  base=`http://127.0.0.1:${service.server.address().port}`;
  user=(await request('/api/auth/register',{email:'billing@example.test',username:'billing_test',password:'secure-test-passphrase'},{'X-GlukWave-Client':'native'})).data;
});
after(async()=>{await service.close();await fs.rm(dir,{recursive:true,force:true});});

test('billing verifies raw signatures and ignores unrelated events without granting a plan',async()=>{
  assert.equal((await request('/api/billing/webhook',{id:'unsigned'})).status,400);
  assert.equal((await event('evt_unrelated','invoice.paid',{})).status,200);
  assert.equal((await event('evt_unrelated','invoice.paid',{})).status,200);
  assert.equal((await service.ctx.store.get('users',user.user.id)).plan,'free');
  assert.equal((await request('/api/billing/status')).data.configured,true);
});
test('paid access requires a bound checkout and current matching subscription; cancellation preserves beta',async()=>{
  const uid=user.user.id;
  let subscription={id:'sub_glukwave_test',customer:'cus_glukwave_test',metadata:{userId:uid},status:'active',cancel_at_period_end:false,current_period_end:2000000000,items:{data:[{price:{id:'price_glukwave_unbound'}}]}};
  // Only the remote subscription response is a fixture; signing, HTTP and persistence are real.
  let lookups=0;service.ctx.stripe.subscriptions.retrieve=async id=>{lookups++;assert.equal(id,subscription.id);return subscription;};
  assert.equal((await event('evt_unbound','checkout.session.completed',{id:'cs_unknown',client_reference_id:uid,subscription:subscription.id})).status,200);
  assert.equal(lookups,0);
  assert.equal((await service.ctx.store.get('users',uid)).plan,'free');
  await service.ctx.store.create('billingCheckouts','cs_owned',{id:'cs_owned',userId:uid});
  assert.equal((await event('evt_paid','checkout.session.completed',{id:'cs_owned',client_reference_id:uid,subscription:subscription.id},101)).status,200);
  assert.equal((await service.ctx.store.get('users',uid)).plan,'unbound');
  subscription={...subscription,status:'canceled'};
  assert.equal((await event('evt_cancel','customer.subscription.updated',{id:subscription.id},102)).status,200);
  assert.equal((await service.ctx.store.get('users',uid)).plan,'free');
  await service.ctx.store.update('users',uid,u=>({...u,plan:'beta'}));
  assert.equal((await event('evt_beta','customer.subscription.deleted',{id:subscription.id},103)).status,200);
  assert.equal((await service.ctx.store.get('users',uid)).plan,'beta');
});
