import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import pino from 'pino';
import {io} from 'socket.io-client';
import {config} from '../src/config.js';
import {createApp} from '../src/app.js';

test('appearance keeps separate palettes, validates colors and merges durable partial updates',async()=>{
  const qa=path.resolve(config.root,'work/qa');await fs.mkdir(qa,{recursive:true});const directory=await fs.mkdtemp(path.join(qa,'appearance-test-'));
  const service=await createApp({...config,env:'test',production:false,storage:'sqlite',dataDir:directory,turnstileSecret:'',turnstileSiteKey:'',smtp:'',emailVerify:false,objectStorage:'local',soundcloudPublicSearch:false},{log:pino({level:'silent'})});
  const sockets=[];
  try{
    await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}`;
    const auth=await (await fetch(base+'/api/auth/register',{method:'POST',headers:{'Content-Type':'application/json','X-GlukWave-Client':'native'},body:JSON.stringify({email:'appearance@example.test',username:'appearance_qa',password:'local-appearance-test-passphrase'})})).json();
    const headers={'Content-Type':'application/json',Authorization:`Bearer ${auth.token}`};
    async function connect(token,deviceId){
      const socket=io(base,{auth:{token,deviceId,name:deviceId,kind:'web'},transports:['websocket'],reconnection:false});sockets.push(socket);
      await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('settings socket connection timed out')),4000);socket.once('connect',()=>{clearTimeout(timer);resolve();});socket.once('connect_error',error=>{clearTimeout(timer);reject(error);});});
      return socket;
    }
    const own=await connect(auth.token,'appearance-device'),received=[];own.on('settings:changed',event=>received.push(event));
    const other=await (await fetch(base+'/api/auth/register',{method:'POST',headers:{'Content-Type':'application/json','X-GlukWave-Client':'native'},body:JSON.stringify({email:'other-appearance@example.test',username:'other_appearance_qa',password:'local-other-appearance-passphrase'})})).json();
    const unrelated=await connect(other.token,'unrelated-device'),unrelatedEvents=[];unrelated.on('settings:changed',event=>unrelatedEvents.push(event));
    const patch=async changes=>{const response=await fetch(base+'/api/settings',{method:'PATCH',headers,body:JSON.stringify(changes)});return {status:response.status,data:await response.json()};};
    assert.equal((await patch({theme:'dark',appearance:{dark:{accent:'#7CA8BB'},light:{bg:'#efeedd'},radius:12,compact:true,waveStyle:'particles',cover3d:false,coverKind:'cd'}})).status,200);
    const merged=await patch({appearance:{speed:.6,dark:{surface:'#252525'}}});
    assert.equal(merged.data.settings.appearance.dark.accent,'#7ca8bb');assert.equal(merged.data.settings.appearance.dark.surface,'#252525');
    assert.equal(merged.data.settings.appearance.light.bg,'#efeedd');assert.equal(merged.data.settings.appearance.light.accent,'#a08369');assert.equal(merged.data.settings.appearance.compact,true);
    assert.equal(merged.data.settings.appearance.coverKind,'cd');assert.equal(merged.data.settings.appearance.cover3d,false);
    assert.equal((await patch({appearance:{light:{bg:'url(https://example.test)'}}})).status,400);
    assert.equal((await patch({appearance:{radius:99}})).status,400);assert.equal((await patch({appearance:{speed:0}})).status,400);
    const get=await (await fetch(base+'/api/settings',{headers})).json();assert.deepEqual(get.settings,merged.data.settings);
    const stored=await service.ctx.store.get('settings',auth.user.id);assert.equal(stored.appearance.waveStyle,'particles');assert.equal(stored.theme,'dark');
    const concurrent=await Promise.all([patch({appearance:{light:{ink:'#111122'}}}),patch({appearance:{dark:{bg:'#171717'}}}),patch({lyrics:false})]);
    assert.ok(concurrent.every(result=>result.status===200));
    await new Promise(resolve=>setTimeout(resolve,100));
    assert.deepEqual(received.map(event=>event.revision),[1,2,3,4,5]);assert.deepEqual(unrelatedEvents,[]);
    assert.equal(received.at(-1).settings.appearance.light.ink,'#111122');assert.equal(received.at(-1).settings.appearance.dark.bg,'#171717');assert.equal(received.at(-1).settings.lyrics,false);
    assert.equal((await patch({revision:99})).status,400);
  }finally{for(const socket of sockets)socket.disconnect();await service.close();assert.ok(directory.startsWith(qa+path.sep));await fs.rm(directory,{recursive:true,force:true,maxRetries:8,retryDelay:150});}
});
