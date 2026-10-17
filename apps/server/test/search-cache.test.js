import test from 'node:test';
import assert from 'node:assert/strict';
import {providerSearchCache,searchSnapshot} from '../src/search-cache.js';

test('provider work coalesces while slow, expires after completion and keeps callers isolated',async()=>{
 let time=0,calls=0,finish;
 const lookup=providerSearchCache({ttl:30,now:()=>time}),input=[{id:'a'}];input.artists=[{name:'Actual artist'}];
 const read=()=>{calls++;return new Promise(resolve=>finish=resolve);};
 const first=lookup('provider/account/query',read);await Promise.resolve();time=100;
 const second=lookup('provider/account/query',read);assert.equal(calls,1);finish(input);
 const [a,b]=await Promise.all([first,second]);assert.deepEqual(a.artists,input.artists);a[0].id='changed';a.artists[0].name='changed';
 assert.equal(b[0].id,'a');assert.equal(b.artists[0].name,'Actual artist');
 assert.equal((await lookup('provider/account/query',()=>assert.fail('still fresh')))[0].id,'a');
 time=131;assert.deepEqual(await lookup('provider/account/query',async()=>[{id:'renewed'}]),[{id:'renewed'}]);
 assert.deepEqual(await lookup('provider/other/query',async()=>[{id:'other'}]),[{id:'other'}]);
});
test('failed provider work is evicted and a later request retries',async()=>{
 const lookup=providerSearchCache();await assert.rejects(lookup('key',async()=>{throw Error('temporary');}),/temporary/);
 assert.deepEqual(await lookup('key',async()=>[]),[]);
});
test('first paint returns ready providers, late work stays shared and failures stay explicit',async()=>{
 const lookup=providerSearchCache();let finish,calls=0;
 const slow=lookup('slow',()=>{calls++;return new Promise(resolve=>finish=resolve);});
 const partial=await searchSnapshot([Promise.resolve(['ready']),slow,Promise.reject(Error('failed'))],5);
 assert.deepEqual(partial.map(row=>row.status),['fulfilled','pending','rejected']);
 const full=lookup('slow',()=>assert.fail('must join pending work'));finish(['later']);
 assert.deepEqual(await full,['later']);assert.equal(calls,1);
 assert.equal(partial[1].status,'pending','the first response must keep its pending marker while later work finishes');
 assert.deepEqual((await searchSnapshot([slow]))[0],{status:'fulfilled',value:['later']});
});
