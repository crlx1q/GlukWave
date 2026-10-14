# Current final design contracts

All collapsed/miniplayer surfaces have no lyrics. Web/native desktopbottom96px, nativeindependentcompact116px, phone68px. ExpandedPlayerPage retains the excerpt and full timedlyrics. Current remote metadata and compact captures: native-parity24-desktop-bottom-clean.png, native-parity24-desktop-bottom-remote-125.png, native-parity24-compact-window-125.png, parity24-footer-no-lyrics.png. Current wavecategories: parity24-wave-choice-{favorites,discovery,popular}.png; styles parity24-steering-web-proof.json. Currenttestsourcehashproof: parity24-ui-steering-verification.json(28/28), analyzerparity24-ui-steering-analyze.log(Noissues), webtiming+response4/4.

The following earlier brief/captures are historical round1 evidence and are superseded where they mention collapsed lyrics or144px compactheight. Final steering section below and evaluatorround2 are current.

# GlukWave +24 public UI review guide

Current implementation is integrated into the existing app; startup, compatibility runtime and packaging are root-owned.

## Local review
- Run `node work/qa/parity24-ui-server.mjs`; real source app fixture: http://127.0.0.1:5244/app/#library. This owns only original QA tracks/WAV/API/socket data, no real account traffic.
- Fixture `POST /api/qa/ui24` accepts `settings`, `clock`, `lyricStart`, `output:local|remote`, `track`. Web local playback uses actual WAV clock, so use the visible seek control for current-line/intro captures.
- Browser automation uses isolated `parity24-ui` session. `work/qa/parity24-ui-browser.mjs` creates baseline footer, wide, lyrics captures.
- Native tests: `apps/native/test/parity24_ui_test.dart`, existing `parity23_ui_test.dart` behavior remains except bottom transport now96px and compact lyric window144px. Root owns shared Flutter execution lock; coordinate before running.

## Observable design contracts
- Footer remains96px with lyrics in the track metadata rail, central transport/seek stay normal. No separate Words window, nested bordered card, or footer attribution link. Phone collapsed rail hidden to preserve compactness.
- Full-player excerpt is an understated left rule with caption, current and next line, above seek. Existing preference disables it. Full lyrics current and adjacent lines stay sharp; farther lines subtly defocus by distance and clear on hover/focus. High contrast and legacy TV avoid filters.
- Intro3/2/1 is derived from media time in the three seconds before first nonempty/non-musical-marker timed words. Empty introductory timing rows do not cancel it. Untimed/zero-start lyrics have no countdown; seeks update it in either direction, pause holds it.
- Web cover keeps one live album; measured FLIP translate animates between tabs. Complete fixed turn envelope stays; invisible lower air is reclaimed from spacing. Wide no-panel layout remains artwork left/controls right; smaller views stack.
- CD lid has opaque inner plastic and four thin edge faces, plus existing opaque body tray/back/edges. Native lid normal accounts for its14degree hinge. Front lower-right brand and hover extraction retained.
- Pointer lighting updates directly on requestAnimationFrame, without a CSS easing tail. Shape reset/flip can still ease. Native full view uses short incoming fade/slide, not an outgoing audio/player clone.
- `data-browser-profile=tv-legacy` styles use literal dark palette, flex layout, flat cover, no expensive blur and explicit remote-key focus. This is compatibility fallback, not physical Samsung proof.

## Current source captures
- work/qa/parity24-web-footer.png
- work/qa/parity24-web-wide.png
- work/qa/parity24-web-lyrics.png
- work/qa/native-parity24-intro-3.png
- work/qa/native-parity24-lyric-rail.png
- work/qa/native-parity24-full-lyrics-390.png
- work/qa/native-parity24-full-lyrics-1440.png
- work/qa/native-parity24-desktop-bottom-rail.png
- work/qa/native-parity24-desktop-bottom-remote-125.png
- work/qa/native-parity24-compact-window-125.png
- work/qa/native-parity24-cd-{0,82,100,180,260,360}.png

Initial web captures predate the final scoped margin/gradient specificity correction; independent evaluator is taking fresh current-source captures. Native captures are actual Flutter widget-tree captures, not physical OS UI. They do not assert hardware playback or Samsung browser success.

