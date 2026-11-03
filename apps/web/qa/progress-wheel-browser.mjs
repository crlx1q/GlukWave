// Start player-polish-preview-server.mjs first. Uses its isolated audio and account.
import assert from 'node:assert/strict';
import {open,evaluate,run,useSession} from './browser.mjs';

process.env.AGENT_BROWSER_ARGS='--mute-audio,--autoplay-policy=no-user-gesture-required';
useSession(`gluk-progress-wheel-${Date.now()}`);

async function until(expression,timeout=18000){
 const deadline=Date.now()+timeout;
 while(Date.now()<deadline){
  if(evaluate(expression))return;
  await new Promise(resolve=>setTimeout(resolve,100));
 }
 throw Error(`Timed out: ${expression}`);
}

async function frames(selector,expression,action='',duration=650){
 evaluate(`(()=>{
  const node=document.querySelector(${JSON.stringify(selector)});
  if(!node)throw Error('Missing range');
  const read=()=>${expression}, rows=[read()],started=performance.now();
  window.__controlFrames=null;
  ${action}
  const frame=()=>{rows.push(read());if(performance.now()-started<${duration})requestAnimationFrame(frame);else window.__controlFrames=rows;};
  requestAnimationFrame(frame);
 })()`);
 await until('window.__controlFrames!==null');
 return evaluate('window.__controlFrames');
}

function smooth(rows,label){
 const deltas=rows.slice(1).map((value,index)=>value-rows[index]);
 assert(rows.at(-1)-rows[0]>.2,label);
 assert(deltas.filter(delta=>delta>0).length>20,JSON.stringify({label,rows}));
 assert(deltas.every(delta=>delta>=-.025&&delta<.35),JSON.stringify({label,rows}));
 return {label,frames:rows.length,advancing:deltas.filter(delta=>delta>0).length};
}

try{
 open('http://127.0.0.1:5189/app/#library');
 await until(`!!document.querySelector('.track-main')`);
 evaluate(`window.__controlContext=function(method){
  const host=document.getElementById('root'),key=Object.keys(host).find(name=>name.startsWith('__reactContainer$'));
  const stack=[host[key].stateNode.current];
  while(stack.length){const fiber=stack.pop(),value=fiber.memoizedProps?.value;
   if(value&&typeof value[method]==='function')return value;
   if(fiber.sibling)stack.push(fiber.sibling);if(fiber.child)stack.push(fiber.child);
  }
  throw Error('Context unavailable: '+method);
 };window.__controlPlayer=()=>__controlContext('command');
 void __controlPlayer().playTrack(__controlContext('saveSettings').library.tracks.find(track=>track.id==='hls-one'))`);
 await until('__controlPlayer().state.playing&&!__controlPlayer().trackLoading');
 run('set','viewport','1440','900');
 evaluate(`(()=>{
  const prototype=HTMLMediaElement.prototype,time=Object.getOwnPropertyDescriptor(prototype,'currentTime'),ready=Object.getOwnPropertyDescriptor(prototype,'readyState');
  const fixture=media=>media.currentSrc.includes('/qa-silence.wav');
  Object.defineProperty(prototype,'currentTime',{...time,get(){const value=time.get.call(this);return fixture(this)?Math.floor(value):value;}});
  Object.defineProperty(prototype,'readyState',{...ready,get(){const value=ready.get.call(this);if(fixture(this)){window.__controlAudio=this;return Math.min(2,value);}return value;}});
  window.__restoreControlAudio=()=>{Object.defineProperty(prototype,'currentTime',time);Object.defineProperty(prototype,'readyState',ready);};
 })()`);
 await until('!!window.__controlAudio');
 evaluate(`window.__controlAudio.dispatchEvent(new Event('stalled'))`);
 assert.equal(evaluate('__controlPlayer().trackLoading'),false);
 const desktop=smooth(await frames('.player .progress-line input','Number(node.value)'),'desktop seek');
 run('set','viewport','375','812');
 await until(`getComputedStyle(document.querySelector('.player-card-progress')).display!=='none'`);
 const collapsed=smooth(await frames('.player-card-progress','parseFloat(node.closest(".player").style.getPropertyValue("--track-progress"))*2.4'),'phone mini fill');
 evaluate('__controlPlayer().setFull(true)');
 await until(`document.querySelector('.full-player')?.classList.contains('is-open')`);
 const expanded=smooth(await frames('.full-seek input','Number(node.value)'),'phone expanded seek');
 evaluate(`__restoreControlAudio();__controlPlayer().setFull(false);void __controlPlayer().command({command:'pause'});void __controlPlayer().command({command:'volume',volume:.5})`);
 run('set','viewport','1440','900');
 await until(`!__controlPlayer().state.playing&&Number(document.querySelector('.volume-control input').value)===.5`);
 const paused=await frames('.player .progress-line input','Number(node.value)','',300);
 assert(paused.every(position=>position===paused[0]),JSON.stringify(paused));
 await until(`!matchMedia('(prefers-reduced-motion: reduce)').matches&&document.documentElement.dataset.motion!=='reduce'`);
 run('hover','.volume-control input');
 await until(`document.querySelector('.volume-thumb-hint')?.style.visibility==='visible'`);
 const wheel=delta=>`node.dispatchEvent(new WheelEvent('wheel',{deltaY:${delta},bubbles:true,cancelable:true}));`;
 const volume=await frames('.volume-control input','Number(node.value)',wheel(-120),350);
 assert.equal(volume[0],.5);
 assert.equal(volume.at(-1),.55);
 assert(volume.filter(value=>value>.5&&value<.55).length>=3,JSON.stringify(volume));
 const back=await frames('.volume-control input','Number(node.value)',wheel(120),350);
 assert.equal(back[0],.55);
 assert.equal(back.at(-1),.5);
 assert(back.filter(value=>value>.5&&value<.55).length>=3,JSON.stringify(back));
 const thumbOffset=evaluate(`(()=>{const input=document.querySelector('.volume-control input'),hint=document.querySelector('.volume-thumb-hint'),rect=input.getBoundingClientRect(),bubble=hint.getBoundingClientRect();return Math.abs(bubble.left+bubble.width/2-(rect.left+rect.width/2));})()`);
 assert(thumbOffset<1,`Hint drift ${thumbOffset}px`);
 const drag=evaluate(`(()=>{const rect=document.querySelector('.volume-control input').getBoundingClientRect();return{start:Math.round(rect.left+rect.width/2),end:Math.round(rect.left+7+(rect.width-14)*.76),y:Math.round(rect.top+rect.height/2)};})()`);
 run('mouse','move',String(drag.start),String(drag.y));
 run('mouse','down','left');
 run('mouse','move',String(drag.end),String(drag.y));
 const heldVolume=evaluate(`Number(document.querySelector('.volume-control input').value)`);
 assert(Math.abs(heldVolume-.76)<.021,`Held drag selected ${heldVolume}`);
 run('mouse','up','left');
 await until(`Math.abs(Number(localStorage.getItem('gw-device-volume'))-${heldVolume})<.0001`);
 run('focus','.player .progress-line input');
 run('press','Home');
 await until(`__controlPlayer().state.position===0&&Number(document.querySelector('.player .progress-line input').value)===0`);
 console.log(JSON.stringify({desktop,collapsed,expanded,paused:true,wheelUp:volume,wheelDown:back,thumbOffset,heldVolume,keyboardSeek:true}));
}finally{run('close');}
