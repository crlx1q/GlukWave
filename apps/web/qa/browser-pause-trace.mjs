import fs from 'node:fs/promises';
import {click,evaluate,run,snapshot,useSession} from './browser.mjs';
useSession('gluk-language-guest');
evaluate(`window.__pauseTrace=[];window.__pauseWidget=SC.Widget(document.querySelector('.persistent-provider iframe'));window.__pauseOriginal=__pauseWidget.pause;__pauseWidget.pause=function(){__pauseTrace.push({type:'widget.pause called',stack:new Error().stack,at:performance.now()});return __pauseOriginal.apply(this,arguments);};__pauseWidget.bind(SC.Widget.Events.PLAY,()=>__pauseTrace.push({type:'sdk PLAY',at:performance.now()}));__pauseWidget.bind(SC.Widget.Events.PAUSE,()=>__pauseTrace.push({type:'sdk PAUSE',at:performance.now()}));document.addEventListener('click',event=>__pauseTrace.push({type:'click',text:event.target.closest('button,a')?.getAttribute('aria-label')||event.target.closest('button,a')?.textContent,at:performance.now()}),true);`);
const samples=[];
const probe=step=>{const data=evaluate(`new Promise(resolve=>__pauseWidget.getPosition(position=>__pauseWidget.isPaused(paused=>resolve({position:position/1000,paused,full:document.querySelector('.full-player')?.classList.contains('is-open'),viewport:[innerWidth,innerHeight],sameFrame:document.querySelector('.persistent-provider iframe')===__finalFrame,frameSrc:document.querySelector('.persistent-provider iframe')?.src,events:[...__pauseTrace]}))))`);samples.push({step,...data});console.log(JSON.stringify({step,position:data.position,paused:data.paused,full:data.full,last:data.events.slice(-3)}));};
try{
 probe('before');click('Play');probe('explicit Play');
 run('set','viewport','1280','900');snapshot();probe('1280 resize');
 click('Home');probe('Home');click('Expand player');probe('Expand');
 run('set','viewport','390','844');snapshot();probe('390 full resize');
 click('Collapse player');probe('Collapse');
 run('set','viewport','1280','900');snapshot();probe('1280 app resize');
 click('Home');probe('Home again');click('Settings');probe('Settings');click(/^Language /);probe('Language section');
 run('set','viewport','390','844');snapshot();probe('390 settings resize');
 await fs.writeFile('work/qa/web-language-pause-trace.json',JSON.stringify({samples},null,2));
}catch(error){await fs.writeFile('work/qa/web-language-pause-trace.json',JSON.stringify({error:String(error),samples,snapshot:snapshot().snapshot},null,2));throw error;}
finally{evaluate(`__pauseWidget.pause=__pauseOriginal;`);}
