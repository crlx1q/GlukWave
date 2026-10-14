import test from 'node:test';
import assert from 'node:assert/strict';
import {lyricCue,lyricDefocus} from '../src/lyric-timing.ts';
const lines=[{time:10,text:'First line'},{time:20,text:'Next line'}];
test('Timed intro comes from playback time and follows seeks in either direction',()=>{
  assert.equal(lyricCue(lines,true,0).countdown,null);
  for(const [position,number] of [[7,3],[7.9,3],[8,2],[9,1],[9.999,1]])assert.equal(lyricCue(lines,true,position).countdown,number);
  assert.equal(lyricCue(lines,true,10).active,0);assert.equal(lyricCue(lines,true,10).intro,false);
  assert.equal(lyricCue(lines,true,30).active,1);assert.equal(lyricCue(lines,true,8).countdown,2);
  assert.equal(lyricCue(lines,false,8).countdown,null);
  assert.equal(lyricCue([{time:0,text:'Immediate'}],true,0).countdown,null);
  assert.equal(lyricCue([],true,1).countdown,null);
  assert.equal(lyricCue([{time:0,text:''},{time:1,text:'♪'},...lines],true,8).countdown,2);
});
test('Only distant lyrics are softly defocused and blur has a bounded maximum',()=>{
  assert.equal(lyricDefocus(0,0),0);assert.equal(lyricDefocus(1,0),0);assert.equal(lyricDefocus(6,-1),0);
  assert.equal(lyricDefocus(3,0),.7);assert.equal(lyricDefocus(99,0),1.6);
});
