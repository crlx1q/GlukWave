import test from 'node:test';
import assert from 'node:assert/strict';
import {needsWaveTail,recommendationQuery} from '../src/wave-session.ts';
import {PlaybackWarmup} from '../src/playback-warmup.ts';
import {AudioGesture} from '../src/audio-gesture.ts';
import {OptimisticControls} from '../src/optimistic-controls.ts';

test('search and playlist tails continue, explicit repeats and foreign tracks do not',()=>{
 assert(needsWaveTail(['a'],'a','off'));
 assert(needsWaveTail(['a','b'],'b','off'));
 assert(!needsWaveTail(['a','b'],'a','off'));
 assert(!needsWaveTail(['a'],'a','all',true));
 assert(!needsWaveTail(['a'],'a','one'));
 assert(needsWaveTail(['a'],'a','one',true));
 assert(!needsWaveTail([],'foreign','off'));
 assert(!needsWaveTail(['a'],'foreign','off'));
 const query=new URLSearchParams(recommendationQuery({mode:'discovery',mood:'calm',seedTrackId:'youtube-A&B'},Array.from({length:110},(_,i)=>'track-'+i),'batch'));
 assert.equal(query.get('seedTrackId'),'youtube-A&B');
 assert.equal(query.get('mode'),'discovery');assert.equal(query.get('mood'),'calm');
 assert.equal(query.get('exclude').split(',').length,100);
});

test('preparation shares concurrent resolution, retries failures and expires descriptors',async()=>{
 const cache=new PlaybackWarmup();cache.reset('account-a');let calls=0,release;
 const job=()=>{calls++;return new Promise(resolve=>{release=resolve;});};
 const first=cache.get('one',job),second=cache.get('one',job);
 assert.equal(calls,1);release({kind:'audio',url:'/one'});
 assert.deepEqual(await first,await second);await cache.get('one',job);assert.equal(calls,1);
 await assert.rejects(cache.get('bad',async()=>{throw Error('temporary');}));
 assert.equal((await cache.get('bad',async()=>({kind:'audio',url:'/recovered'}))).url,'/recovered');
 const oldNow=Date.now;try{Date.now=()=>oldNow()+61000;assert.equal((await cache.get('one',async()=>({kind:'audio',url:'/renewed'}))).url,'/renewed');}finally{Date.now=oldNow;}
});

test('preparation is bounded and a previous account cannot populate the next account',async()=>{
 const cache=new PlaybackWarmup();cache.reset('a');let finish;
 const old=cache.get('same',()=>new Promise(resolve=>{finish=resolve;}));
 cache.reset('b');await cache.get('same',async()=>({kind:'audio',url:'/b'}));
 finish({kind:'audio',url:'/a'});await old;
 assert.equal((await cache.get('same',()=>{throw Error('must be cached');})).url,'/b');
 for(const id of ['two','three','four'])await cache.get(id,async()=>({kind:'audio',url:'/'+id}));
 let fresh=0;await cache.get('same',async()=>{fresh++;return {kind:'audio',url:'/new'};});assert.equal(fresh,1);
});

test('media priming requires a trusted gesture, uses the same empty element and preserves an existing source',async()=>{
 const original=Object.getOwnPropertyDescriptor(globalThis,'navigator');
 let active=false,plays=0,pauses=0,src='';
 Object.defineProperty(globalThis,'navigator',{configurable:true,value:{userActivation:{get isActive(){return active;}}}});
 const audio={getAttribute:()=>src,set src(value){src=value;},play:async()=>{plays++;},pause:()=>{pauses++;}};
 try{
  const gesture=new AudioGesture();gesture.prime(audio);assert.equal(plays,0);
  active=true;gesture.prime(audio);assert.equal(plays,1);assert.match(src,/^blob:/);assert(gesture.owns(audio));
  await new Promise(resolve=>setImmediate(resolve));assert.equal(pauses,1);
  src='/real-track';gesture.prime(audio);assert.equal(plays,1);assert(!gesture.owns(audio));
 }finally{if(original)Object.defineProperty(globalThis,'navigator',original);else delete globalThis.navigator;}
});

test('unconfirmed toggles suppress canonical heartbeats; a held slider does not',()=>{
 const controls=new OptimisticControls(),state={repeat:'off',volume:.8};
 const draft=controls.begin('same',state,{volume:.2},true);assert(!controls.committing());
 const repeat=controls.begin('same',state,{repeat:'one'});assert(controls.committing());
 assert.equal(controls.overlay(state).repeat,'one');assert.equal(controls.broadcast(state).repeat,'off');
 controls.observe({repeat:'off'});assert.equal(controls.overlay(state).repeat,'one');
 controls.settle(repeat,true,true);assert(!controls.committing());
 assert.equal(controls.broadcast(state).volume,.8);controls.settle(draft,false);
});
