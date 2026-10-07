import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import { evaluate,open,run,snapshot,useSession,wait } from './browser.mjs';
useSession('gluk-language-guest');
const samples=[],file='work/qa/web-language-pwa.json';
const state=()=>evaluate(`({url:location.href,language:document.documentElement.lang,heading:document.querySelector('h1')?.textContent,app:!!document.querySelector('.app-shell'),landing:!!document.querySelector('.public-site'),mini:!!document.querySelector('.times'),offline:!navigator.onLine,overflow:document.documentElement.scrollWidth>innerWidth})`);
try{
 run('reload');snapshot();wait(`!!document.querySelector('.public-site')`);run('scrollintoview','.site-preview');wait(`document.querySelector('.site-preview img')?.naturalWidth===1280`);
 open('http://127.0.0.1:4100/app/#settings');wait(`!!navigator.serviceWorker.controller&&!!document.querySelector('main h1')`);
 const manifest=evaluate(`fetch('/manifest.webmanifest').then(r=>r.json())`);assert.equal(manifest.start_url,'/app/');assert.equal(manifest.lang,'en');
 const cache=evaluate(`caches.keys().then(async names=>({names,urls:(await Promise.all(names.map(async name=>(await (await caches.open(name)).keys()).map(request=>new URL(request.url).pathname)))).flat()}))`);assert(cache.urls.includes('/app/'));assert(cache.urls.includes('/mini.html'));assert(!cache.urls.some(url=>url.startsWith('/api/')||url.startsWith('/socket.io/')));samples.push({step:'manifest and cache',manifest,cache});
 run('set','offline','on');wait(`!navigator.onLine`);run('reload');snapshot();wait(`!!document.querySelector('.app-shell')&&!!document.querySelector('main h1')`);samples.push({step:'offline app reload',...state()});assert.equal(samples.at(-1).app,true);assert.equal(samples.at(-1).language,'en');
 for(const [url,kind] of [['http://127.0.0.1:4100/#library','app'],['http://127.0.0.1:4100/app/?invite=qa-link-no-secret#rooms','app'],['http://127.0.0.1:4100/mini.html','mini'],['http://127.0.0.1:4100/','landing']]){
  open(url);wait(kind==='app'?`!!document.querySelector('.app-shell')&&!!document.querySelector('main h1')`:kind==='mini'?`!!document.querySelector('.times')`:`!!document.querySelector('.public-site')`);const sample={step:'offline '+kind,...state()};samples.push(sample);assert.equal(sample[kind],true);assert.equal(sample.language,'en');
 }
 run('set','offline','off');open('http://127.0.0.1:4100/apple');wait(`!!document.querySelector('.public-site')`);samples.push({step:'app pathname boundary',...state()});assert.equal(samples.at(-1).app,false);
 open('http://127.0.0.1:4100/?reset=qa-expired-test-token');wait(`!!document.querySelector('.auth-form')`);samples.push({step:'legacy reset deeplink',...state()});assert.equal(samples.at(-1).app,true);
 open('http://127.0.0.1:4100/');wait(`!!document.querySelector('.public-site')`);
 await fs.writeFile(file,JSON.stringify({passed:true,samples},null,2));console.log(JSON.stringify({passed:true,file,samples:samples.map(({step,url,language,app,landing,mini})=>({step,url,language,app,landing,mini}))}));
}catch(error){await fs.writeFile(file,JSON.stringify({passed:false,error:String(error),samples,snapshot:snapshot().snapshot},null,2));throw error;}finally{run('set','offline','off');}
