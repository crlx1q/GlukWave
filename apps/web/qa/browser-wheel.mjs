import {run,evaluate} from './browser.mjs';
// CLI0.21 wheel emits at(0,0) even after hover; send trusted wheel at the measured control.
export async function wheelAt(selector,deltaY){
 const rect=evaluate(`(()=>{const r=document.querySelector(${JSON.stringify(selector)}).getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2};})()`);
 const {cdpUrl}=run('get','cdp-url'),socket=new WebSocket(cdpUrl),pending=new Map();let id=0;
 socket.addEventListener('message',event=>{const message=JSON.parse(event.data);if(!message.id)return;const call=pending.get(message.id);pending.delete(message.id);message.error?call?.reject(Error(message.error.message)):call?.resolve(message.result);});
 await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',reject,{once:true});});
 const send=(method,params={},sessionId)=>new Promise((resolve,reject)=>{const next=++id;pending.set(next,{resolve,reject});socket.send(JSON.stringify({id:next,method,params,...sessionId&&{sessionId}}));});
 try{const {targetInfos}=await send('Target.getTargets'),target=targetInfos.find(target=>target.type==='page'&&target.url.startsWith('http://127.0.0.1:5187/app/'));if(!target)throw Error('Missing isolated QA tab');const {sessionId}=await send('Target.attachToTarget',{targetId:target.targetId,flatten:true});await send('Input.dispatchMouseEvent',{type:'mouseWheel',x:rect.x,y:rect.y,deltaX:0,deltaY},sessionId);await new Promise(resolve=>setTimeout(resolve,100));await send('Target.detachFromTarget',{sessionId});}finally{socket.close();}
}
