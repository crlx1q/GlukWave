import test from 'node:test';import assert from 'node:assert/strict';
import {mediaSessionState} from '../src/media-session-state.ts';
test('next-track loading retains title and intended playback instead of a transient idle session',()=>{
 const track={title:'Next song',artist:'Artist'};assert.equal(mediaSessionState(track,false,true,true,true).playbackState,'playing');assert.equal(mediaSessionState(track,false,true,true,false).title,'Next song — Artist · GlukWave');assert.equal(mediaSessionState(track,false,false,false,false).playbackState,'paused');assert.equal(mediaSessionState(track,false,false,false,false).title,'Next song — Artist · GlukWave');assert.deepEqual(mediaSessionState(null,false,false,false,false),{title:null,playbackState:'none'});
});
