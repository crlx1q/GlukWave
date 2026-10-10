import test from 'node:test';
import assert from 'node:assert/strict';
import {createPlaybackResolver} from '../src/playback.js';

test('Playback never falls back to catalog widgets; tries independent audio after a failed adapter and bounds diagnostics',async()=>{
  const calls=[],reports=[];
  const track={id:'song',source:'youtube',playback:{kind:'youtube',embedUrl:'https://www.youtube.com/embed/never-mounted'}};
  const ctx={publicTrack:t=>t,extractorExpected:async()=>true,
    extractorPlayback:async()=>{calls.push('licensed');throw Object.assign(new Error('private upstream'),{code:'EXTRACTOR_UPSTREAM',status:502});},
    soundcloudPlayback:async()=>{calls.push('soundcloud');return {kind:'audio',url:'/api/soundcloud-audio/song',offline:false};},
    reportError:async value=>reports.push(value)};
  const resolve=createPlaybackResolver(ctx);
  assert.equal((await resolve(track,{id:'user'},'session')).kind,'audio');
  assert.deepEqual(calls,['licensed','soundcloud']);
  assert(!JSON.stringify(reports).includes('private upstream'));
  ctx.soundcloudPlayback=async()=>null;ctx.extractorExpected=async()=>false;ctx.extractorPlayback=async()=>null;
  await assert.rejects(resolve(track,{id:'user'},'session'),{status:422,code:'AUDIO_UNAVAILABLE'});
  await assert.rejects(resolve(track,null,null),{status:401,code:'AUTH_REQUIRED'});
  const local={...track,source:'local',playback:{kind:'audio',url:'/api/media/song'}};
  assert.equal((await resolve(local,{id:'user'},'session')).url,'/api/media/song');
  ctx.extractorPlayback=async()=>{throw Object.assign(new Error('secret'),{code:'EXTRACTOR_BUSY',status:503});};
  for(let index=0;index<25;index++)await assert.rejects(resolve(track,{id:'user'},'session'),{code:'EXTRACTOR_BUSY'});
  const stats=ctx.playbackDiagnostics();assert.equal(stats.mode,'native-audio');assert.equal(stats.recent.length,20);assert.equal(stats.counts.failed,25);assert.equal(stats.counts.unavailable,1);
});
