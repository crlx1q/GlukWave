import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import { click,evaluate,fill,open,run,select,snapshot,useSession,wait } from './browser.mjs';
useSession('gluk-language-guest');
const ru=JSON.parse(await fs.readFile('apps/web/src/locales/ru.json','utf8'));
const file='work/qa/web-language-account.json',samples=[];
const account=()=>evaluate(`Promise.all([fetch('/api/auth/me').then(r=>r.json()),fetch('/api/settings',{headers:{'Accept-Language':document.documentElement.lang}}).then(r=>r.json())]).then(([me,payload])=>({user:me.user?{id:me.user.id,displayName:me.user.displayName}:null,language:payload.settings?.language,htmlLanguage:document.documentElement.lang,choice:localStorage.getItem('gw-language-choice'),pending:me.user?JSON.parse(localStorage.getItem('gw-settings-pending:'+me.user.id)||'{}'):null}))`);
try{
 select('ru');samples.push({step:'guest Russian',...evaluate(`({language:document.documentElement.lang,choice:localStorage.getItem('gw-language-choice'),guest:JSON.parse(localStorage.getItem('gw-settings:guest')||'null')?.language})`)});
 click(ru['landing.open'],'link');wait(`!!document.querySelector('.app-shell')`);
 click(ru['copy.204']);click(ru['copy.255']);
 const id='langqa_'+Date.now().toString(36),email=id+'@example.test';
 fill('textbox',ru['copy.245'],'Музыка QA language');fill('textbox',ru['copy.247'],id);fill('textbox',ru['copy.249'],email);fill('textbox',ru['copy.250'],'Local-qa-passphrase-2026');
 click(ru['copy.255']);wait(`!!localStorage.getItem('gw-user')&&!document.querySelector('.auth-form')`);
 wait(`!localStorage.getItem('gw-settings-pending:'+JSON.parse(localStorage.getItem('gw-user')).id)`);
 const registered=account();samples.push({step:'registered from Russian guest',email,...registered});
 assert.equal(registered.language,'ru');assert.equal(registered.htmlLanguage,'ru');assert.equal(registered.choice,'ru');assert.equal(registered.user.displayName,'Музыка QA language');
 open('http://127.0.0.1:4100/app/#settings');wait(`document.querySelector('main h1')&&document.documentElement.lang==='ru'`);samples.push({step:'registration reload',...account()});
 assert.equal(samples.at(-1).language,'ru');assert.equal(samples.at(-1).htmlLanguage,'ru');
 await fs.writeFile(file,JSON.stringify({passed:true,samples},null,2));console.log(JSON.stringify({passed:true,file,email,language:registered.language}));
}catch(error){await fs.writeFile(file,JSON.stringify({passed:false,error:String(error),samples,snapshot:snapshot().snapshot},null,2));throw error;}
