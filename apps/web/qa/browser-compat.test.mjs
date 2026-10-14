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
  assert.equal(nodes.h1.textContent, 'Открываем твою музыку');
  timer();
  assert.equal(attributes['data-failed'], 'true');
  assert.equal(nodes.h1.textContent, 'Не удалось открыть GlukWave');
  assert.equal(typeof nodes.button.onclick, 'function');
  mounted = true; observer();
  assert.equal(disconnected, true);
  assert.equal(removed, 2);
});
