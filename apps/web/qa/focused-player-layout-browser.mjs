import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {open,evaluate,run,useSession,snapshot,screenshot} from './browser.mjs';
process.env.AGENT_BROWSER_ARGS='--mute-audio';
const stamp=Date.now(),proof={passed:false,layouts:[],screenshots:[],checks:[],scope:'Real React application, original audio and cover assets on own5190; normal autoplay policy; physical sound muted.'};
useSession(`focused-layout-${stamp}`);
const wait=async code=>{for(let i=0;i<160;i++){if(evaluate(code))return;await new Promise(r=>setTimeout(r,80));}throw Error(`Wait: ${code}`);};
const shot=name=>{const file=`work/qa/focused-player-layout-${stamp}-${name}.png`;screenshot(file);proof.screenshots.push(file);};
const probe=()=>evaluate(`(()=>{const rect=n=>n.getBoundingClientRect().toJSON(),full=document.querySelector('.full-player'),listening=full.querySelector('.np-listening'),layout=full.querySelector('.np-layout'),transport=full.querySelector('.np-transport-row');return {full:rect(full),header:rect(full.querySelector('.np-header')),cover:rect(full.querySelector('.album-object')),title:rect(full.querySelector('.np-track-heading')),listening:rect(listening),scrollTop:layout.scrollTop,scrollHeight:listening.scrollHeight,clientHeight:listening.clientHeight,scrollColor:getComputedStyle(layout).scrollbarColor,display:getComputedStyle(transport.querySelector('.transport')).display,buttons:Array.from(transport.querySelectorAll('button')).map(n=>({label:n.getAttribute('aria-label')||n.title,rect:rect(n)}))};})()`);
function check(data,width,height,defaultView){
 assert(Math.abs(data.full.width-width)<2&&Math.abs(data.full.height-height)<2,JSON.stringify(data));
 assert.equal(data.display,'flex');assert.equal(data.buttons.length,6);
 assert(data.cover.top>=data.header.bottom+3,`Cover overlaps header: ${JSON.stringify(data)}`);
 assert(data.cover.bottom<=data.title.top+2,`Cover overlaps title: ${JSON.stringify(data)}`);
 for(const button of data.buttons){const b=button.rect;assert(b.left>=-1&&b.right<=width+1&&b.top>=0&&b.bottom<=height+1,JSON.stringify(button));}
 for(let i=0;i<data.buttons.length;i++)for(let j=i+1;j<data.buttons.length;j++){
  const a=data.buttons[i],b=data.buttons[j],x=Math.min(a.rect.right,b.rect.right)-Math.max(a.rect.left,b.rect.left),y=Math.min(a.rect.bottom,b.rect.bottom)-Math.max(a.rect.top,b.rect.top);
  assert(!(x>1&&y>1),`Intersecting controls ${a.label}/${b.label}: ${x}x${y}`);
  assert(Math.abs((a.rect.top+a.rect.bottom)/2-(b.rect.top+b.rect.bottom)/2)<2,`Staggered controls: ${JSON.stringify(data.buttons)}`);
 }
 assert.notEqual(data.scrollColor,'auto');
 if(defaultView&&width>=1280)assert(data.scrollHeight<=data.clientHeight,`Unnecessary desktop scrolling: ${JSON.stringify(data)}`);
}
try{
 open('http://127.0.0.1:5190/app/#home');snapshot();await wait(`!!document.querySelector('.wave-hero')`);
 evaluate(`window.__gw=function(key){const host=document.getElementById('root'),root=host[Object.keys(host).find(n=>n.startsWith('__reactContainer$'))]?.stateNode?.current,stack=[root];while(stack.length){const f=stack.pop();if(!f)continue;const v=f.memoizedProps?.value;if(v&&typeof v[key]==='function')return v;if(f.sibling)stack.push(f.sibling);if(f.child)stack.push(f.child);}throw Error(key);};`);
 await wait(`__gw('saveSettings').settingsSync==='saved'`);
 evaluate(`(async()=>{await fetch('/api/qa/polish',{method:'POST',body:JSON.stringify({scenario:'design'})});await __gw('saveSettings').saveSettings({language:'en',theme:'dark',fontScale:1.25,lyricsUnderCover:false,reducedMotion:true,appearance:{cover3d:false,radius:24}});await __gw('command').playTrack(__gw('saveSettings').library.tracks.find(t=>t.id==='hls-two'),__gw('saveSettings').library.tracks);})()`);
 await wait(`__gw('command').playback?.kind==='audio'`);run('click','.player-center .main-play');snapshot();await wait(`__gw('command').state.playing`);
 evaluate(`__gw('command').setFull(true,'player')`);await wait(`!!document.querySelector('.full-player.is-open')`);
 const sizes=process.env.FOCUSED_LAYOUT_DESKTOP?[[1440,950],[1280,820]]:[[1440,950],[1280,820],[390,844],[375,812],[320,820]];
 for(const theme of ['dark','amoled','light'])for(const [width,height] of sizes){
  run('set','viewport',String(width),String(height));evaluate(`void __gw('saveSettings').saveSettings({theme:'${theme}'})`);await wait(`document.documentElement.dataset.theme==='${theme}'`);snapshot();
  const resized=probe();check(resized,width,height,true);assert.equal(resized.scrollTop,0);shot(`${theme}-${width}-centered`);
  run('click','.np-lyrics-toggle');snapshot();await wait(`!!document.querySelector('.np-detail-lyrics .lyrics-lines')`);
  const lyrics=probe();check(lyrics,width,height,false);shot(`${theme}-${width}-lyrics`);
  // A lyric view can scroll independently; returning to the centered player must start at its cover.
  evaluate(`document.querySelector('.np-layout').scrollTop=120`);
  run('click','.np-lyrics-toggle');snapshot();await wait(`!document.querySelector('.np-detail-pane')`);
  const reopened=probe();check(reopened,width,height,true);assert.equal(reopened.scrollTop,0);
  proof.layouts.push({theme,width,height,resized,lyrics,reopened});
 }
 run('set','viewport','375','812');evaluate(`void __gw('saveSettings').saveSettings({theme:'amoled'})`);await wait(`document.documentElement.dataset.theme==='amoled'`);run('click','.np-eq');snapshot();await wait(`!!document.querySelector('.eq-popover')`);run('click','.eq-preset-trigger');snapshot();await wait(`!!document.querySelector('.eq-preset-options')`);shot('amoled-375-preset-list');run('press','Escape');snapshot();run('press','Escape');snapshot();await wait(`!document.querySelector('.eq-popover')`);
 proof.checks.push(`${proof.layouts.length} actual layouts across three themes at125%; all six transport/EQ controls remain in one row, pairwise nonintersecting and within viewport.`);
 proof.checks.push('Actual cover remains below the fixed header and above title after persistent window resizing and after returning from a scrolled lyrics view.');
 proof.checks.push('Desktop centered content fits without unnecessary vertical scrolling; fallback/detail scrollbars are explicitly themed.');
 proof.errors=run('errors');assert(!proof.errors.errors?.length,JSON.stringify(proof.errors));proof.passed=true;
}catch(error){proof.error=String(error);try{proof.snapshot=snapshot().snapshot;shot('failure');}catch{}throw error;}finally{await fs.writeFile('work/qa/focused-player-layout-proof.json',JSON.stringify(proof,null,2));run('close');}
