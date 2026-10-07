import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import { click,evaluate,open,run,screenshot,select,snapshot,useSession,wait } from './browser.mjs';
const copies=Object.fromEntries(await Promise.all(['en','ru','kk','uk','de','es'].map(async code=>[code,JSON.parse(await fs.readFile(`apps/web/src/locales/${code}.json`,'utf8'))]))),samples=[],file='work/qa/web-language-responsive.json';
const geometry=()=>evaluate(`({lang:document.documentElement.lang,viewport:[innerWidth,innerHeight],width:document.documentElement.scrollWidth,overflow:document.documentElement.scrollWidth>innerWidth,heading:document.querySelector('h1')?.textContent,mobileTabs:[...document.querySelectorAll('.mobile-nav button')].filter(node=>node.getBoundingClientRect().width>0).length,full:document.querySelector('.full-player')?.classList.contains('is-open'),cover:document.querySelector('.album-cover img')?.naturalWidth})`);
try{
 useSession('gluk-language-guest');open('http://127.0.0.1:4100/');run('reload');snapshot();wait(`!!document.querySelector('.public-site')`);
 for(const code of ['en','ru','kk','uk','de','es']){
  select(code);wait(`document.documentElement.lang==='${code}'`);
  for(const [width,height] of [[320,760],[390,844],[768,1024],[1280,900]]){
   run('set','viewport',String(width),String(height));const sample={step:'landing',...geometry()};samples.push(sample);assert.equal(sample.overflow,false);assert.equal(sample.lang,code);assert.equal(sample.heading,copies[code]['landing.title1']+copies[code]['landing.title2']);
   if(code==='en'&&(width===390||width===1280)){run('scroll','up','10000');screenshot(`work/qa/web-language-landing-${width}.png`);run('screenshot',`work/qa/web-language-landing-${width}-full.png`,'--full');}
   if(code==='de'&&width===320){run('scroll','up','10000');screenshot('work/qa/web-language-landing-de-320.png');}
  }
 }
 select('en');click(copies.en['landing.open'],'link');wait(`!!document.querySelector('.app-shell')`);click('Settings');click(/^Language /);
 for(const code of ['en','ru','kk','uk','de','es']){
  select(code);wait(`document.documentElement.lang==='${code}'`);
  for(const [width,height] of [[320,760],[390,844],[768,1024],[1280,625]]){
   run('set','viewport',String(width),String(height));const sample={step:'settings',...geometry()};samples.push(sample);assert.equal(sample.overflow,false);assert.equal(sample.lang,code);assert.equal(sample.mobileTabs,width<=850?3:0);
   if(code==='de'&&width===320)screenshot('work/qa/web-language-settings-de-320.png');
   if(code==='en'&&width===1280)screenshot('work/qa/web-language-settings-short-desktop.png');
  }
 }
 select('en');
 useSession('gluk-web-v6');if(evaluate(`document.querySelector('.full-player')?.classList.contains('is-open')`)){run('press','Escape');snapshot();}
 run('set','viewport','1280','900');click('Settings');click(/^Language /);select('de');click('Player erweitern');
 for(const [width,height] of [[320,760],[390,844],[768,1024],[1280,900]]){run('set','viewport',String(width),String(height));const sample={step:'full player German',...geometry()};samples.push(sample);assert.equal(sample.overflow,false);assert.equal(sample.full,true);if(width===390)screenshot('work/qa/web-language-player-de-390.png');}
 click(copies.de['copy.652']);click(copies.de['copy.646']);click(copies.de['copy.639']);assert.equal(evaluate(`document.querySelector('.np-tabs button.selected')?.textContent`),copies.de['copy.651']);
 click(copies.de['copy.653']);click(copies.de['copy.646']);click(copies.de['copy.639']);assert.equal(evaluate(`document.querySelector('.np-tabs button.selected')?.textContent`),copies.de['copy.651']);
 click(copies.de['copy.646']);click(copies.de['copy.023']);click(/^Sprache /);select('en');click(copies.en['copy.639']);run('set','viewport','390','844');screenshot('work/qa/web-language-player-390.png');run('set','viewport','1280','900');screenshot('work/qa/web-language-player-desktop.png');
 await fs.writeFile(file,JSON.stringify({passed:true,reopenPlayerFromLyricsAndQueue:true,samples},null,2));console.log(JSON.stringify({passed:true,file,samples:samples.length,reopenPlayerFromLyricsAndQueue:true}));
}catch(error){await fs.writeFile(file,JSON.stringify({passed:false,error:String(error),samples,snapshot:snapshot().snapshot},null,2));throw error;}
