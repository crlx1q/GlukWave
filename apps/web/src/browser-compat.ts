// Evaluate before the app graph: some dependencies create their device identity
// at module scope. All fallbacks are bundled locally; no third-party runtime.
import 'whatwg-fetch';
import 'abortcontroller-polyfill/dist/polyfill-patch-fetch';
import 'intersection-observer';
import 'intl-pluralrules';
import ResizeObserverPolyfill from 'resize-observer-polyfill';
import cssVars from 'css-vars-ponyfill';
import { bridgeMediaQuery, compatibleUuid } from './browser-compat-model';

if (!window.ResizeObserver) window.ResizeObserver = ResizeObserverPolyfill;
if (!window.crypto.randomUUID) {
  window.crypto.randomUUID = (() => compatibleUuid(window.crypto)) as Crypto['randomUUID'];
}
const originalMatchMedia = window.matchMedia.bind(window);
window.matchMedia = query => bridgeMediaQuery(originalMatchMedia(query));
const legacyAudio = window as Window & { webkitAudioContext?: typeof AudioContext };
if (!window.AudioContext && legacyAudio.webkitAudioContext) {
  window.AudioContext = legacyAudio.webkitAudioContext;
}
const supports = (property: string, value: string) => !!window.CSS?.supports?.(property, value);
const television = /Tizen|SMART-TV|SmartTV/i.test(navigator.userAgent);
if ((television && (!supports('display', 'grid') || !supports('height', '100dvh') || !supports('color', 'color-mix(in srgb, black, white)'))) || new URLSearchParams(location.search).get('compat') === '1') {
  document.documentElement.dataset.browserProfile = 'tv-legacy';
}
if (!supports('color', 'var(--wave-test)')) {
  const root = document.documentElement;
  const refresh = () => {
    const variables: Record<string, string> = {};
    for (let index = 0; index < root.style.length; index++) {
      const key = root.style[index];
      if (key.startsWith('--')) variables[key] = root.style.getPropertyValue(key);
    }
    cssVars({ variables, onlyLegacy: true, watch: true, silent: true });
  };
  let frame = 0;
  new MutationObserver(() => {
    cancelAnimationFrame(frame);
    frame = requestAnimationFrame(refresh);
  }).observe(root, { attributes: true, attributeFilter: ['style'] });
  refresh();
}
