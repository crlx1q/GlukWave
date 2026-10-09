# Discord web integration handoff

Web product files are frozen after the final successful build. Root owns backend and native integration.

## Implemented

- Replaced the legacy local bridge/pairing form with a server-backed Discord settings panel in connections and notification settings. Removed the global localhost Rich Presence sender entirely.
- Paid eligibility is read from the server. Free shows a membership lock; connected Free accounts can still disconnect. No client-side API keys, pairing secrets or developer configuration instructions.
- Identity, avatar with failure fallback, reconnect/change/disconnect confirmation, publication status, canonical output device, presence and private-jam consent controls.
- Responsive activity preview using only the server's current track data, bounded progress, album artwork fallback, Wave mark and the two genuine track/join links. Label explicitly says preview; Discord controls actual rendering.
- All six locales, three themes, global font scale and reduced motion. Complete loading, empty, permission lock, expired authorization, reconnecting, temporary failure and retry states.
- One scoped request lane coalesces socket/focus/resume notifications, aborts on account lifetime changes and discards stale identity results. No playback publication requests are sent from the browser.
- Incoming `/app/?listen=<userId>` and `/app/?jam=<jamId>` links preserve a signed-out invitation (including an external Google return through a bounded 30-minute session intent), require explicit confirmation, then use the existing server join API and player room flow. They do not add friends or bypass limits. Existing `/app/?track=<trackId>` routing remains intact.

## Validation

- `npm run build --workspace @glukwave/web`: final TypeScript and production bundle passed. Only the pre-existing large motion-icons bundle advisory remains.
- `node --experimental-strip-types --test apps/web/qa/discord.test.mjs apps/web/qa/parity-web-model.test.mjs apps/web/qa/connect-controller.test.mjs apps/web/qa/playback-lifecycle.test.mjs`: 24/24 passed.
- `apps/web/qa/discord-browser-proof.json`: 8 rendered browser stages passed, no uncaught page errors. Three themes at desktop/mobile widths, all six locales at 125% scale, real isolated HTTP preference mutations, disconnect confirmation, scoped error recovery, Free lock and signed-out invitation.
- `git diff --check -- apps/web`: passed, apart from informational repository LF/CRLF conversion messages.
- PNGs: `discord-active-dark-desktop.png`, `discord-active-light-mobile.png`, `discord-active-es-125-mobile.png`, `discord-free-mobile.png`, `discord-invite-signedout-mobile.png`, plus the remaining states in this QA directory. `discord-mobile-preview.png` shows the complete activity preview. Full-page mobile captures display the fixed player/navigation at the browser viewport position; evaluate actual scrolling separately.

## QA boundary

Browser checks use the isolated `discord-preview-server.mjs` on localhost 5183 with explicit HTTP fixtures. They establish rendering and client interaction behavior, **not** genuine Discord OAuth consent, headless presence or server permissions. Backend integration tests and real provider validation are root-owned. No production owner account, environment credentials or playback was changed. Browser sessions are uniquely named and muted. An additional screenshot session had a Windows CLI-close timeout; retry confirmed `closed: true`.

Independent design evaluation is delegated by root; this file is an implementation handoff, not an evaluation verdict. Its first pass caught double text scaling at 375px/125% German: this was corrected by applying the existing global zoom exactly once and compacting the narrow song layout. The evaluator accepted the focused recheck and then reported web PASS after 1440/768/375 viewports, six locales at 125%, status states and the disconnect modal. Evaluation reports remain evaluator/root-owned. Final successful bundle: main-Ds_lT4no.js and main-0enKJQz8.css. The isolated 5183 server was stopped after the evaluator acknowledged completion.
