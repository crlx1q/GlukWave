import test from 'node:test';import assert from 'node:assert/strict';
import{bloomField,particleResponse,waveResponse,bloomFieldGLSL}from '../src/wave-math.ts';
test('Bloom responds across normal measured music without an invented silence level',()=>{
 let rest=0,react=0;const measured=waveResponse(.25);
 for(let u=0;u<=1;u+=.01)for(let v=0;v<=1;v+=.01){rest+=bloomField(u,v,.8,0);react+=bloomField(u,v,.8,measured);}
 assert(react/rest>1.8&&react/rest<3);assert.equal(waveResponse(0),0);
 assert.equal(bloomField(.5,.5,.8,NaN),bloomField(.5,.5,.8,0));
 assert(bloomFieldGLSL.includes('(1.0+e*1.5)'));assert(bloomFieldGLSL.includes('(.145+e*.09)'));
});
test('Particle pulse lifts spread, amplitude and point size, stays bounded and silence unchanged',()=>{
 assert.deepEqual(particleResponse(0),{amplitude:.15,detail:.055,spread:1,radius:0,brightness:0});
 assert.deepEqual(particleResponse(NaN),particleResponse(0));
 const normal=particleResponse(waveResponse(.25)),maximum=particleResponse(1);
 assert(normal.amplitude>.19&&normal.spread>1.4&&normal.radius>.35);
 assert.deepEqual(particleResponse(2),maximum);assert.deepEqual(particleResponse(-2),particleResponse(0));
});
