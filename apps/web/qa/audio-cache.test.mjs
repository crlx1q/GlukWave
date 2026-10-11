import test from 'node:test';
import assert from 'node:assert/strict';
import {isAudioFile,canRetryCachedAudio} from '../src/audio-cache-validation.ts';

test('manifests and successful HTML/JSON error responses cannot become audio files',async()=>{
 for(const [body,type] of [['#EXTM3U\n#EXTINF:4,\ntrack.ts','audio/mpeg'],['\uFEFF  #EXTM3U','application/octet-stream'],['<!DOCTYPE html><html>Error</html>','audio/mp4'],[' {"error":{"code":"EXPIRED"}}','audio/mpeg'],['binary','text/plain'],['','audio/mpeg']]){
  assert.equal(await isAudioFile(new Blob([body],{type})),false);
 }
});
test('real file headers and unknown binary containers remain available to the decoder',async()=>{
 for(const [body,type] of [['RIFF\x00\x00\x00\x00WAVE','audio/wav'],['ID3\x04\x00\x00','audio/mpeg'],['\x00\x00\x00\x18ftypM4A ','audio/mp4'],['OggS\x00','audio/ogg'],[new Uint8Array([255,241,80,128,1,127,252]),'application/octet-stream']]){
  assert.equal(await isAudioFile(new Blob([body],{type})),true);
 }
});
test('only cached decoder failures retry online, never policy/network/cancellation errors or fresh sources',()=>{
 const bad=Object.assign(Error('Unsupported'),{name:'NotSupportedError'});
 assert(canRetryCachedAudio(bad,true,true));
 assert(canRetryCachedAudio({code:'AUDIO_FORMAT_UNAVAILABLE'},true,true));
 for(const name of ['NotAllowedError','AbortError','NetworkError'])assert(!canRetryCachedAudio({name},true,true));
 assert(!canRetryCachedAudio(bad,false,true));assert(!canRetryCachedAudio(bad,true,false));
});
