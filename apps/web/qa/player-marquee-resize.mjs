import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {open,evaluate,run,useSession,snapshot,screenshot} from './browser.mjs';
process.env.AGENT_BROWSER_ARGS='--mute-audio,--autoplay-policy=no-user-gesture-required';
useSession('gluk-marquee-resize-'+Date.now());
const proof={passed:false,scope:'Actual isolated browser, original audio fixture; viewport/theme/scroll transitions with one unchanged long track',cases:[]};
const wait=async expression=>{const end=Date.now()+20000;while(Date.now()<end){if(evaluate(expression))return;snapshot();await new Promise(resolve=>setTimeout(resolve,100));}throw Error('Wait '+expression);};
const helper=`window.__resizeContext=function(key){const host=document.getElementById('root'),root=host[Object.keys(host).find(name=>name.startsWith('__reactContainer$'))]?.stateNode?.current,stack=[root];while(stack.length){const fiber=stack.pop();if(!fiber)continue;const value=fiber.memoizedProps?.value;if(value&&typeof value[key]==='function')return value;if(fiber.sibling)stack.push(fiber.sibling);if(fiber.child)stack.push(fiber.child);}throw Error('Missing context '+key);};`;
try{
 open('http://127.0.0.1:5189/app/#library');await wait(`!!document.querySelector('.track-main')`);evaluate(helper);
 evaluate(`void __resizeContext('command').playTrack(__resizeContext('saveSettings').library.tracks.find(t=>t.id==='hls-one'))`);await wait(`__resizeContext('command').state.playing&&!__resizeContext('command').trackLoading`);
 for(const theme of ['light','dark','amoled']){
  evaluate(`void __resizeContext('saveSettings').saveSettings({language:'en',theme:'${theme}',fontScale:1,reducedMotion:false,seasonalEffects:{enabled:false}})`);await wait(`document.documentElement.dataset.theme==='${theme}'`);
  for(const [w,h] of [[1440,1000],[768,1000],[375,812],[1440,1000]]){
   run('set','viewport',String(w),String(h));snapshot();run('scroll','down','550');snapshot();run('scroll','up','3000');snapshot();await new Promise(resolve=>setTimeout(resolve,400));
   const labels=evaluate(`Array.from(document.querySelectorAll('.player-track-info .scrolling-label')).map(e=>({text:e.textContent,overflow:e.dataset.overflow,moving:e.dataset.moving,width:e.clientWidth,textWidth:e.firstElementChild.scrollWidth,animation:getComputedStyle(e.firstElementChild).animationName,rect:e.getBoundingClientRect().toJSON()}))`);
   proof.cases.push({theme,w,labels});
   assert(labels.every(label=>label.overflow!=='true'||label.moving==='true'),JSON.stringify(proof.cases.at(-1)));
   assert(labels.every(label=>label.overflow==='true'||label.moving==='false'),JSON.stringify(proof.cases.at(-1)));
  }
 }
 proof.passed=true;
}catch(error){proof.error=String(error);screenshot('apps/web/qa/player-marquee-resize-failure.png');throw error;}finally{await fs.writeFile('apps/web/qa/player-marquee-resize-proof.json',JSON.stringify(proof,null,2));run('close');}
