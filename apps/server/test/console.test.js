import test from 'node:test';
import assert from 'node:assert/strict';
import {PassThrough} from 'node:stream';
import {stripVTControlCharacters} from 'node:util';
import {consoleColorLevel,formatConsoleCard,waveAscii} from '../src/console-brand.js';
import {openServerConsole,runtimeSnapshot} from '../src/console-ui.js';
import {formatConsoleLog} from '../src/console-transport.js';

const config={production:false,host:'127.0.0.1',port:4000,appUrl:'https://user:password@wave.gluk.tech/app?token=private',storage:'sqlite',objectStorage:'local'};
test('console fits narrow terminals, removes unsafe controls and keeps actual counters',()=>{
  const snapshot={clients:4,rooms:2,uptime:4809,memoryMB:132,heapMB:67,cpuPercent:2.5,requests:452,failures:3,averageMs:17};
  for(const columns of [24,40,60,80,120]){
    const plain=formatConsoleCard(config,snapshot,{columns});
    assert.ok(plain.split('\n').every(line=>[...line].length<=columns),`Overflow at ${columns}`);
    assert.ok(!plain.includes('\x1b'));
    assert.ok(!plain.includes('password')&&!plain.includes('token=private'));
    const color=formatConsoleCard(config,snapshot,{columns,color:3});
    assert.equal(stripVTControlCharacters(color),plain);
  }
  const card=formatConsoleCard(config,snapshot,{columns:100});
  assert.ok(card.includes(waveAscii[2]));
  assert.ok(card.includes('4 connected clients  ·  2 rooms'));
  assert.ok(card.includes('1:20:09')&&card.includes('132 MB RSS  ·  67 MB heap')&&card.includes('2.5%'));
  assert.ok(!formatConsoleCard({...config,host:'\x1b[2J\nforged'},snapshot).includes('\x1b'));
});
test('console respects redirected output, NO_COLOR and terminal capabilities',()=>{
  assert.equal(consoleColorLevel({isTTY:false},{}),0);
  assert.equal(consoleColorLevel({isTTY:true},{NO_COLOR:'',FORCE_COLOR:'3'}),0);
  assert.equal(consoleColorLevel({isTTY:true},{TERM:'dumb'}),0);
  assert.equal(consoleColorLevel({isTTY:true},{TERM:'xterm'}),1);
  assert.equal(consoleColorLevel({isTTY:true},{TERM:'xterm-256color'}),2);
  assert.equal(consoleColorLevel({isTTY:true},{WT_SESSION:'active'}),3);
  assert.equal(consoleColorLevel({isTTY:true},{}),process.platform==='win32'?3:1);
  assert.equal(consoleColorLevel({isTTY:false},{FORCE_COLOR:'3'}),3);
});
test('interactive status has no polling timer and closes its input listener',async()=>{
  const output=new PassThrough(),input=new PassThrough();output.isTTY=true;input.isTTY=true;output.columns=80;
  let content='',stops=0;output.on('data',chunk=>content+=chunk.toString());
  const ctx={io:{sockets:{sockets:new Map([['one',{}],['two',{}]]),adapter:{rooms:new Map([['room:x',new Set()],['socket-id',new Set()]])}}},metrics:{requests:8,failures:2,duration:40},resourceSnapshot:()=>({cpuOneCorePercent:1.5})};
  const previous=process.env.CONSOLE_STYLE;process.env.CONSOLE_STYLE='studio';
  try{
    const close=openServerConsole(config,ctx,()=>stops++,{input,output});
    const initial=content.length;input.write('s\nq\n');await new Promise(resolve=>setImmediate(resolve));
    assert.ok(content.length>initial);assert.equal(stops,1);
    assert.equal(runtimeSnapshot(ctx).rooms,1);assert.equal(runtimeSnapshot(ctx).averageMs,5);
    close();input.write('q\n');await new Promise(resolve=>setImmediate(resolve));assert.equal(stops,1);
  }finally{if(previous===undefined)delete process.env.CONSOLE_STYLE;else process.env.CONSOLE_STYLE=previous;input.destroy();output.destroy();}
});
test('request logs use measured duration and cannot inject terminal controls',()=>{
  const record={method:'GET',path:'/api/tracks\x1b[2J\nforged',status:503,ms:1204,msg:'Unavailable\x1b[31m',code:'PROVIDER_TIMEOUT'};
  const plain=formatConsoleLog(record),color=formatConsoleLog(record,{color:3});
  assert.ok(plain.includes('503  1.20s'));
  assert.ok(plain.includes('[PROVIDER_TIMEOUT]'));
  assert.ok(!plain.includes('\x1b')&&!plain.includes('\n'));
  assert.equal(stripVTControlCharacters(color),plain);
});
