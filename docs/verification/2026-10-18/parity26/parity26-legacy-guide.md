# GlukWave26 — scoped legacy player compatibility

Root final-dist update, 18 October: rebuilt production assets pass the separate `parity26-compat-runtime-proof.json` (startup, dialog fallback, original WAV playback and full lyrics) and `parity26-legacy-layout-proof.json` (1440/768/375/320, no injected CSS, bounded mini/full controls, physical seek hit, six lyric rows, no cover/title overlap or horizontal overflow). The final proof records the production index hash. The earlier injected-source check below remains historical evidence, not a substitute for that final run. Physical TV and canonical silent-fixture seek-retention limitations remain.

This follow-up changes only `apps/web/src/glukwave26.css`. It retains the completed26 design, modern capsule layout and native UI. No builds, installs, deployment or owner-account requests were performed.

## Cause and changes

- The older-TV profile used physical left/right gutters while inheriting the modern capsule's `translateX(-50%)`. That shifted the whole mini player offscreen. The profile now explicitly resets the transform and uses bounded gutters.
- The26 `player-track-window` is a real flex child in the fallback; metadata can shrink, while transport keeps its required width. Phone fallback remains60px and desktop fallback68px. Modern desktop's centered740px capsule is unchanged.
- On narrow legacy viewports, modern dense detail-grid rules also overrode the fallback sleeve width. Explicit legacy flex/width/control-block rules now keep the complete sleeve above its title and transport. Lyrics remain in a scrollable lower pane.
- Legacy range controls use solid track/thumb colors, so old engines can show the seek and volume rails without depending on dynamic CSS variables or `color-mix`.

## Verification and boundaries

`work/qa/parity26-legacy-layout-browser.mjs` serves the previous actual production build through the existing isolated fixture on5276, removes newer browser APIs, forces the SystemJS legacy branch, then injects **only the current source fallback CSS**. This proves the source correction in a real browser; it is **not the final rebuilt-dist verification**, and it does not emulate or verify a physical Samsung TV.

The four widths are1440,768,375,320 at900px height. Assertions cover mini/metadata bounds, physical mini click opening the full player, full seek bounds and unblocked physical hit, six lyric rows after a physical Lyrics click, no cover/title overlap and no horizontal document overflow. Captures are `parity26-legacy-mini-WIDTH.png`, `parity26-legacy-full-WIDTH.png`, `parity26-legacy-lyrics-WIDTH.png` in `work/qa`. Machine-readable result: `parity26-legacy-layout-source-proof.json`.

An additional physical seek-retention probe is recorded separately in that JSON. The silent-media fixture resets some seeks near0; it is **not counted as passing canonical seek retention**. Timeline, playback and clock code were not changed by this CSS fix.

The remaining40 UI source hashes are compared with the existing41-file freeze. Only the checked CSS hash is replaced. The prior independent PASS applies to the prior freeze; root must run the final web build, actual-dist compatibility smoke and independent evaluation attempt3 before delivery.
