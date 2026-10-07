import fs from 'node:fs/promises';
const [endpoint,mode='inspect',argument,output] = process.argv.slice(2);
const url=new URL(endpoint);
if(url.protocol!=='ws:'||url.hostname!=='127.0.0.1')throw new Error('This QA helper only attaches to the supplied isolated local browser.');
const socket=new WebSocket(url),pending=new Map();let sequence=0;
socket.addEventListener('message',event=>{const message=JSON.parse(event.data),entry=pending.get(message.id);if(!entry)return;pending.delete(message.id);clearTimeout(entry.timer);message.error?entry.reject(new Error(message.error.message)):entry.resolve(message.result);});
const call=(method,params={},sessionId)=>new Promise((resolve,reject)=>{const id=++sequence,timer=setTimeout(()=>{pending.delete(id);reject(new Error(`Timed out: ${method}`));},15000);pending.set(id,{resolve,reject,timer});socket.send(JSON.stringify({id,method,params,...(sessionId?{sessionId}:{})}));});
try{
 await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',reject,{once:true});});
 const {targetInfos}=await call('Target.getTargets'),pages=targetInfos.filter(target=>target.type==='page'&&target.url.startsWith('http://127.0.0.1:4100/'));
 if(pages.length!==1)throw new Error(`Expected one isolated QA page, found ${pages.length}`);
 const {sessionId}=await call('Target.attachToTarget',{targetId:pages[0].targetId,flatten:true});
 const evaluate=async expression=>{const {result,exceptionDetails}=await call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true},sessionId);if(exceptionDetails)throw new Error(exceptionDetails.text);return result.value;};
 if(mode==='enable'){
  const [width=390,height=844]=(argument||'390,844').split(',').map(Number);
  await call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:true},sessionId);
  await call('Emulation.setTouchEmulationEnabled',{enabled:true,maxTouchPoints:1},sessionId);
 }else if(mode==='swipe'||mode==='cancel'||mode==='partial'){
  await call('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false},sessionId);
  await call('Emulation.setTouchEmulationEnabled',{enabled:true,maxTouchPoints:1},sessionId);
  await new Promise(resolve=>setTimeout(resolve,150));
  const beforeScroll=await evaluate('document.querySelector(".lyrics-lines")?.scrollTop');
  const [x,y,endX,endY]=(argument||'').split(',').map(Number);if([x,y,endX,endY].some(value=>!Number.isFinite(value)))throw new Error('Supply startX,startY,endX,endY.');
  await evaluate('window.__touchEvents=[];window.__touchProbe=event=>__touchEvents.push({type:event.type,pointerType:event.pointerType,trusted:event.isTrusted,x:event.clientX,y:event.clientY});["pointerdown","pointermove","pointerup","pointercancel"].forEach(name=>window.addEventListener(name,__touchProbe,{passive:true}));');
  const dispatch=(type,px,py)=>call('Input.dispatchTouchEvent',{type,touchPoints:type==='touchEnd'||type==='touchCancel'?[]:[{x:px,y:py,id:1,radiusX:4,radiusY:4,force:1}]},sessionId);
  await dispatch('touchStart',x,y);
  for(let step=1;step<=12;step++){await dispatch('touchMove',x+(endX-x)*step/12,y+(endY-y)*step/12);await new Promise(resolve=>setTimeout(resolve,18));}
  let partial;
  if(mode==='partial'){partial=await evaluate('({cover:(()=>{const r=document.querySelector(".np-cover-growth .album-object").getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height}})(),mini:(()=>{const r=document.querySelector(".player-art").getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height}})(),reveal:document.querySelector(".full-player").style.getPropertyValue("--reveal")})');if(output){const {data}=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:false},sessionId);await fs.writeFile(output,Buffer.from(data,'base64'));}}
  await dispatch(mode==='cancel'||mode==='partial'?'touchCancel':'touchEnd');
  await new Promise(resolve=>setTimeout(resolve,650));
  const result=await evaluate('({events:__touchEvents,open:document.querySelector(".full-player")?.classList.contains("is-open"),dragging:document.querySelector(".full-player")?.classList.contains("is-dragging"),title:document.querySelector(".player-track-info b")?.textContent,fullTransform:getComputedStyle(document.querySelector(".full-player")).transform,viewport:[innerWidth,innerHeight],horizontalOverflow:document.documentElement.scrollWidth>innerWidth})');
  const afterScroll=await evaluate('document.querySelector(".lyrics-lines")?.scrollTop');
  await evaluate('["pointerdown","pointermove","pointerup","pointercancel"].forEach(name=>window.removeEventListener(name,__touchProbe));');console.log(JSON.stringify({...result,...(partial?{partial}:{}),...(beforeScroll!==undefined?{beforeScroll,afterScroll}:{})},null,2));if(output&&mode!=='partial'){const {data}=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:false},sessionId);await fs.writeFile(output,Buffer.from(data,'base64'));}
 }else if(mode==='media'){
  await call('Emulation.setEmulatedMedia',{features:[{name:'prefers-reduced-motion',value:argument||'reduce'}]},sessionId);
 }else if(mode==='screenshot'){
  const {data}=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:false},sessionId);await fs.writeFile(argument,Buffer.from(data,'base64'));
 }
 await call('Target.detachFromTarget',{sessionId});
}finally{socket.close();}
