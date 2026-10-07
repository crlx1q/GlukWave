import test from 'node:test';
import assert from 'node:assert/strict';
import {Readable} from 'node:stream';
import {soundcloudEnvelope,readSoundcloudEnvelope,decodeAudioEnvelope} from '../src/waveforms.js';
import {soundcloudWaveformUrl} from '../src/soundcloud-public.js';

test('real PCM waveform keeps silence quiet and measures changing audio amplitude',async()=>{
  const rate=8000,duration=2,size=rate*duration*2,bytes=Buffer.alloc(44+size);
  bytes.write('RIFF');bytes.writeUInt32LE(36+size,4);bytes.write('WAVEfmt ',8);bytes.writeUInt32LE(16,16);bytes.writeUInt16LE(1,20);bytes.writeUInt16LE(1,22);bytes.writeUInt32LE(rate,24);bytes.writeUInt32LE(rate*2,28);bytes.writeUInt16LE(2,32);bytes.writeUInt16LE(16,34);bytes.write('data',36);bytes.writeUInt32LE(size,40);
  for(let n=rate;n<rate*duration;n++)bytes.writeInt16LE(Math.round(Math.sin(n*2*Math.PI*220/rate)*16000),44+n*2);
  const samples=await decodeAudioEnvelope(Readable.from([bytes]),duration);
  assert.ok(samples?.length>=32);assert.ok(samples.slice(0,16).every(value=>value<.001));assert.ok(samples.slice(-16).every(value=>value>.3&&value<.4));
  assert.equal(await decodeAudioEnvelope(Readable.from([Buffer.from('not audio')]),2),null);
});

test('SoundCloud envelopes are bounded, normalized and never fetch arbitrary hosts or follow redirects',async()=>{
  assert.deepEqual(soundcloudEnvelope({height:100,samples:[0,50,100,150]}),[0,.5,1,1]);assert.equal(soundcloudEnvelope({height:0,samples:[1]}),null);assert.equal(soundcloudEnvelope({height:10,samples:[-1]}),null);
  assert.equal(soundcloudEnvelope({height:100,samples:Array(10000).fill(50)}).length,4096);
  assert.equal(soundcloudWaveformUrl('https://wave.sndcdn.com/test.png'),'https://wave.sndcdn.com/test.json');assert.equal(soundcloudWaveformUrl('https://wave.sndcdn.com.evil.test/test.json'),null);assert.equal(soundcloudWaveformUrl('https://name:pass@wave.sndcdn.com/test.json'),null);
  let fetched=false;await assert.rejects(readSoundcloudEnvelope('http://127.0.0.1/private',()=>{fetched=true;}));assert.equal(fetched,false);
  assert.equal(await readSoundcloudEnvelope('https://wave.sndcdn.com/test.json',async(_,options)=>{assert.equal(options.redirect,'manual');return new Response('',{status:302,headers:{location:'http://127.0.0.1/private'}});}),null);
  assert.deepEqual(await readSoundcloudEnvelope('https://wave.sndcdn.com/test.json',async()=>Response.json({height:100,samples:[0,25,50]})),[0,.25,.5]);
});