## Sources
Web: player-ui.tsx, lyric-timing.ts, album.tsx, mini.tsx (attribution removal only), focused-player.css, refinement21.css, reference-cover.css, six locale JSON catalogs; qa/lyric-timing.test.mjs.
Native: ui/mini_lyrics.dart, ui/lyric_timing.dart, ui/player.dart, ui/native19_desktop_transport.dart, ui/album_stage.dart, l10n/ecosystem_polish_strings.dart; compact-height-only lib/services/desktop.dart; test/parity24_ui_test.dart and superseded geometry expectations in parity23_ui_test.dart.

## Targeted checks
Native parity23+24 focused22/22 passed including hardened cues, optical packing and125% layouts (work/qa/parity24-ui-regression-final2.log). Final CD back-facing paint order refinement is with evaluator for fresh capture. Web typecheck and timing2/2 passed after helper hardening. No installer/APK/build/deployment has been performed by UI agent.

## Independent current-source acceptance

Final PASS: work/qa/parity24-evaluator-verdict.json and work/qa/parity24-evaluator-review-guide.md. The evaluator verified24current source hashes and31fresh captures(55/55). Firstthree motion samples now preserve the exact pre-toggle artwork rectangle before one smooth movement; legacyTVflat cover clears heading by33px, all lyricfilters are off and keyboardfocus is visible. Native current-source independent3-case verification passed, including the finalCDback-facing paint order. These public artifacts supersede the initial web screenshots above.

The UI agent closed its own parity24-ui browser and5244source fixture after evaluation; no owner/browser/production session was used. Fixture code remains reusable.

# Latest user steering — supersedes collapsed lyric design above

All collapsed/miniplayer lyrics are now removed: web footer, native bottom rail, compact desktop and quick desktop popup, phone mini. Full expanded player retains its current/next excerpt and full synchronized lyrics. Metadata is free for real device status. Compact window always116px; no lyric-driven resizing. Current captures: native-parity24-desktop-bottom-clean.png, native-parity24-desktop-bottom-remote-125.png, native-parity24-compact-window-125.png, parity24-footer-no-lyrics.png. Expanded excerpt coverage remains inparity23/24 tests.

Wave mode, mood and imported-taste genre selection now share quiet neutral surface fill, transparent border, no shadow/gradient, restrained accent icon and keyboard-focus ring. Current Favorite/New/Popular captures: parity24-wave-choice-favorites.png, parity24-wave-choice-discovery.png, parity24-wave-choice-popular.png; computed styles parity24-steering-web-proof.json.

Bloom and particles now respond more visibly to real measured energy. Bloom sharedJS/GLSL/Dart center amplitudes add.09/.04energy, width sensitivity1.5(up from.3), level sensitivity.65(up from.25). Atmeasured.25, total fixed-time fieldmass is2.282× silencebaseline. Particles sharedhelper increases amplitude, detailspan, bandspread, pointsize and brightness. No time-based fakeenergy;silencebaseline and reduced-motion handling unchanged. Webqa/wave24-response.test.mjs and nativewave_test.dart fixture checks verify bounded behavior and crossplatform equations.

CD geometry remains fullyfilled opaque:front/reverse/bodytray/back/allthickness. Ten angle captures now cover0,45,82,100,135,180,225,260,315,360; the space between an open lid/base naturally exposes backdrop, all actual planes remain opaque. FinalCDbackplane metadata and innerprint retained.

Currenttargetednative28/28passed, affectedanalyzerNoissues. Machine-readable affectedproof/sourcehashes: work/qa/parity24-ui-steering-verification.json; rawexpandedreporter work/qa/parity24-ui-steering-tests.log. Webtiming+wave4/4passed. No fullsuite/build rerun byUIagent. Source is frozen for evaluatorround2 and parent delivery.

Fixture5244 restarted for evaluatorround2; UI agent is not mutatingfixture while evaluationruns.

## Final steering acceptance

Round2 PASS: work/qa/parity24-steering-evaluator-verdict.json and work/qa/parity24-steering-evaluator-review-guide.md;35current sourcehashes+40captures matched75/75. SevenactualnativeUIcases+onefixed-phase paintercase passed, actualwebGPU/Canvasfixedenergy comparisonspassed, realremoteAndroidoutput named andkeyboardselectionfocus verified. The evaluatorclosed its own5245fixture/browser; UIagentclosed5244andparity24-steeringbrowser. No sourcechanges afteracceptance.
