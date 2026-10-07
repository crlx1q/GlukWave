import { execFileSync } from 'node:child_process';
import path from 'node:path';

const cli=path.resolve('node_modules/agent-browser/bin/agent-browser-win32-x64.exe');
export let session=process.env.GLUKWAVE_QA_SESSION||'gluk-web-v6';
export const useSession=name=>{session=name;};
export function run(...args){
 let raw;try{raw=execFileSync(cli,['--session',session,...args,'--json'],{encoding:'utf8',timeout:35000,maxBuffer:4*1024*1024});}catch(error){if(!error.stdout)throw error;raw=error.stdout;}
 const result=JSON.parse(raw);if(!result.success)throw new Error(result.error||raw);return result.data;
}
export const snapshot=()=>run('snapshot','-i');
export function ref(role,name){const state=snapshot(),match=Object.entries(state.refs).find(([,entry])=>entry.role===role&&(name instanceof RegExp?name.test(entry.name):entry.name===name));if(!match)throw new Error(`Missing ${role}: ${name}\n${state.snapshot}`);return '@'+match[0];}
export function click(name,role='button'){run('scrollintoview',ref(role,name));const item=ref(role,name);run('click',item);return snapshot();}
export function select(language){run('select',ref('combobox',/.*/),language);return snapshot();}
export function fill(role,name,value){run('fill',ref(role,name),value);return snapshot();}
export function evaluate(code){const result=run('eval','-b',Buffer.from(code).toString('base64'));return result.result;}
export function wait(expression){run('wait','--fn',expression);return snapshot();}
export function open(url){try{run('--executable-path','C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe','open',url);}catch(error){if(!String(error).includes('Operation timed out')||snapshot().origin!==url)throw error;}return snapshot();}
export const screenshot=file=>run('screenshot',path.resolve(file));
