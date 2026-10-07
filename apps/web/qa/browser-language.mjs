import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import { click,evaluate,run,select,snapshot,wait } from './browser.mjs';

const file='work/qa/web-language-soundcloud.json',samples=[];
const probe=()=>evaluate(`new Promise(resolve=>{__languageWidget.getPosition(position=>__languageWidget.isPaused(paused=>resolve({language:document.documentElement.lang,position:position/1000,paused,sameFrame:document.querySelector('.persistent-provider iframe')===__languageFrame,sameWidget:SC.Widget(__languageFrame)===__languageWidget,frames:document.querySelectorAll('.persistent-provider iframe').length,title:document.querySelector('.player-track-info b')?.textContent,artist:document.querySelector('.player-track-info small')?.textContent,events:[...__languageEvents],headings:[...document.querySelectorAll('main h1,main h2')].map(node=>node.textContent)})));})`);
try{
 if(evaluate(`document.querySelector('.full-player')?.classList.contains('is-open')`)){run('press','Escape');snapshot();}
 if(evaluate(`document.querySelector('.player-track-info b')?.textContent`)!=='Flickermood'){click('Library');click('Flickermood Forss');}
 wait(`document.querySelector('.persistent-provider')?.dataset.ready==='true'`);
 evaluate(`window.__languageFrame=document.querySelector('.persistent-provider iframe');window.__languageWidget=SC.Widget(__languageFrame);window.__languageEvents=[];__languageWidget.bind(SC.Widget.Events.PLAY,()=>__languageEvents.push('PLAY'));__languageWidget.bind(SC.Widget.Events.PAUSE,()=>__languageEvents.push('PAUSE'));window.__languagePaused=true;__languageWidget.isPaused(value=>window.__languagePaused=value);`);
 wait(`(__languageWidget.isPaused(value=>window.__languagePaused=value),!__languagePaused)`);
 samples.push({step:'initial',...probe()});
 click('Settings');click(/^Language Make yourself/);
 for(const code of ['ru','kk','uk','de','es','en']){
  select(code);wait(`document.documentElement.lang==='${code}'`);
  const sample=probe();samples.push({step:'language '+code,...sample,snapshot:snapshot().snapshot});
  assert.equal(sample.language,code);assert.equal(sample.paused,false);assert.equal(sample.sameFrame,true);assert.equal(sample.sameWidget,true);assert.equal(sample.frames,1);assert.equal(sample.title,'Flickermood');assert.equal(sample.artist,'Forss');
 }
 assert(samples.at(-1).position>samples[0].position);assert.deepEqual(samples.at(-1).events,samples[0].events);
 click('Expand player');samples.push({step:'fullscreen',...probe()});
 run('press','Escape');snapshot();click('Home');samples.push({step:'home',...probe()});
 click('Library');samples.push({step:'library',...probe()});
 assert(samples.every(item=>!item.paused&&item.sameFrame&&item.sameWidget&&item.frames===1));
 await fs.writeFile(file,JSON.stringify({passed:true,provider:'Official SoundCloud Widget SDK',samples},null,2));
 console.log(JSON.stringify({passed:true,file,positions:samples.map(({step,position})=>({step,position})),events:samples.at(-1).events}));
}catch(error){await fs.writeFile(file,JSON.stringify({passed:false,error:String(error),samples},null,2));throw error;}
