import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import { click,evaluate,fill,open,select,snapshot,useSession,wait } from './browser.mjs';
useSession('gluk-language-guest');
const copies=Object.fromEntries(await Promise.all(['ru','de','en'].map(async code=>[code,JSON.parse(await fs.readFile(`apps/web/src/locales/${code}.json`,'utf8'))]))),samples=[],file='work/qa/web-language-existing-account.json';
try{
 click(/^Konto /);click(copies.de['copy.042']);wait(`!localStorage.getItem('gw-user')&&document.documentElement.lang==='ru'`);
 click(copies.ru['copy.023']);click(/^Язык /);select('ru');samples.push({step:'Russian guest before existing login',language:evaluate(`document.documentElement.lang`)});
 click(copies.ru['copy.204']);fill('textbox',copies.ru['copy.249'],'qa@example.test');fill('textbox',copies.ru['copy.250'],'Local-qa-passphrase-2026');click(copies.ru['copy.254']);
 wait(`JSON.parse(localStorage.getItem('gw-user')||'{}').username==='qa_check'&&document.documentElement.lang==='en'`);
 const loggedIn=evaluate(`fetch('/api/settings').then(r=>r.json()).then(payload=>({server:payload.settings.language,html:document.documentElement.lang,choice:localStorage.getItem('gw-language-choice'),user:JSON.parse(localStorage.getItem('gw-user')).username}))`);samples.push({step:'Existing English account wins over guest Russian',...loggedIn});assert.equal(loggedIn.server,'en');assert.equal(loggedIn.html,'en');assert.equal(loggedIn.choice,'en');
 open('http://127.0.0.1:4100/');wait(`!!document.querySelector('.public-site')&&document.documentElement.lang==='en'`);samples.push({step:'Account language on public arrival',language:evaluate(`document.documentElement.lang`),heading:evaluate(`document.querySelector('h1').textContent`)});
 await fs.writeFile(file,JSON.stringify({passed:true,samples},null,2));console.log(JSON.stringify({passed:true,file,samples}));
}catch(error){await fs.writeFile(file,JSON.stringify({passed:false,error:String(error),samples,snapshot:snapshot().snapshot},null,2));throw error;}
