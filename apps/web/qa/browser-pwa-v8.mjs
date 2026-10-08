import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {evaluate,open,run,select,snapshot,useSession,wait} from './browser.mjs';
useSession(process.env.GLUKWAVE_QA_SESSION||'gluk-pwa-v8');
const samples=[],file=process.env.GLUKWAVE_QA_OUTPUT||'work/qa/web-language-pwa-v10.json',shell=process.env.GLUKWAVE_QA_SHELL||'glukwave-shell-v10-palette';
const index=await fs.readFile('apps/web/dist/index.html','utf8'),build=index.match(/src="(\/assets\/main-[^"]+\.js)"/)[1];
const state=()=>evaluate(`({url:location.href,language:document.documentElement.lang,app:!!document.querySelector('.app-shell'),landing:!!document.querySelector('.public-site'),mini:!!document.querySelector('.times'),offline:!navigator.onLine,overflow:document.documentElement.scrollWidth>innerWidth,previewPixels:document.querySelector('.site-preview img')?.naturalWidth})`);
const inventory=()=>evaluate(`caches.keys().then(async names=>({names,entries:(await Promise.all(names.map(async name=>(await (await caches.open(name)).keys()).map(request=>({cache:name,url:new URL(request.url).pathname}))))).flat()}))`);
try{
 open('http://127.0.0.1:4100/');wait(`!!document.querySelector('.public-site')`);select('en');
 const serviceWorker=evaluate(`navigator.serviceWorker.ready.then(async registration=>{await registration.update();return {url:registration.active?.scriptURL,state:registration.active?.state,script:await fetch('/sw.js',{cache:'reload'}).then(r=>r.text())};})`);
 assert(serviceWorker.script.includes(`const SHELL='${shell}'`));
 wait(`!!navigator.serviceWorker.controller&&caches.has('${shell}')`);
 const preview=evaluate(`(async()=>{const response=await (await caches.open('${shell}')).match('/brand/app-preview.png');return response?{status:response.status,type:response.headers.get('content-type'),bytes:(await response.blob()).size}:null;})()`);
 assert.equal(preview.status,200);assert(preview.type.includes('image/png'));assert(preview.bytes>100000);
 const cache=inventory();assert.deepEqual(cache.names,[shell]);assert(cache.entries.some(entry=>entry.url===build));for(const path of ['/','/app/','/mini.html','/brand/app-preview.png'])assert(cache.entries.some(entry=>entry.url===path));assert(!cache.entries.some(entry=>entry.url.startsWith('/api/')||entry.url.startsWith('/socket.io/')));
 samples.push({step:'fresh current v8 installation',serviceWorker:{url:serviceWorker.url,state:serviceWorker.state},preview,cache});
 run('set','offline','on');wait(`!navigator.onLine`);
 for(const [url,kind] of [['http://127.0.0.1:4100/app/#settings','app'],['http://127.0.0.1:4100/app/?invite=qa-offline-v8#rooms','app'],['http://127.0.0.1:4100/mini.html','mini'],['http://127.0.0.1:4100/','landing']]){
  open(url);wait(kind==='app'?`!!document.querySelector('.app-shell')&&!!document.querySelector('main h1')`:kind==='mini'?`!!document.querySelector('.times')`:`!!document.querySelector('.public-site')`);
  const sample={step:'offline '+kind,...state()};samples.push(sample);assert(sample[kind]);assert(sample.offline);assert.equal(sample.language,'en');assert(!sample.overflow);
 }
 run('scrollintoview','.site-preview');wait(`document.querySelector('.site-preview img')?.naturalWidth===1280`);samples.push({step:'own actual app preview offline',...state()});run('screenshot',file.replace(/\.json$/,'-offline-preview.png'));
 const finalCache=inventory();assert(!finalCache.entries.some(entry=>entry.url.startsWith('/api/')||entry.url.startsWith('/socket.io/')));
 await fs.writeFile(file,JSON.stringify({passed:true,shell,build,samples,finalCache},null,2));console.log(JSON.stringify({passed:true,file,shell,build,samples:samples.map(({step,url,language,app,landing,mini,previewPixels})=>({step,url,language,app,landing,mini,previewPixels}))}));
}catch(error){await fs.writeFile(file,JSON.stringify({passed:false,error:String(error),shell,samples,snapshot:snapshot().snapshot},null,2));throw error;}
finally{run('set','offline','off');}
