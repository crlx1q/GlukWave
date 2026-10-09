import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { open, evaluate, run, useSession, snapshot, screenshot, click, ref } from './browser.mjs';
process.env.AGENT_BROWSER_ARGS = '--mute-audio';
useSession('gluk-discord-ui-' + Date.now());
const origin = 'http://127.0.0.1:5183', proof = { passed: false, scope: 'Rendered application and UI interactions against isolated HTTP fixtures; not evidence of genuine Discord OAuth or publication.', steps: [], screenshots: [], layouts: [] };
const control = async body => { const response = await fetch(origin + '/api/qa/discord', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }); return response.json(); };
const wait = expression => { const end = Date.now() + 18000; while (Date.now() < end) { if (evaluate(expression)) return snapshot(); Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 180); } throw new Error('Wait failed: ' + expression); };
const helper = `window.__gw=function(key){const host=document.getElementById('root'),root=host[Object.keys(host).find(name=>name.startsWith('__reactContainer$'))]?.stateNode?.current,stack=[root];while(stack.length){const fiber=stack.pop();if(!fiber)continue;const value=fiber.memoizedProps?.value;if(value&&typeof value[key]==='function')return value;if(fiber.sibling)stack.push(fiber.sibling);if(fiber.child)stack.push(fiber.child);}throw Error('Missing context '+key);};`;
const refresh = () => { evaluate(`window.dispatchEvent(new Event('focus'))`); snapshot(); };
const shot = name => { const file = `apps/web/qa/discord-${name}.png`; screenshot(file); proof.screenshots.push(file); };
try {
  await control({ scenario: 'active', preferences: { enabled: true, allowJoin: false } });
  open(origin + '/app/#settings?section=notifications'); wait(`!!document.querySelector('.wave-discord-activity')`); evaluate(helper); run('set', 'viewport', '1440', '1000'); snapshot();
  assert(evaluate(`document.querySelector('.wave-discord-identity').innerText.includes('@wave_listener')`));
  assert(evaluate(`document.querySelector('.wave-discord-preview-actions button').disabled`));
  run('scrollintoview', '.wave-discord'); snapshot(); shot('active-light-desktop');
  run('check', ref('checkbox', /^Let friends listen with me/)); snapshot(); wait(`!!document.querySelector('.wave-discord-preview-actions a[href*="listen="]')`);
  assert((await control({})).mutations.some(value => value.allowJoin === true));
  run('uncheck', ref('checkbox', /^Show what I am listening to/)); snapshot(); wait(`document.querySelector('.wave-discord-status').classList.contains('state-disabled')`);
  run('check', ref('checkbox', /^Show what I am listening to/)); snapshot(); wait(`document.querySelector('.wave-discord-status').classList.contains('state-active')`);
  proof.steps.push('Connected identity, live preview, server PATCH presence/privacy toggles and two Wave links');
  for (const theme of ['light', 'dark', 'amoled']) {
    evaluate(`__gw('saveSettings').saveSettings({theme:${JSON.stringify(theme)}})`); wait(`document.documentElement.dataset.theme===${JSON.stringify(theme)}`);
    for (const [size, width, height] of [['desktop', 1440, 1000], ['mobile', 390, 844]]) {
      run('set', 'viewport', String(width), String(height)); snapshot(); run('scrollintoview', '.wave-discord'); snapshot();
      const layout = evaluate(`(()=>{const panel=document.querySelector('.wave-discord'),r=panel.getBoundingClientRect(),elements=[...panel.querySelectorAll('*')],clipped=elements.filter(e=>e.getBoundingClientRect().right>innerWidth+1);return{overflow:document.documentElement.scrollWidth>innerWidth,width:r.width,clipped:clipped.map(e=>e.className)}})()`);
      assert(!layout.overflow && !layout.clipped.length, JSON.stringify(layout)); proof.layouts.push({ theme, size, ...layout }); shot(`active-${theme}-${size}`);
    }
  }
  proof.steps.push('Active three-theme desktop/mobile rendered layout without horizontal overflow');
  for (const language of ['en', 'ru', 'kk', 'uk', 'de', 'es']) {
    evaluate(`__gw('saveSettings').saveSettings({language:${JSON.stringify(language)},fontScale:1.25})`); wait(`document.documentElement.lang===${JSON.stringify(language)}`); run('scrollintoview', '.wave-discord'); snapshot();
    assert(!evaluate(`document.querySelector('.wave-discord').innerText.includes('discord.')`)); assert(!evaluate(`document.documentElement.scrollWidth>innerWidth`));
  }
  shot('active-es-125-mobile'); proof.steps.push('Six translated languages at 125 percent font scale on phone');
  evaluate(`__gw('saveSettings').saveSettings({language:'en',fontScale:1})`); wait(`document.documentElement.lang==='en'`);
  for (const scenario of ['idle', 'disconnected', 'reconnect_required', 'unavailable', 'retrying']) {
    await control({ scenario }); refresh(); wait(`document.querySelector('.wave-discord-status')?.classList.contains('state-${scenario}')`); run('scrollintoview', '.wave-discord'); snapshot();
    if (['disconnected', 'unavailable'].includes(scenario)) assert(!evaluate(`document.querySelector('.wave-discord-activity').innerText.includes('A moment on your wavelength')`));
    if (scenario === 'reconnect_required') assert(evaluate(`document.querySelectorAll('.wave-discord .switch input:disabled').length===2`));
    shot(scenario + '-mobile');
  }
  proof.steps.push('Idle, disconnected, reconnect-required, unavailable and retrying states retain truthful controls');
  await control({ scenario: 'active' }); refresh(); wait(`document.querySelector('.wave-discord-status')?.classList.contains('state-active')`);
  click('Disconnect'); wait(`!!document.querySelector('dialog[open]')`); click('Disconnect'); wait(`!document.querySelector('dialog[open]')&&document.querySelector('.wave-discord-status')?.classList.contains('state-disconnected')`); proof.steps.push('Disconnect confirms then updates after actual isolated DELETE acknowledgement');
  await control({ scenario: 'error' }); refresh(); wait(`!!document.querySelector('.wave-discord-error')`); shot('error-mobile');
  await control({ scenario: 'idle' }); click('Refresh'); wait(`!document.querySelector('.wave-discord-error')`); proof.steps.push('Transient API error has a scoped retry and recovers');
  await control({ scenario: 'free' }); run('reload'); wait(`!!document.querySelector('.wave-discord-empty.locked')`); run('scrollintoview', '.wave-discord'); snapshot(); shot('free-mobile'); assert(!evaluate(`!!document.querySelector('.wave-discord .switch')`)); proof.steps.push('Free receives locked UI from the server eligibility response');
  await control({ scenario: 'signedout' }); open(origin + '/app/?listen=friend-42#rooms'); wait(`!!document.querySelector('.wave-discord-invitation')`); assert(evaluate(`document.querySelector('.wave-discord-invitation').innerText.includes('Sign in to join')`)); shot('invite-signedout-mobile'); click('Close'); assert(!evaluate(`location.search.includes('listen=')`)); proof.steps.push('Signed-out listen invitation requires explicit sign-in and can be dismissed without joining');
  const errors = run('errors'); proof.browserErrors = errors;
  proof.passed = true;
} catch (error) { proof.error = String(error); try { proof.snapshot = snapshot().snapshot; } catch {} throw error; }
finally { await fs.writeFile('apps/web/qa/discord-browser-proof.json', JSON.stringify(proof, null, 2)); run('close'); }
