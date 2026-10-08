import test from 'node:test';
import assert from 'node:assert/strict';
import {updateMongoDocument} from '../src/store.js';

// A minimal atomic collection models conflicting remote readers without a real
// database credential. Assertions cover outcomes, including migrated records.
function collection(initial){
  const documents=new Map(initial.map(v=>[v._id,structuredClone(v)]));
  return {
    documents,
    async findOne({_id}){await new Promise(resolve=>setImmediate(resolve));return structuredClone(documents.get(_id)||null);},
    async insertOne(value){await new Promise(resolve=>setImmediate(resolve));if(documents.has(value._id)){const error=new Error('Duplicate');error.code=11000;throw error;}documents.set(value._id,structuredClone(value));},
    async replaceOne(query,next){await new Promise(resolve=>setImmediate(resolve));const current=documents.get(query._id);const matches=current&&(typeof query._v==='object'?!Object.hasOwn(current,'_v'):current._v===query._v);if(!matches)return {modifiedCount:0};documents.set(query._id,structuredClone(next));return {modifiedCount:1};}
  };
}

test('Mongo concurrent changes survive more than ten conflicting readers',async()=>{
  const records=collection([{_id:'counter',_v:0,id:'counter',value:0}]);
  await Promise.all(Array.from({length:32},()=>updateMongoDocument(records,'counter',v=>({...v,value:v.value+1}))));
  assert.equal(records.documents.get('counter').value,32);
  assert.equal(records.documents.get('counter')._v,32);
});

test('Mongo migrated records acquire a revision without losing concurrent changes',async()=>{
  const records=collection([{_id:'legacy',id:'legacy',value:0,name:'Existing record'}]);
  const values=await Promise.all(Array.from({length:12},()=>updateMongoDocument(records,'legacy',v=>({...v,value:v.value+1}))));
  assert.equal(records.documents.get('legacy').value,12);
  assert.equal(records.documents.get('legacy')._v,12);
  assert.equal(records.documents.get('legacy').name,'Existing record');
  assert.ok(values.every(value=>!Object.hasOwn(value,'_v')&&!Object.hasOwn(value,'_id')));
});

test('Mongo missing records are created once and no-op/error callbacks preserve data',async()=>{
  const records=collection([]);
  await Promise.all(Array.from({length:12},()=>updateMongoDocument(records,'new',v=>({id:'new',value:(v?.value||0)+1}))));
  assert.equal(records.documents.get('new').value,12);
  const before=structuredClone(records.documents.get('new'));
  await updateMongoDocument(records,'new',()=>undefined);
  await assert.rejects(updateMongoDocument(records,'new',()=>{throw new Error('Rejected mutation');}),/Rejected mutation/);
  assert.deepEqual(records.documents.get('new'),before);
});
