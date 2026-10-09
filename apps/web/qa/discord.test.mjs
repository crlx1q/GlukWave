import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { discordPosition, discordOAuthUrl, discordInvitation, restoredDiscordInvitation, DiscordStatusController } from '../src/discord-model.ts';
const tick = () => new Promise(resolve => setImmediate(resolve));
test('progress extrapolates only playing activity and clamps end or malformed values', () => {
  assert.equal(discordPosition({ position: 42, duration: 180, playing: true }, 5), 47);
  assert.equal(discordPosition({ position: 42, duration: 180, playing: false }, 5), 42);
  assert.equal(discordPosition({ position: 175, duration: 180, playing: true }, 20), 180);
  assert.equal(discordPosition({ position: NaN, duration: Infinity, playing: false }, 0), 0);
});
test('authorization redirects only accept actual HTTPS Discord authorization endpoints', () => {
  assert.equal(discordOAuthUrl('https://discord.com/oauth2/authorize?client_id=1'), 'https://discord.com/oauth2/authorize?client_id=1');
  for (const value of ['javascript:alert(1)', 'https://discord.com.attacker.test/oauth2/authorize', 'http://discord.com/oauth2/authorize', 'https://user@discord.com/oauth2/authorize', 'https://discord.com/channels/@me', '/oauth2/authorize']) assert.throws(() => discordOAuthUrl(value));
});
test('invite parsing keeps explicit listen or jam identity and refuses path injection', () => {
  assert.deepEqual(discordInvitation('?listen=user_42'), { kind: 'listen', id: 'user_42' });
  assert.deepEqual(discordInvitation('?jam=room-42'), { kind: 'jam', id: 'room-42' });
  assert.equal(discordInvitation('?listen=../../admin'), null);
  assert.equal(discordInvitation('?listen=' + 'a'.repeat(129)), null);
  assert.equal(discordInvitation('?track=42'), null);
});
test('explicit invite intent survives an external sign-in return within a bounded lifetime', () => {
  const saved = JSON.stringify({ kind: 'listen', id: 'friend-42', expiresAt: 11000 });
  assert.deepEqual(restoredDiscordInvitation('', saved, 10000), { kind: 'listen', id: 'friend-42' });
  assert.deepEqual(restoredDiscordInvitation('?jam=room-42', saved, 10000), { kind: 'jam', id: 'room-42' });
  assert.equal(restoredDiscordInvitation('', saved, 12000), null);
  assert.equal(restoredDiscordInvitation('', '{bad', 10000), null);
  assert.equal(restoredDiscordInvitation('', JSON.stringify({ kind: 'listen', id: '../admin', expiresAt: 11000 }), 10000), null);
  assert.equal(restoredDiscordInvitation('', JSON.stringify({ kind: 'listen', id: 'friend-42', expiresAt: 2000000 }), 10000), null);
});
test('status refresh coalesces notifications without concurrent duplicate API calls', async () => {
  const pending = [], seen = [], errors = [];
  const controller = new DiscordStatusController(signal => new Promise(resolve => pending.push({ signal, resolve })), value => seen.push(value), error => errors.push(error));
  controller.refresh(); controller.refresh(); controller.refresh(); assert.equal(pending.length, 1);
  pending[0].resolve({ status: 'idle' }); await tick(); assert.equal(pending.length, 2);
  pending[1].resolve({ status: 'active' }); await tick(); assert.deepEqual(seen.map(value => value.status), ['idle', 'active']); assert.deepEqual(errors, []); controller.stop();
});
test('account panel cleanup aborts and discards old identity results including queued refresh', async () => {
  let resolve, signal, calls = 0, seen = 0;
  const controller = new DiscordStatusController(next => { signal = next; calls++; return new Promise(done => resolve = done); }, () => seen++, () => seen++);
  controller.refresh(); controller.refresh(); controller.stop(); assert(signal.aborted);
  resolve({ identity: { username: 'previous-account' } }); await tick(); controller.refresh(); assert.equal(seen, 0); assert.equal(calls, 1);
});
test('all Discord labels are present in six catalogs with matching interpolation', async () => {
  const languages = ['en', 'ru', 'kk', 'uk', 'de', 'es'];
  const catalogs = await Promise.all(languages.map(async language => JSON.parse(await fs.readFile(new URL(`../src/locales/${language}.json`, import.meta.url), 'utf8'))));
  const keys = Object.keys(catalogs[0]).filter(key => key.startsWith('discord.')); assert.equal(keys.length, 48);
  for (const key of keys) for (const [index, catalog] of catalogs.entries()) { assert.equal(typeof catalog[key], 'string', `${languages[index]} ${key}`); assert(catalog[key].trim()); assert.deepEqual([...catalog[key].matchAll(/\{\w+\}/g)].map(value => value[0]), [...catalogs[0][key].matchAll(/\{\w+\}/g)].map(value => value[0])); }
});
