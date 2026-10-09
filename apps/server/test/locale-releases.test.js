import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import pino from 'pino';
import {io} from 'socket.io-client';
import {config} from '../src/config.js';
import {createApp} from '../src/app.js';
import {browserLanguage,countryLanguage,createCountryLookup,ipNumber,localeFor,languageCodes} from '../src/locale.js';
import {localizedError,errorCatalog} from '../src/messages.js';
import {accountMail,resetConfirmation} from '../src/mail-text.js';
import {systemText,notificationFor} from '../src/system-text.js';

test('automatic locale understands weighted browser tags and country choices, without private IP geolocation',()=>{
  assert.equal(browserLanguage('fr-FR,uk-UA;q=0.8,en;q=0.9'),'en');
  assert.equal(browserLanguage('de-DE;q=0,kk-KZ;q=0.4,es;q=0.7'),'es');
  assert.equal(browserLanguage('ru;q=invalid,de;q=2,*;q=1'),null);
  for(const [country,language] of [['KZ','kk'],['UA','uk'],['RU','ru'],['AT','de'],['MX','es'],['US','en']])assert.equal(countryLanguage(country),language);
  for(const ip of ['127.0.0.1','192.168.3.7','10.0.0.2','172.16.0.1','100.100.0.1','::1','fc00::1','fe80::1','::ffff:c0a8:0307','::ffff:127.0.0.1','fe80::1%eth0','bad'])assert.equal(ipNumber(ip),null);
  assert.equal(ipNumber('::ffff:0808:0808').value,ipNumber('8.8.8.8').value);
  assert.equal(ipNumber('2001:db8::192.0.2.1').family,6);
  assert.equal(localeFor({ip:'127.0.0.1',headers:{'accept-language':'kk-KZ'}},()=>null).language,'kk');
  assert.equal(localeFor({ip:'95.56.0.1',headers:{'accept-language':'en'}},()=> 'KZ').source,'ip');
  assert.equal(localeFor({ip:'127.0.0.1',headers:{}},()=>null).language,'en');
});

test('bundled country-only database resolves real IPv4/IPv6 locally and includes checked provenance',async()=>{
  const directory=path.join(config.root,'apps/server/data/geoip'),lookup=createCountryLookup(directory);
  assert.equal(lookup('8.8.8.8'),'US');assert.equal(lookup('77.88.8.8'),'RU');assert.equal(lookup('95.56.0.1'),'KZ');
  assert.match(lookup('2a00:1450:4001:800::200e'),/^[A-Z]{2}$/);
  assert.equal(lookup('192.168.3.7'),null);
  const provenance=JSON.parse(await fs.readFile(path.join(directory,'provenance.json'),'utf8'));
  for(const family of ['ipv4','ipv6']){const file=await fs.readFile(path.join(directory,family+'.csv.gz'));assert.equal(crypto.createHash('sha256').update(file).digest('hex'),provenance.databases[family].packedSha256);assert.ok(provenance.databases[family].rows>100000);}
});

test('server error catalogs are complete and preserve stable codes and Russian-specific detail',()=>{
  for(const [code,messages] of Object.entries(errorCatalog))for(const language of languageCodes.filter(value=>value!=='ru')){assert.equal(typeof messages[language],'string');assert.ok(messages[language].length>5,`${code}/${language}`);}
  const error={code:'AUTH_REQUIRED',message:'Войди в свой аккаунт.'};assert.deepEqual(localizedError(error,'ru'),error);assert.equal(localizedError(error,'de').code,error.code);assert.match(localizedError(error,'en').message,/Sign in/);
  for(const language of languageCodes){const link='https://example.test/?reset=opaque',verify=accountMail({displayName:'User'},'verify',link,language),reset=accountMail({displayName:'User'},'reset',link,language);assert.notEqual(verify.subject,reset.subject);assert.ok(reset.text.includes(link));assert.ok(reset.text.includes('30'));assert.ok(resetConfirmation(language).length>10);
    for(const key of ['likedTracks','likedVideos','importedTracks','importedMusic'])assert.notEqual(systemText(key,language),key);
    const notification=notificationFor({title:'Комната Alice',kind:'room.join',values:{name:'Имя MyName'},url:'/app/?roomId=qa'},language);assert.equal(notification.title,'Комната Alice');assert.ok(notification.body.includes('Имя MyName'));assert.equal(notification.kind,undefined);assert.equal(notification.values,undefined);
  }
});

