import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import { click,evaluate,open,ref,run,screenshot,snapshot,useSession,wait } from './browser.mjs';

useSession('gluk-language-guest');
const captures=[],samples=[],file='work/qa/web-language-final-shots.json';
const sdk=()=>evaluate(`new Promise(resolve=>__finalWidget.getPosition(position=>__finalWidget.isPaused(paused=>resolve({position:position/1000,paused,sameFrame:document.querySelector('.persistent-provider iframe')===__finalFrame,frames:document.querySelectorAll('.persistent-provider iframe').length,events:[...__finalEvents]}))))`);
const record=(name,full=false)=>{
 const target=`outputs/GlukWave-${name}-en.png`;
 if(full)run('screenshot',target,'--full');else screenshot(target);
 captures.push({file:target,...evaluate(`({url:location.href,language:document.documentElement.lang,viewport:[innerWidth,innerHeight],overflow:document.documentElement.scrollWidth>innerWidth,visibleTitle:document.querySelector('.np-track-heading h1')?.textContent||document.querySelector('main h1')?.textContent,coverPixels:document.querySelector('.album-cover img')?.naturalWidth})`)});
 if(evaluate(`!!document.querySelector('.persistent-provider iframe')`)){const sample={step:name,...sdk()};samples.push(sample);console.log(JSON.stringify(sample));}
};
try{
 open('http://127.0.0.1:4100/app/?track=soundcloud-soundcloud%3Atracks%3A293');wait(`!!document.querySelector('.shared-track')`);
 const identity=evaluate(`fetch('/api/auth/me').then(r=>r.json()).then(r=>r.user)`);assert.equal(identity,null);
 assert.equal(evaluate(`document.documentElement.lang`),'en');
 click('Listen to track');wait(`document.querySelector('.persistent-provider')?.dataset.ready==='true'`);wait(`document.querySelector('.album-cover img')?.naturalWidth===500`);
 evaluate(`window.__finalFrame=document.querySelector('.persistent-provider iframe');window.__finalWidget=SC.Widget(__finalFrame);window.__finalEvents=[];window.__finalOriginalPause=__finalWidget.pause;__finalWidget.pause=function(){__finalEvents.push({type:'widget.pause called',stack:new Error().stack,at:performance.now()});return __finalOriginalPause.apply(this,arguments);};__finalWidget.bind(SC.Widget.Events.PLAY,()=>__finalEvents.push({type:'PLAY',at:performance.now()}));__finalWidget.bind(SC.Widget.Events.PAUSE,()=>__finalEvents.push({type:'PAUSE',at:performance.now()}));document.addEventListener('click',event=>__finalEvents.push({type:'click',text:event.target.closest('button,a')?.getAttribute('aria-label')||event.target.closest('button,a')?.textContent,at:performance.now()}),true);window.__finalPaused=true;`);
 if(sdk().paused)click('Play');
 wait(`(__finalWidget.isPaused(value=>window.__finalPaused=value),!__finalPaused)`);
 const initial=sdk();
 run('set','viewport','1280','900');snapshot();record('player-desktop');
 run('set','viewport','390','844');snapshot();record('player-mobile');
 click('Collapse player');run('set','viewport','1280','900');click('Home');record('app-desktop');
 run('set','viewport','390','844');snapshot();record('app-mobile');
 // Settings remains a regular in-app route while the same external controller plays.
 run('set','viewport','1280','900');click('Settings');click(/^Language /);record('settings-desktop');
 run('set','viewport','390','844');snapshot();record('settings-mobile');
 const afterSettings=sdk();assert.equal(afterSettings.paused,false);assert.equal(afterSettings.sameFrame,true);assert(afterSettings.position>initial.position);evaluate(`__finalWidget.pause=__finalOriginalPause;`);
 open('http://127.0.0.1:4100/');run('reload');snapshot();wait(`!!document.querySelector('.platform-list a[download]')`);assert.equal(evaluate(`document.documentElement.lang`),'en');
 for(const [width,height,name] of [[1280,900,'landing-desktop'],[390,844,'landing-mobile']]){
  run('set','viewport',String(width),String(height));run('scroll','up','10000');snapshot();record(name);record(name+'-full',true);
  run('scrollintoview',ref('link','Download for Android'));snapshot();record(name+'-downloads');
 }
 const releases=evaluate(`[...document.querySelectorAll('.platform-list article')].map(node=>({text:node.innerText,download:node.querySelector('a[download]')?.getAttribute('href')||null}))`);
 assert(releases.find(row=>row.text.includes('Android'))?.download==='/api/downloads/android');assert(releases.filter(row=>/Windows|iOS/.test(row.text)).every(row=>row.download===null));
 assert(captures.every(capture=>!capture.overflow));
 await fs.writeFile(file,JSON.stringify({passed:true,guest:true,provider:'Official SoundCloud Widget SDK',initial,afterSettings,samples,releases,captures},null,2));
 console.log(JSON.stringify({passed:true,file,captures:captures.length,initial,afterSettings,releases}));
}catch(error){await fs.writeFile(file,JSON.stringify({passed:false,error:String(error),samples,captures,snapshot:snapshot().snapshot},null,2));throw error;}
