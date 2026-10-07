import fs from 'node:fs/promises';
import {click,evaluate,open,run,screenshot,snapshot,useSession,wait} from './browser.mjs';
useSession('gluk-language-guest');
const result={samples:[]},file='work/qa/web-language-original-pause-repro.json';
try{
 open('http://127.0.0.1:4100/app/?track=soundcloud-soundcloud%3Atracks%3A293');wait(`!!document.querySelector('.shared-track')`);click('Listen to track');wait(`document.querySelector('.persistent-provider')?.dataset.ready==='true'`);wait(`document.querySelector('.album-cover img')?.naturalWidth===500`);
 evaluate(`window.__reproFrame=document.querySelector('.persistent-provider iframe');window.__reproWidget=SC.Widget(__reproFrame);window.__reproPaused=true;__reproWidget.isPaused(value=>window.__reproPaused=value);window.__reproEvents=[];window.__reproPauseOriginal=__reproWidget.pause;window.__reproPlayOriginal=__reproWidget.play;__reproWidget.pause=function(){__reproEvents.push({type:'widget.pause called',stack:new Error().stack,at:performance.now()});return __reproPauseOriginal.apply(this,arguments);};__reproWidget.play=function(){__reproEvents.push({type:'widget.play called',stack:new Error().stack,at:performance.now()});return __reproPlayOriginal.apply(this,arguments);};__reproWidget.bind(SC.Widget.Events.PLAY,()=>__reproEvents.push({type:'sdk PLAY',at:performance.now()}));__reproWidget.bind(SC.Widget.Events.PAUSE,()=>__reproEvents.push({type:'sdk PAUSE',at:performance.now()}));document.addEventListener('click',event=>__reproEvents.push({type:'click',text:event.target.closest('button,a')?.getAttribute('aria-label')||event.target.closest('button,a')?.textContent,at:performance.now()}),true);`);
 result.asyncStartValue=evaluate(`__reproPaused`);if(result.asyncStartValue)click('Play');
 wait(`(__reproWidget.isPaused(value=>window.__reproPaused=value),!__reproPaused)`);
 const probe=()=>evaluate(`new Promise(resolve=>__reproWidget.getPosition(position=>__reproWidget.isPaused(paused=>resolve({position:position/1000,paused,sameFrame:document.querySelector('.persistent-provider iframe')===__reproFrame,events:[...__reproEvents]}))))`);
 result.initial=probe();
 run('set','viewport','1280','900');snapshot();screenshot('work/qa/pause-repro-1-player-desktop.png');
 run('set','viewport','390','844');snapshot();screenshot('work/qa/pause-repro-2-player-mobile.png');
 click('Collapse player');run('set','viewport','1280','900');click('Home');screenshot('work/qa/pause-repro-3-app-desktop.png');
 run('set','viewport','390','844');snapshot();screenshot('work/qa/pause-repro-4-app-mobile.png');
 run('set','viewport','1280','900');click('Settings');click(/^Language /);screenshot('work/qa/pause-repro-5-settings-desktop.png');
 run('set','viewport','390','844');snapshot();screenshot('work/qa/pause-repro-6-settings-mobile.png');
 result.after=probe();result.reproduced=result.after.paused;console.log(JSON.stringify(result));
}catch(error){result.error=String(error);result.snapshot=snapshot().snapshot;throw error;}
finally{await fs.writeFile(file,JSON.stringify(result,null,2));evaluate(`__reproWidget.pause=__reproPauseOriginal;__reproWidget.play=__reproPlayOriginal;`);}