test('locale, durable language settings, localized HTTP errors and real download integrity are enforced',async()=>{
  const qa=path.join(config.root,'work/qa');await fs.mkdir(qa,{recursive:true});const directory=await fs.mkdtemp(path.join(qa,'locale-releases-'));
  const service=await createApp({...config,env:'test',production:false,trustProxy:0,storage:'sqlite',dataDir:directory,releasesDir:directory,smtp:'',emailVerify:false,turnstileSecret:'',turnstileSiteKey:'',objectStorage:'local',soundcloudPublicSearch:false},{log:pino({level:'silent'})});
  try{
    await new Promise(resolve=>service.server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${service.server.address().port}`;
    await (await fetch(base+'/api/locale')).json();
    const local=await fetch(base+'/api/locale',{headers:{'Accept-Language':'es-ES','CF-IPCountry':'DE','X-Forwarded-For':'95.56.0.1'}}),locale=await local.json();
    assert.equal(locale.language,'es');assert.equal(locale.country,null);assert.equal(locale.source,'browser');assert.equal(local.headers.get('content-language'),'es');assert.match(local.headers.get('cache-control'),/no-store/);assert.equal(JSON.stringify(locale).includes('127.0.0.1'),false);
    service.app.set('trust proxy',1);const regional=await (await fetch(base+'/api/locale',{headers:{'X-Forwarded-For':'95.56.0.1','Accept-Language':'en'}})).json();assert.equal(regional.language,'kk');assert.equal(regional.country,'KZ');service.app.set('trust proxy',false);
    for(const language of languageCodes){const response=await fetch(base+'/api/library',{headers:{'Accept-Language':language}}),body=await response.json();assert.equal(response.status,401);assert.equal(body.error.code,'AUTH_REQUIRED');assert.equal(response.headers.get('content-language'),language);assert.ok(body.error.message.length>5);}
    const signup=await (await fetch(base+'/api/auth/register',{method:'POST',headers:{'Content-Type':'application/json','X-GlukWave-Client':'native'},body:JSON.stringify({email:'locale@example.test',username:'locale_qa',password:'locale-private-test-password'})})).json(),headers={Authorization:`Bearer ${signup.token}`,'Content-Type':'application/json','Accept-Language':'en'};
    const socket=io(base,{auth:{token:signup.token,deviceId:'locale-test',name:'Locale test',kind:'web',language:'en'},transports:['websocket'],reconnection:false});
    try{
      await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('Locale socket timeout')),4000);socket.once('connect',()=>{clearTimeout(timer);resolve();});socket.once('connect_error',error=>{clearTimeout(timer);reject(error);});});
      const change=await socket.timeout(3000).emitWithAck('locale:change',{language:'de'});assert.equal(change.language,'de');assert.equal(change.ok,true);
      const denied=await socket.timeout(3000).emitWithAck('room:command',{roomId:'absent',command:'pause'});assert.equal(denied.error.code,'ROOM_NOT_FOUND');assert.match(denied.error.message,/Raum/);
      assert.equal((await socket.timeout(3000).emitWithAck('locale:change',{language:'fr'})).error.code,'VALIDATION');
      const notification=new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('Localized notification timeout')),3000);socket.once('notification',message=>{clearTimeout(timer);resolve(message);});});
      await service.ctx.notifyUser(signup.user.id,{title:'Original room name',kind:'room.join',values:{name:'UserName'},url:'/app/?roomId=qa'});
      const delivered=await notification;assert.equal(delivered.title,'Original room name');assert.equal(delivered.body,'UserName ist dem Raum beigetreten');
    }finally{socket.disconnect();}
    assert.equal((await (await fetch(base+'/api/settings',{headers})).json()).settings.language,'auto');
    for(const language of ['en','ru','kk','uk','de','es','auto'])assert.equal((await fetch(base+'/api/settings',{method:'PATCH',headers,body:JSON.stringify({language})})).status,200);
    assert.equal((await fetch(base+'/api/settings',{method:'PATCH',headers,body:JSON.stringify({language:'fr'})})).status,400);
    const mismatch=await fetch(base+'/api/settings',{method:'PATCH',headers:{...headers,'X-GlukWave-Account':'previous-account'},body:JSON.stringify({language:'kk'})});
    assert.equal(mismatch.status,409);assert.equal((await mismatch.json()).error.code,'SESSION_CHANGED');
    assert.equal((await fetch(base+'/api/settings',{method:'PATCH',headers:{...headers,'X-GlukWave-Account':signup.user.id},body:JSON.stringify({language:'es'})})).status,200);
    await service.ctx.store.update('users',signup.user.id,user=>({...user,plan:'beta'}));
    await fetch(base+'/api/settings',{method:'PATCH',headers,body:JSON.stringify({language:'de'})});await fetch(base+'/api/settings',{method:'PATCH',headers,body:JSON.stringify({appearance:{radius:17}})});
    const settings=(await (await fetch(base+'/api/settings',{headers})).json()).settings;assert.equal(settings.language,'de');assert.equal(settings.appearance.radius,17);assert.equal((await service.ctx.store.get('settings',signup.user.id)).language,'de');
    assert.deepEqual((await (await fetch(base+'/api/releases')).json()).releases,[]);assert.equal((await fetch(base+'/api/downloads/android')).status,404);
    const bytes=Buffer.from('isolated package integrity fixture'),file='QA-only.apk',record={platform:'android',file,version:'1.0.0',channel:'beta',signature:'debug',bytes:bytes.length,sha256:crypto.createHash('sha256').update(bytes).digest('hex'),builtAt:new Date().toISOString()};
    await fs.writeFile(path.join(directory,file),bytes);await fs.writeFile(path.join(directory,'releases.json'),JSON.stringify({releases:[{...record,file:'../private.apk'},{...record,platform:'toString'},record]}));
    const releases=(await (await fetch(base+'/api/releases')).json()).releases;assert.equal(releases.length,1);assert.equal(releases[0].url,'/api/downloads/android');assert.equal(releases[0].path,undefined);assert.equal(releases[0].file,undefined);
    const downloaded=await fetch(base+'/api/downloads/android');assert.deepEqual(Buffer.from(await downloaded.arrayBuffer()),bytes);assert.equal(downloaded.headers.get('x-content-sha256'),record.sha256);
    const range=await fetch(base+'/api/downloads/android',{headers:{Range:'bytes=0-3'}});assert.equal(range.status,206);assert.equal((await range.arrayBuffer()).byteLength,4);
    await fs.writeFile(path.join(directory,file),Buffer.alloc(bytes.length,65));await fs.utimes(path.join(directory,file),new Date(),new Date(Date.now()+1000));
    assert.deepEqual((await (await fetch(base+'/api/releases')).json()).releases,[]);assert.equal((await fetch(base+'/api/downloads/android')).status,404);
  }finally{await service.close();await fs.rm(directory,{recursive:true,force:true});}
});
