import test from 'node:test';import assert from 'node:assert/strict';
import {OptimisticControls} from '../src/optimistic-controls.ts';
const initial={volume:.8,playing:true,position:12,shuffle:false,repeat:'off'};
test('held volume previews do not become canonical; cancel returns latest accepted volume',()=>{
 const edits=new OptimisticControls();edits.begin('a',initial,{volume:.2},true);edits.begin('a',initial,{volume:.4},true);
 assert.equal(edits.overlay(initial).volume,.4);assert.equal(edits.broadcast(edits.overlay(initial)).volume,.8);
 edits.observe({volume:.7});assert.equal(edits.overlay(initial).volume,.4);assert.deepEqual(edits.cancelDraft('volume'),{volume:.7});
});
test('an older rejected toggle cannot remove the newer choice; later failure rolls back to accepted ACK',()=>{
 const edits=new OptimisticControls(),first=edits.begin('a',initial,{shuffle:true}),second=edits.begin('a',initial,{shuffle:false});
 assert.deepEqual(edits.settle(first,false),{});assert.equal(edits.overlay(initial).shuffle,false);
 edits.observe({shuffle:true});assert.deepEqual(edits.settle(second,false),{shuffle:true});
 const third=edits.begin('a',initial,{repeat:'one'});assert.deepEqual(edits.settle(third,true,true),{repeat:'one'});
});
test('canonical room ACK releases only matching fields and keeps newer play/seek presentation',()=>{
 const edits=new OptimisticControls(),pause=edits.begin('a',initial,{playing:false}),seek=edits.begin('a',initial,{position:90});
 edits.observe({playing:false,position:12});assert.deepEqual(edits.settle(pause,true),{playing:false});
 assert.equal(edits.overlay(initial).position,90);edits.observe({position:90});assert.deepEqual(edits.settle(seek,true),{position:90});
});
test('account/output/room changes invalidate queued work, old ACK and rollback',()=>{
 const edits=new OptimisticControls(),old=edits.begin('account-a/room-a/pc',initial,{volume:.2});
 edits.reset('account-b/phone',{...initial,volume:.6});assert.equal(edits.current(old),false);
 assert.deepEqual(edits.settle(old,false),{});assert.equal(edits.overlay({...initial,volume:.6}).volume,.6);
});
test('a scope change cannot promote a held draft into the next track baseline',()=>{
 const edits=new OptimisticControls();edits.begin('first',initial,{volume:.2},true);
 const visible=edits.overlay(initial);assert.deepEqual(edits.ensure('second',visible),{volume:initial.volume});
 // No pending value survives; the transition baseline restored the old accepted level.
 const next=edits.begin('second',visible,{volume:.3});assert.deepEqual(edits.settle(next,false),{volume:initial.volume});
});
test('queued superseded controls are discarded while distinct controls stay ordered',()=>{
 const edits=new OptimisticControls(),first=edits.begin('a',initial,{shuffle:true}),second=edits.begin('a',initial,{shuffle:false}),third=edits.begin('a',initial,{repeat:'all'});
 assert.equal(edits.superseded(first),true);assert.equal(edits.superseded(second),false);assert.equal(edits.superseded(third),false);
});
test('returning to the same account/output does not resurrect an ACK from its previous lifetime',()=>{
 const edits=new OptimisticControls(),old=edits.begin('a',initial,{volume:.2});edits.reset('b',initial);edits.reset('a',initial);
 assert.equal(edits.current(old),false);assert.deepEqual(edits.settle(old,true,true),{});
 const next=edits.begin('a',initial,{volume:.3});assert.deepEqual(edits.settle(next,false),{volume:initial.volume});
});
