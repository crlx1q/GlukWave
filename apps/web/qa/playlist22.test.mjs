import test from 'node:test';
import assert from 'node:assert/strict';
import {LibraryEdits,setLiked,replacePlaylist,mergePlaylistCover} from '../src/library-edits.ts';
const empty=()=>({tracks:[],likedIds:[],playlists:[{id:'list',name:'Original',trackIds:[]}],history:[]});
const deferred=()=>{let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no;});return {promise,resolve,reject};};
test('likes are immediate, ordered, and an older failure does not undo a later click',async()=>{
 let rendered;const edits=new LibraryEdits(empty(),value=>rendered=value);edits.reset('A',empty());
 const first=deferred(),second=deferred(),requests=[];
 const one=edits.mutate('like:song',value=>setLiked(value,'song',true),()=>{requests.push(true);return first.promise;},value=>setLiked(value,'song',true));
 const failed=assert.rejects(one,/offline/);
 const two=edits.mutate('like:song',value=>setLiked(value,'song',false),()=>{requests.push(false);return second.promise;},value=>setLiked(value,'song',false));
 assert.deepEqual(rendered.likedIds,[]);assert(edits.pending);await Promise.resolve();await Promise.resolve();assert.deepEqual(requests,[true]);
 first.reject(new Error('offline'));await failed;await Promise.resolve();await Promise.resolve();assert.deepEqual(rendered.likedIds,[]);
 second.resolve({});await two;assert.deepEqual(requests,[true,false]);assert(!edits.pending);assert.deepEqual(rendered.likedIds,[]);
});
test('fresh snapshots overlay pending edits, stale reads cannot erase acknowledged changes',async()=>{
 const edits=new LibraryEdits(empty(),()=>{});edits.reset('A',empty());const stale=edits.revision,gate=deferred();
 const operation=edits.mutate('playlist:list',value=>replacePlaylist(value,{...value.playlists[0],trackIds:['song']}),()=>gate.promise,(value,result)=>replacePlaylist(value,result));
 assert.equal(edits.snapshot(empty(),stale),false);const whilePending=edits.revision;
 assert(edits.snapshot(empty(),whilePending));assert.deepEqual(edits.value.playlists[0].trackIds,['song']);
 gate.resolve({id:'list',name:'Original',trackIds:['song']});await operation;
 assert.equal(edits.snapshot(empty(),whilePending),false);assert.deepEqual(edits.value.playlists[0].trackIds,['song']);
});
test('account changes isolate late results and queued mutations',async()=>{
 const edits=new LibraryEdits(empty(),()=>{});edits.reset('A',empty());const gate=deferred();let calls=0;
 const first=edits.mutate('like:song',value=>setLiked(value,'song',true),()=>{calls++;return gate.promise;},value=>setLiked(value,'song',true));
 const second=edits.mutate('like:song',value=>setLiked(value,'song',false),async()=>{calls++;},value=>setLiked(value,'song',false));
 const rejected=Promise.all([assert.rejects(first,{name:'AbortError'}),assert.rejects(second,{name:'AbortError'})]);
 await Promise.resolve();await Promise.resolve();edits.reset('B',empty());gate.resolve({});await rejected;
 assert.equal(calls,1);assert.equal(edits.scope,'B');assert.deepEqual(edits.value.likedIds,[]);
});
test('two different playlist edits keep each other when one fails',async()=>{
 const state=empty();state.playlists.push({id:'other',name:'Other',trackIds:[]});const edits=new LibraryEdits(state,()=>{});edits.reset('A',state);
 const bad=deferred(),good=deferred();const first=edits.mutate('playlist:list',value=>replacePlaylist(value,{id:'list',name:'Bad',trackIds:[]}),()=>bad.promise,value=>value);
 const failure=assert.rejects(first,/denied/);const second=edits.mutate('playlist:other',value=>replacePlaylist(value,{id:'other',name:'Saved',trackIds:[]}),()=>good.promise,(value,result)=>replacePlaylist(value,result));
 good.resolve({id:'other',name:'Saved',trackIds:[]});await second;bad.reject(new Error('denied'));await failure;
 assert.equal(edits.value.playlists.find(item=>item.id==='list').name,'Original');assert.equal(edits.value.playlists.find(item=>item.id==='other').name,'Saved');
});
test('a new playlist is an immediate draft, confirmed data excludes it until acknowledgement',async()=>{
 const edits=new LibraryEdits(empty(),()=>{});edits.reset('A',empty());const gate=deferred(),draft={id:'pending:fixture',name:'On the road',trackIds:[]};
 const operation=edits.mutate('create:'+draft.id,value=>replacePlaylist(value,draft),()=>gate.promise,(value,playlist)=>replacePlaylist(value,playlist));
 const failure=assert.rejects(operation,/limit/);
 assert(edits.value.playlists.some(value=>value.id===draft.id));assert(!edits.confirmed.playlists.some(value=>value.id===draft.id));
 gate.reject(new Error('limit'));await failure;
 assert(!edits.value.playlists.some(value=>value.id===draft.id));assert.equal(edits.value.playlists[0].name,'Original');
});
test('a delayed cover response cannot replace a newer name or membership',()=>{
 const state=empty();state.playlists[0]={id:'list',name:'New name',trackIds:['new-song'],artwork:''};
 const next=mergePlaylistCover(state,{id:'list',name:'Old name',trackIds:[],artwork:'/new-cover.jpg',coverArtworks:[]});
 assert.equal(next.playlists[0].name,'New name');assert.deepEqual(next.playlists[0].trackIds,['new-song']);assert.equal(next.playlists[0].artwork,'/new-cover.jpg');
 assert.equal(mergePlaylistCover({...state,playlists:[]},next.playlists[0]).playlists.length,0,'late cover acknowledgement cannot resurrect a deleted playlist');
});
