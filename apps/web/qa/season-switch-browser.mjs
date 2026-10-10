import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {open,evaluate,run,useSession,snapshot,screenshot} from './browser.mjs';
useSession('gluk-season-switch-final');
open('http://127.0.0.1:5187/app/#settings?section=appearance');
const helper=`window.__gw=function(key){const host=document.getElementById('root'),root=host[Object.keys(host).find(name=>name.startsWith('__reactContainer$'))]?.stateNode?.current,stack=[root];while(stack.length){const fiber=stack.pop();if(!fiber)continue;const value=fiber.memoizedProps?.value;if(value&&typeof value[key]==='function')return value;if(fiber.sibling)stack.push(fiber.sibling);if(fiber.child)stack.push(fiber.child);}throw Error('Missing context '+key);};`;
const wait=async expression=>{for(let i=0;i<60;i++){if(evaluate(expression))return;await new Promise(r=>setTimeout(r,100));}throw Error(expression);};
const proof={passed:false,rows:[],screenshots:[]};
try{await wait(`!!document.querySelector('.season-settings')`);evaluate(helper);
for(const width of[320,390])for(const scale of[1,1.25])for(const language of ['en','ru','kk','uk','de','es']){
run('set','viewport',String(width),'900');evaluate(`__gw('saveSettings').saveSettings({language:${JSON.stringify(language)},fontScale:${scale},seasonalEffects:{enabled:false}})`);await wait(`document.documentElement.lang===${JSON.stringify(language)}&&!document.querySelector('.season-settings input').checked`);snapshot();run('scrollintoview','.season-settings');
const geometry=evaluate(`(()=>{const box=document.querySelector('.season-settings .switch'),input=box.querySelector('input'),visual=box.querySelector('span');return{boxWidth:box.getBoundingClientRect().width,inputHeight:input.getBoundingClientRect().height,visualWidth:visual.getBoundingClientRect().width,overflow:document.documentElement.scrollWidth>innerWidth}})()`);
assert.equal(geometry.boxWidth,44*scale);assert.equal(geometry.inputHeight,44*scale);assert.equal(geometry.visualWidth,40*scale);assert.equal(geometry.overflow,false);const off=evaluate(`getComputedStyle(document.querySelector('.season-settings .switch>span'),':after').transform`);if(language==='ru'&&width===320&&scale===1.25){const file='apps/web/qa/transport-season-switch-ru-125-320-off.png';screenshot(file);proof.screenshots.push(file);}run('check','.season-settings input[type=checkbox]');await wait(`document.querySelector('.season-settings input').checked`);await new Promise(r=>setTimeout(r,250));const on=evaluate(`getComputedStyle(document.querySelector('.season-settings .switch>span'),':after').transform`);assert.notEqual(on,off);proof.rows.push({language,width,scale,off,on,...geometry});
if(language==='ru'&&width===320){const file=`apps/web/qa/transport-season-switch-ru-${scale===1?'100':'125'}-320.png`;screenshot(file);proof.screenshots.push(file);}
}proof.browserErrors=run('errors');assert.equal(proof.browserErrors.errors.length,0);proof.passed=true;
}finally{await fs.writeFile('apps/web/qa/season-switch-proof.json',JSON.stringify(proof,null,2));run('close');}
