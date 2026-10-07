import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import { click,evaluate,run,snapshot,wait } from './browser.mjs';
try{
 if(evaluate(`document.querySelector('.full-player')?.classList.contains('is-open')`)){run('press','Escape');snapshot();}
 click('Library');click(/^verification-audio /);click('Flickermood Forss');click('Expand player');
 // Request an unavailable variant in this isolated browser to exercise a real image error.
 evaluate(`(()=>{window.__coverLoadErrors=[];const image=document.querySelector('.album-cover img');image.addEventListener('error',event=>__coverLoadErrors.push({trusted:event.isTrusted,source:image.src}),{once:true});const url=new URL(image.src);url.pathname=url.pathname.replace('-t500x500.jpg','-qa-unavailable-t500x500.jpg');image.src=url.href;})()`);
 wait(`document.querySelector('.album-cover img')?.naturalWidth===100`);
 const proof=evaluate(`({source:document.querySelector('.album-cover img').src,naturalWidth:document.querySelector('.album-cover img').naturalWidth,skeleton:!!document.querySelector('.album-cover .art-skeleton'),title:document.querySelector('.np-track-heading h1').textContent,errors:window.__coverLoadErrors})`);
 assert(proof.source.endsWith('-large.jpg'));assert.equal(proof.naturalWidth,100);assert.equal(proof.skeleton,false);assert.equal(proof.title,'Flickermood');assert.equal(proof.errors[0]?.trusted,true);
 await fs.writeFile('work/qa/web-language-artwork-fallback.json',JSON.stringify({passed:true,method:'A genuine network error for an unavailable SoundCloud image variant triggers the Art fallback and loads the real original 100px image',...proof},null,2));console.log(JSON.stringify({passed:true,...proof}));
}finally{run('network','unroute');}
