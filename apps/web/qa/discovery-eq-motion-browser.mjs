import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {open,evaluate,run,useSession,snapshot,screenshot} from './browser.mjs';
process.env.AGENT_BROWSER_ARGS='--mute-audio';
const stamp=Date.now();useSession(`discovery-eq-motion-${stamp}`);
const proof={passed:false,scope:'Actual React EQ reset button, existing original QA audio, own muted browser and normal autoplay policy.'};
const wait=code=>evaluate(`(async()=>{for(let i=0;i<160;i++){if(eval(${JSON.stringify(code)}))return true;await new Promise(r=>setTimeout(r,70));}throw Error(${JSON.stringify('Wait '+code)});})()`);
const helper=`window.__gw=function(key){const host=document.getElementById('root'),root=host[Object.keys(host).find(n=>n.startsWith('__reactContainer$'))]?.stateNode?.current,stack=[root];while(stack.length){const f=stack.pop();if(!f)continue;const v=f.memoizedProps?.value;if(v&&typeof v[key]==='function')return v;if(f.sibling)stack.push(f.sibling);if(f.child)stack.push(f.child);}throw Error(key);};`;
try{
 open('http://127.0.0.1:5194/app/#home');snapshot();wait(`!!document.querySelector('.wave-hero')`);evaluate(helper);
 evaluate(`(async()=>{await fetch('/api/qa/polish',{method:'POST',body:JSON.stringify({scenario:'design'})});await __gw('saveSettings').saveSettings({theme:'dark',fontScale:1,reducedMotion:false,appearance:{radius:30,speed:1},equalizer:{enabled:true,bands:[-3,-2,0,2,4,2,0,-2,-3,1],preamp:0}});await __gw('command').playTrack(__gw('saveSettings').library.tracks[0],__gw('saveSettings').library.tracks);return true;})()`);
 wait(`__gw('command').playback?.kind==='audio'`);run('click','.player-center .main-play');snapshot();wait(`__gw('command').state.playing`);evaluate(`__gw('command').setFull(true,'player')`);wait(`!!document.querySelector('.full-player.is-open')`);run('click','.np-eq');snapshot();wait(`!!document.querySelector('.eq-popover')`);
 evaluate(`window.__curveValues=[];window.__curveObserver=new MutationObserver(()=>__curveValues.push(document.querySelector('.eq-curve polyline').getAttribute('points')));__curveObserver.observe(document.querySelector('.eq-curve polyline'),{attributes:true,attributeFilter:['points']});`);
 run('click','.eq-popover header button:nth-of-type(2)');snapshot();wait(`__gw('saveSettings').settings.equalizer.bands.every(v=>v===0)&&new Set(__curveValues).size>3&&document.querySelector('.eq-curve polyline').getAttribute('points').split(' ').every(p=>p.endsWith(',72'))`);
 proof.curve=evaluate(`({intermediateFrames:new Set(__curveValues).size,finalPoints:document.querySelector('.eq-curve polyline').getAttribute('points'),radius:getComputedStyle(document.querySelector('.eq-popover')).borderTopLeftRadius})`);assert(proof.curve.finalPoints.split(' ').every(point=>point.endsWith(',72')));assert.equal(proof.curve.radius,'17.4px');
 evaluate(`__curveObserver.disconnect()`);proof.screenshot=`work/qa/discovery-eq-motion-${stamp}.png`;screenshot(proof.screenshot);proof.passed=true;
}catch(error){proof.error=String(error);throw error;}finally{await fs.writeFile('work/qa/discovery-eq-motion-proof.json',JSON.stringify(proof,null,2));run('close');}
