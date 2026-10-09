import test from 'node:test';
import assert from 'node:assert/strict';
import {waitForPlayback} from '../src/playback-lifecycle.ts';
import {mediaDownloadPath,mediaArtworkPath} from '../src/media-download.ts';

test('cancelled media readiness stops polling and rejects the pending transfer',async()=>{
 const controller=new AbortController();let reads=0;
 const pending=waitForPlayback(()=>{reads++;return false;},controller.signal,'Unavailable',1000,5);
 controller.abort();await assert.rejects(pending,{name:'AbortError'});const after=reads;
 await new Promise(resolve=>setTimeout(resolve,25));assert.equal(reads,after);
});
test('cache artwork always uses owned API or known-track cover proxy',()=>{
 const origin='https://wave.gluk.tech';
 assert.equal(mediaArtworkPath('track','/api/media/cover.jpg',origin),'/api/media/cover.jpg');
 assert.equal(mediaArtworkPath('track','https://i1.sndcdn.com/cover.jpg',origin),'/api/external-covers/track');
 assert.equal(mediaArtworkPath('track','https://arbitrary.example/private',origin),'/api/external-covers/track');
 assert.equal(mediaArtworkPath('track','http://127.0.0.1/admin',origin),'/api/external-covers/track');
});
test('ready media detaches cancellation and cannot be rejected later',async()=>{
 const controller=new AbortController();let ready=false,reads=0;
 const pending=waitForPlayback(()=>{reads++;return ready;},controller.signal,'Unavailable',1000,5);
 ready=true;await pending;const after=reads;controller.abort();await new Promise(resolve=>setTimeout(resolve,20));assert.equal(reads,after);
});
test('source that never becomes ready has a bounded failure',async()=>{
 await assert.rejects(waitForPlayback(()=>false,new AbortController().signal,'Source unavailable',10,3),/Source unavailable/);
});
test('download permission selects only same-origin application API',()=>{
 const origin='https://wave.gluk.tech';
 assert.equal(mediaDownloadPath('track',undefined,origin),'/api/media/track/download');
 assert.equal(mediaDownloadPath('track','/api/external-audio/track/download',origin),'/api/external-audio/track/download');
 assert.equal(mediaDownloadPath('track',origin+'/api/external-audio/track/download?quality=best',origin),'/api/external-audio/track/download?quality=best');
 for(const url of ['https://media.example/audio','//media.example/api/audio','javascript:alert(1)','https://person:password@wave.gluk.tech/api/audio','/app/fake-audio'])assert.equal(mediaDownloadPath('track',url,origin),null);
});
