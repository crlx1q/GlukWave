import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {open,evaluate,run,useSession,snapshot,click,select,screenshot} from './browser.mjs';

// An isolated muted browser verifies the real SDK without disturbing the listener.
process.env.AGENT_BROWSER_ARGS='--mute-audio';
useSession('gluk-v8-production-muted-'+Date.now());
const file='work/qa/web-v8-continuity.json',proof={passed:false,mutedBrowser:true,samples:[],captures:[]};
const copies=JSON.parse(await fs.readFile('apps/web/src/locales/en.json','utf8'));
const index=await fs.readFile('apps/web/dist/index.html','utf8');
proof.build=index.match(/src="(\/assets\/main-[^"]+\.js)"/)[1];
const helper=(await fs.readFile('apps/web/qa/browser-v7-sync.mjs','utf8')).match(/const helpers=`([\s\S]*?)`;/)[1];
async function poll(expression){const end=Date.now()+25000;while(Date.now()<end){if(evaluate(expression))return;await new Promise(resolve=>setTimeout(resolve,350));}throw Error('Timed out: '+expression);}
const probe=step=>{const data=evaluate(`new Promise(resolve=>__v8Widget.getPosition(position=>__v8Widget.isPaused(paused=>resolve({position:position/1000,paused,sameFrame:document.querySelector('.persistent-provider iframe')===__v8Frame,sameWidget:SC.Widget(__v8Frame)===__v8Widget,frames:document.querySelectorAll('.persistent-provider iframe').length,language:document.documentElement.lang,theme:document.documentElement.dataset.theme,overflow:document.documentElement.scrollWidth>innerWidth,events:[...__v8Events]}))))`);assert(!data.paused,step+' unexpectedly paused');assert(data.sameFrame&&data.sameWidget&&data.frames===1);assert(!data.overflow);proof.samples.push({step,...data});return data;};
const capture=name=>{const file='outputs/preview-v8-'+name+'.png';screenshot(file);proof.captures.push(file);};
try{
 open('http://127.0.0.1:4100/app/#home');await poll(`!!document.querySelector('.app-shell')`);evaluate(helper);
 evaluate(`__gwContext('saveSettings').saveSettings({language:'en',reducedMotion:true})`);await poll(`document.documentElement.lang==='en'`);
 open('http://127.0.0.1:4100/app/?track=soundcloud-soundcloud%3Atracks%3A293');await poll(`!!document.querySelector('.shared-track')`);click(copies['copy.214']);await poll(`document.querySelector('.persistent-provider')?.dataset.ready==='true'`);evaluate(helper);
 evaluate(`window.__v8Frame=document.querySelector('.persistent-provider iframe');window.__v8Widget=SC.Widget(__v8Frame);window.__v8Events=[];__v8Widget.bind(SC.Widget.Events.PLAY,()=>__v8Events.push('PLAY'));__v8Widget.bind(SC.Widget.Events.PAUSE,()=>__v8Events.push('PAUSE'));__gwContext('playTrack').command({command:'volume',volume:0});`);
 if(evaluate(`new Promise(resolve=>__v8Widget.isPaused(resolve))`))click('Play');
 await poll(`new Promise(resolve=>__v8Widget.getPosition(position=>__v8Widget.isPaused(paused=>resolve(!paused&&position>5000))))`);
 const first=probe('actual muted SDK playback');run('set','viewport','1440','1000');capture('player-desktop');run('set','viewport','390','844');capture('player-mobile');probe('mobile full player');
 click(copies['copy.646']);run('set','viewport','1440','1000');click(copies['copy.023']);click(/^Language/);
 for(const language of ['ru','kk','uk','de','es','en']){select(language);await poll(`document.documentElement.lang==='${language}'`);probe('language '+language);}
 for(const theme of ['light','dark','amoled']){evaluate(`__gwContext('saveSettings').saveSettings({theme:${JSON.stringify(theme)}})`);await poll(`document.documentElement.dataset.theme==='${theme}'`);probe('theme '+theme);}
 evaluate(`__gwContext('navigate').navigate('home')`);await poll(`!!document.querySelector('.wave-hero')`);probe('home after settings');run('set','viewport','390','844');probe('mobile home');
 assert(proof.samples.at(-1).position>first.position);assert(!proof.samples.at(-1).events.includes('PAUSE'));
 evaluate(`__gwContext('playTrack').command({command:'pause'})`);await poll(`new Promise(resolve=>__v8Widget.isPaused(resolve))`);proof.intentionalFinalPause=true;proof.passed=true;
}catch(error){proof.error=String(error);proof.snapshot=snapshot().snapshot;throw error;}
finally{await fs.writeFile(file,JSON.stringify(proof,null,2)+'\n');console.log(JSON.stringify({passed:proof.passed,file,build:proof.build,samples:proof.samples.length,mutedBrowser:true,error:proof.error}));}
