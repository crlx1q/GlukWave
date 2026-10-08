import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {open,evaluate,useSession,snapshot} from './browser.mjs';

useSession('gluk-v7-acoustics');
open('http://127.0.0.1:5173/app/#home');snapshot();
const result=evaluate(`(async()=>{
 const {createEqualizer,configureEqualizer}=await import('/src/audio-processing.ts');
 async function render(settings,frequency=1000){
  const context=new OfflineAudioContext(1,48000,48000),oscillator=context.createOscillator(),sourceGain=context.createGain();
  oscillator.frequency.value=frequency;sourceGain.gain.value=.05;oscillator.connect(sourceGain);
  const filters=createEqualizer(context,sourceGain);configureEqualizer({context,...filters},settings);filters.output.connect(context.destination);oscillator.start();
  const buffer=await context.startRendering(),data=buffer.getChannelData(0);let sum=0;for(let index=24000;index<data.length;index++)sum+=data[index]*data[index];return Math.sqrt(sum/24000);
 }
 const flat={enabled:true,preamp:0,bands:Array(10).fill(0)},boost={...flat,bands:flat.bands.map((_,index)=>index===5?6:0)};
 const baseline=await render(flat),raised=await render(boost),compensated=await render({...boost,preamp:-6}),disabled=await render({...boost,enabled:false,preamp:-6}),outside=await render(boost,125),outsideBase=await render(flat,125);
 const db=(value,reference=baseline)=>20*Math.log10(value/reference);
 return {baseline,boostDb:db(raised),compensatedDb:db(compensated),disabledDb:db(disabled),outsideBandDb:db(outside,outsideBase),sampleRate:48000};
})()`);
assert(Math.abs(result.baseline-.05/Math.sqrt(2))<.0001);
assert(result.boostDb>5.5&&result.boostDb<6.5);
assert(Math.abs(result.compensatedDb)<.3);
assert(Math.abs(result.disabledDb)<.1);
assert(Math.abs(result.outsideBandDb)<.3);
await fs.mkdir('work/qa',{recursive:true});await fs.writeFile('work/qa/web-v7-acoustics.json',JSON.stringify({passed:true,...result},null,2));console.log(JSON.stringify({passed:true,...result}));
