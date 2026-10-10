import {open,evaluate,run,useSession,snapshot,screenshot} from './browser.mjs';
useSession('gluk-season-switch-capture');
open('http://127.0.0.1:5187/app/#settings?section=appearance');
await new Promise(resolve=>setTimeout(resolve,800));
evaluate(`window.__gw=function(key){const host=document.getElementById('root'),root=host[Object.keys(host).find(name=>name.startsWith('__reactContainer$'))]?.stateNode?.current,stack=[root];while(stack.length){const fiber=stack.pop();if(!fiber)continue;const value=fiber.memoizedProps?.value;if(value&&typeof value[key]==='function')return value;if(fiber.sibling)stack.push(fiber.sibling);if(fiber.child)stack.push(fiber.child);}throw Error(key);};`);
run('set','viewport','320','900');
for(const enabled of [false,true]){evaluate(`__gw('saveSettings').saveSettings({language:'ru',fontScale:1.25,seasonalEffects:{enabled:${enabled},mode:'snow'}})`);await new Promise(resolve=>setTimeout(resolve,500));evaluate(`(()=>{const offset=document.querySelector('.season-settings').getBoundingClientRect().top;window.scrollBy(0,offset-30);})()`);snapshot();screenshot(`apps/web/qa/transport-season-switch-ru-125-320${enabled?'':'-off'}.png`);}
run('close');
