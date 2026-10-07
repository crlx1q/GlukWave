import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import { click,evaluate,open,run,select,snapshot,useSession,wait } from './browser.mjs';
useSession('gluk-language-guest');
const copies=Object.fromEntries(await Promise.all(['ru','es','de','en'].map(async code=>[code,JSON.parse(await fs.readFile(`apps/web/src/locales/${code}.json`,'utf8'))]))),samples=[],file='work/qa/web-language-races.json';
const state=()=>evaluate(`({language:document.documentElement.lang,choice:localStorage.getItem('gw-language-choice'),user:JSON.parse(localStorage.getItem('gw-user')||'null')?.id,pending:JSON.parse(localStorage.getItem('gw-settings-pending:'+JSON.parse(localStorage.getItem('gw-user')||'{}').id)||'{}'),landing:!!document.querySelector('.public-site'),app:!!document.querySelector('.app-shell')})`);
try{
 run('set','viewport','1280','900');click(copies.ru['copy.023']);click(/^Язык /);
 wait(`!!navigator.serviceWorker.controller`);run('set','offline','on');wait(`!navigator.onLine`);
 select('es');const offline=state();samples.push({step:'offline manual choice',...offline});assert.equal(offline.pending.language,'es');assert.equal(offline.choice,'es');
 open('http://127.0.0.1:4100/');wait(`!!document.querySelector('.public-site')`);samples.push({step:'offline landing',...state()});assert.equal(samples.at(-1).language,'es');
 run('set','offline','off');run('reload');snapshot();wait(`!!document.querySelector('.public-site')&&document.documentElement.lang==='es'`);
 const arrival=evaluate(`fetch('/api/settings').then(r=>r.json()).then(payload=>({server:payload.settings.language,html:document.documentElement.lang,pending:JSON.parse(localStorage.getItem('gw-settings-pending:'+JSON.parse(localStorage.getItem('gw-user')).id)||'{}')}))`);samples.push({step:'pending choice over stale account preference',...arrival});assert.equal(arrival.server,'ru');assert.equal(arrival.html,'es');assert.equal(arrival.pending.language,'es');
 open('http://127.0.0.1:4100/app/#settings');wait(`!localStorage.getItem('gw-settings-pending:'+JSON.parse(localStorage.getItem('gw-user')).id)`);samples.push({step:'pending choice synced in app',...state(),server:evaluate(`fetch('/api/settings').then(r=>r.json()).then(payload=>payload.settings.language)`)});assert.equal(samples.at(-1).server,'es');
 click(/^Idioma /);
 evaluate(`window.__originalLocaleFetch=window.fetch;window.__realAutomaticResponse=null;window.fetch=async(...args)=>{const response=await __originalLocaleFetch(...args);if(new URL(typeof args[0]==='string'?args[0]:args[0].url,location.href).pathname==='/api/locale'){window.__realAutomaticResponse=await response.clone().json();await new Promise(resolve=>window.__releaseAutomatic=resolve);}return response;};`);
 select('auto');wait(`!!window.__realAutomaticResponse`);select('de');evaluate(`__releaseAutomatic();window.fetch=__originalLocaleFetch;`);snapshot();
 wait(`document.documentElement.lang==='de'&&localStorage.getItem('gw-language-choice')==='de'`);
 const late={step:'manual choice survives delayed real automatic response',...state(),automatic:evaluate(`window.__realAutomaticResponse`)};samples.push(late);assert.equal(late.automatic.language,'ru');assert.equal(late.language,'de');assert.equal(late.choice,'de');
 await fs.writeFile(file,JSON.stringify({passed:true,samples},null,2));console.log(JSON.stringify({passed:true,file,samples}));
}catch(error){await fs.writeFile(file,JSON.stringify({passed:false,error:String(error),samples,snapshot:snapshot().snapshot},null,2));throw error;}finally{run('set','offline','off');evaluate(`if(window.__originalLocaleFetch)window.fetch=__originalLocaleFetch;if(window.__releaseAutomatic)__releaseAutomatic();`);}
