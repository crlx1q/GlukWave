import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {open,evaluate,run,useSession,snapshot,screenshot} from './browser.mjs';
process.env.AGENT_BROWSER_ARGS='--mute-audio,--autoplay-policy=no-user-gesture-required';
useSession('gluk-expanded-layout-'+Date.now());
const proof={passed:false,scope:'Actual isolated browser expanded player; original audio fixture. No physical/live-provider check.',cases:[]};
const wait=async expression=>{const end=Date.now()+20000;while(Date.now()<end){if(evaluate(expression))return;snapshot();await new Promise(resolve=>setTimeout(resolve,100));}throw Error('Wait '+expression);};
const helper=`window.__expandedContext=function(key){const host=document.getElementById('root'),root=host[Object.keys(host).find(name=>name.startsWith('__reactContainer$'))]?.stateNode?.current,stack=[root];while(stack.length){const fiber=stack.pop();if(!fiber)continue;const value=fiber.memoizedProps?.value;if(value&&typeof value[key]==='function')return value;if(fiber.sibling)stack.push(fiber.sibling);if(fiber.child)stack.push(fiber.child);}throw Error('Missing context '+key);};`;
try{
 open('http://127.0.0.1:5189/app/#library');await wait(`!!document.querySelector('.track-main')`);evaluate(helper);
 evaluate(`void __expandedContext('command').playTrack(__expandedContext('saveSettings').library.tracks.find(t=>t.id==='hls-one'))`);await wait(`__expandedContext('command').state.playing&&!__expandedContext('command').trackLoading`);
 const cases=[...['light','dark','amoled'].flatMap(theme=>[1440,768,375,320].map(w=>({language:'en',theme,w,scale:1}))),...['en','ru','kk','uk','de','es'].flatMap(language=>[375,320].map(w=>({language,theme:'light',w,scale:1.25})))];
 for(const item of cases){
  evaluate(`void __expandedContext('saveSettings').saveSettings({language:'${item.language}',theme:'${item.theme}',fontScale:${item.scale},reducedMotion:false,seasonalEffects:{enabled:false}})`);await wait(`document.documentElement.lang==='${item.language}'&&document.documentElement.dataset.theme==='${item.theme}'`);
  run('set','viewport',String(item.w),String(item.w<600?812:1000));snapshot();evaluate(`__expandedContext('command').setFull(true)`);await wait(`document.querySelector('.full-player')?.classList.contains('is-open')`);snapshot();
  const result=evaluate(`(()=>{const seek=document.querySelector('.full-player .full-seek'),row=document.querySelector('.np-transport-row'),times=Array.from(seek.querySelectorAll(':scope>span')).map(e=>e.getBoundingClientRect().toJSON()),controls=document.querySelector('.np-controls').getBoundingClientRect(),rect=row.getBoundingClientRect(),region=document.querySelector(innerWidth<851?'.full-player .np-layout':'.full-player .np-listening'),thumb=getComputedStyle(region,'::-webkit-scrollbar');return{times,row:rect.toJSON(),overlaps:times.some(t=>t.bottom>rect.top-6),horizontalOverflow:Array.from(row.querySelectorAll('button')).filter(e=>{const b=e.getBoundingClientRect();return b.width&&(b.left<controls.left-1||b.right>controls.right+1)}).map(e=>e.ariaLabel||e.title),pageOverflow:document.documentElement.scrollWidth>innerWidth,scrollbar:{width:thumb.width,thumb:getComputedStyle(region,'::-webkit-scrollbar-thumb').backgroundColor,buttons:getComputedStyle(region,'::-webkit-scrollbar-button').display}}})()`);
  proof.cases.push({...item,...result});assert.equal(result.overlaps,false,JSON.stringify(proof.cases.at(-1)));assert.deepEqual(result.horizontalOverflow,[],JSON.stringify(proof.cases.at(-1)));assert.equal(result.pageOverflow,false);assert.equal(result.scrollbar.width,'4px');assert.equal(result.scrollbar.buttons,'none');
  if(item.language==='en'&&item.scale===1&&item.theme==='light')screenshot(`apps/web/qa/player-expanded-polish-${item.w}.png`);
  evaluate(`__expandedContext('command').setFull(false)`);await wait(`!document.querySelector('.full-player')?.classList.contains('is-open')`);
 }
 proof.passed=true;
}catch(error){proof.error=String(error);screenshot('apps/web/qa/player-expanded-polish-failure.png');throw error;}finally{await fs.writeFile('apps/web/qa/player-expanded-layout-proof.json',JSON.stringify(proof,null,2));run('close');}
