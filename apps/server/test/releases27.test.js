import test from 'node:test';
import assert from 'node:assert/strict';
import {compareReleaseVersions} from '../src/releases.js';
test('release selection orders numeric builds and semantic versions rather than manifest location or text order',()=>{
 for(const [newer,older] of [['1.0.0+27','1.0.0+26'],['1.2.1','1.2.0+999'],['2.0.0','1.99.99'],['1.0.0','1.0.0-rc.1'],['1.0.0-rc.10','1.0.0-rc.9']]){
  assert(compareReleaseVersions(newer,older)>0);assert(compareReleaseVersions(older,newer)<0);
 }
 assert.equal(compareReleaseVersions('1.0.0','1.0.0+0'),0);
});
