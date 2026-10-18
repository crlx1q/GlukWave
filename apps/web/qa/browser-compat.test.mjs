import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { parse } from 'acorn';
import { compatibleUuid, bridgeMediaQuery } from '../src/browser-compat-model.ts';

test('older TV crypto creates UUIDv4 identifiers with secure random bytes', () => {
  let calls = 0;
  const crypto = { getRandomValues(bytes) { calls++; bytes.fill(255); return bytes; } };
  assert.equal(compatibleUuid(crypto), 'ffffffff-ffff-4fff-bfff-ffffffffffff');
  assert.equal(calls, 1);
});

test('old media query change listeners subscribe and unsubscribe symmetrically', () => {
  const listeners = new Set();
  const query = { addListener: listener => listeners.add(listener), removeListener: listener => listeners.delete(listener) };
  const callback = () => {};
  assert.equal(bridgeMediaQuery(query), query);
  query.addEventListener('change', callback);
  assert.equal(listeners.size, 1);
  query.removeEventListener('change', callback);
  assert.equal(listeners.size, 0);
  const modern = { addEventListener() {}, removeEventListener() {} };
  const original = modern.addEventListener;
  bridgeMediaQuery(modern);
  assert.equal(modern.addEventListener, original);
});

const script = readFileSync(new URL('../public/startup.js', import.meta.url), 'utf8');
test('startup recovery parses as ES5 and respects cached account language', () => {
  parse(script, { ecmaVersion: 5 });
  const nodes = { h1: {}, p: {}, button: {} };
  const attributes = {};
  let mounted = false, timer, removed = 0, disconnected = false;
  const shell = { querySelector: key => nodes[key], setAttribute: (key, value) => { attributes[key] = value; } };
  const document = { documentElement: {}, getElementById: id => id === 'gw-boot' ? (mounted ? null : shell) : {} };
  const values = { 'gw-user': '{"id":"test"}', 'gw-settings:test': '{"language":"ru"}', 'gw-language-choice': 'en' };
  let observer;
  const window = { addEventListener() {}, removeEventListener() { removed++; }, MutationObserver: function (callback) { observer = callback; this.observe = () => {}; this.disconnect = () => { disconnected = true; }; } };
  runInNewContext(script, {
    document, window, navigator: { language: 'kk' }, localStorage: { getItem: key => values[key] || null },
    location: { reload() {} }, setTimeout: callback => { timer = callback; return 1; }, clearTimeout() {}, MutationObserver: window.MutationObserver,
  });
  assert.equal(document.documentElement.lang, 'ru');
  assert.equal(nodes.h1.textContent, '');
  assert.equal(nodes.p.textContent, '');
  timer();
  assert.equal(attributes['data-failed'], 'true');
  assert.equal(nodes.h1.textContent, 'Не удалось открыть GlukWave');
  assert.equal(typeof nodes.button.onclick, 'function');
  mounted = true; observer();
  assert.equal(disconnected, true);
  assert.equal(removed, 1);
});

function bootFixture(userAgent = 'Desktop Chrome', observed = true) {
  const nodes = {h1:{}, p:{}, button:{}}, attributes = {}, timers = new Map(), listeners = new Map();
  let mounted = false, nextTimer = 0, changed;
  const shell = {querySelector:key=>nodes[key], setAttribute:(key,value)=>attributes[key]=value};
  const document = {documentElement:{}, getElementById:id=>id==='gw-boot'?(mounted?null:shell):{}};
  const MutationObserver = function (callback) {changed=callback;this.observe=()=>{};this.disconnect=()=>{};};
  const window = {addEventListener:(name,fn)=>listeners.set(name,fn), removeEventListener:name=>listeners.delete(name), ...(observed?{MutationObserver}:{})};
  runInNewContext(script, {document, window, navigator:{language:'ru',userAgent}, localStorage:{getItem:()=>null}, location:{reload(){}},
    MutationObserver, setTimeout:(fn,delay)=>{timers.set(++nextTimer,{fn,delay});return nextTimer;},clearTimeout:id=>timers.delete(id)});
  return {nodes,attributes,timers,listeners, mount(){mounted=true;changed?.();}, error(target){listeners.get('error')?.({target});}, run(delay){for(const [id,value] of [...timers])if(value.delay===delay){timers.delete(id);value.fn();}}};
}

test('unrelated resource failures and request rejections never flash a boot error',()=>{
  const boot=bootFixture();
  for(const target of [{tagName:'IMG',src:'/cover.png'},{tagName:'LINK',href:'/fonts.css'},{tagName:'SCRIPT',src:'/optional-analytics.js'},null])boot.error(target);
  assert.equal(boot.listeners.has('unhandledrejection'),false);
  assert.equal(boot.timers.size,1);
  assert.equal(boot.attributes['data-failed'],undefined);
  boot.mount();
  assert.equal(boot.timers.size,0);
  assert.equal(boot.listeners.size,0);
});

test('a recovered main script failure is canceled when React commits',()=>{
  const boot=bootFixture();
  boot.error({tagName:'SCRIPT',src:'https://glukwave.example/assets/main-123.js'});
  boot.error({tagName:'SCRIPT',src:'https://glukwave.example/assets/polyfills-legacy-123.js'});
  assert.equal(boot.timers.size,2);
  assert.equal(boot.attributes['data-failed'],undefined);
  boot.mount();boot.run(1500);boot.run(15000);
  assert.equal(boot.attributes['data-failed'],undefined);
});

test('a genuine unavailable bundle offers retry, and TV advice appears only on a TV',()=>{
  for(const ua of ['Desktop Chrome','Samsung SMART-TV Tizen']){
    const boot=bootFixture(ua);
    boot.error({tagName:'SCRIPT',src:'https://glukwave.example/assets/main-legacy-123.js'});
    boot.run(1500);
    assert.equal(boot.attributes['data-failed'],'true');
    assert.equal(boot.nodes.h1.textContent,'Не удалось открыть GlukWave');
    assert.equal(boot.nodes.p.textContent.includes('браузеру ТВ'),ua.includes('Tizen'));
  }
});

test('the watchdog still recovers a stalled runtime without MutationObserver',()=>{
  const stalled=bootFixture('Desktop Chrome',false);stalled.run(15000);
  assert.equal(stalled.attributes['data-failed'],'true');
  const mounted=bootFixture('Desktop Chrome',false);mounted.mount();mounted.run(15000);
  assert.equal(mounted.attributes['data-failed'],undefined);
});
