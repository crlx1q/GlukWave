import test from 'node:test';
import assert from 'node:assert/strict';
import {parseLyrics} from '../src/util.js';

test('lyrics distinguish hour timestamps from standard LRC minutes and fractions',()=>{
  const parsed=parseLyrics('[1:20:00]Long track\n[80:00.00]Same position\n[02:03:04.125]Later\n[00:05.89]First');
  assert.equal(parsed.synchronized,true);
  assert.deepEqual(parsed.lines,[{time:5.89,text:'First'},{time:4800,text:'Long track'},{time:4800,text:'Same position'},{time:7384.125,text:'Later'}]);
});

test('repeated LRC times, metadata and untimed lines retain their meaning',()=>{
  assert.deepEqual(parseLyrics('[ar:Artist]\n[00:01.2][00:04.10]Repeated\nUntimed').lines,[{time:1.2,text:'Repeated'},{time:4.1,text:'Repeated'},{time:null,text:'Untimed'}]);
});

test('invalid clock fields cannot introduce impossible synchronized positions',()=>{
  const parsed=parseLyrics('[1:60:00]Invalid minute\n[00:60]Invalid second\n[1:02:60]Invalid hour second');
  assert.equal(parsed.synchronized,false);
  assert.deepEqual(parsed.lines.map(line=>line.time),[null,null,null]);
});
