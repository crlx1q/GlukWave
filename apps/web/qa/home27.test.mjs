import test from 'node:test';
import assert from 'node:assert/strict';
import {normalizeHomePins} from '../src/home-pins.ts';

test('home pins restore order and bounded type-specific data without accepting corrupt entries',()=>{
 const pins=[{id:'list',type:'playlist',playlistId:'owned'},{id:'liked',type:'likes'},{id:'genre',type:'mix',genre:' jazz ',mood:'calm'}];
 assert.deepEqual(normalizeHomePins(pins),[pins[0],pins[1],{...pins[2],genre:'jazz'}]);
 assert.deepEqual(normalizeHomePins([{id:'bad',type:'script',url:'evil'},...pins,pins[0],{id:'empty',type:'mix',genre:''},{id:'missing',type:'playlist'}]),normalizeHomePins(pins));
 assert.equal(normalizeHomePins(Array.from({length:30},(_,i)=>({id:'p'+i,type:'likes'}))).length,12);
 assert.deepEqual(normalizeHomePins(null),[]);
});
