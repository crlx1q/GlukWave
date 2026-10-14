# Refinement21 public UI review guide

These changes use the actual GlukWave React and Flutter components. The three owner screenshots show regressions to fix. No new raster assets or mockup app are introduced.

## Decisions

- Output identity is a compact unboxed platform/name/listening signature under the track only while controlling another output. Local playback retains the ordinary Connect entry.
- Quick Connect is a device switchboard: platform, confirmed online/selected state, a small real track snapshot, and one transfer action. It has no duplicate play/seek/volume transport. A footer link opens full Connect. Same-installation other-window output can be reclaimed into the current surface.
- Full Connect preserves refresh, independent mode, transfer, removal confirmation, offline/last-seen/session data and per-device controls when independent listening requires them. The duplicate active-output transport is removed.
- Giant wave cause: legacy `.device-track > span { flex: 1 }` expanded the listening wrapper and `svg { width:100% }` amplified it. Wrapper/SVG bounds are now invariant, including flex-basis and both axes. Live dash loops; pause, reduced motion and visibility stop it.
- Native main wave formerly used `animation.value*90` and rewound every 90 seconds. It now accumulates elapsed phase, follows speed and stops while backgrounded. Web phase persists through effect reconstruction.
- Native Windows's listening rail already shows a current/next hierarchy. Web now has an optional wide-desktop two-line lyrics shortcut above the persistent player; it opens full lyrics and reuses the existing lyric request. Full-player compact preview uses current/next hierarchy above seek. Native matching full-player placement already existed. Both honor lyrics/lyricsUnderCover; small phones retain their full lyrics entry without the preview crowding controls.

## Evidence and reproduction

- `work/qa/refinement21-web-proof.json`: 11 actual-browser checks, widths 1440, 375, 320 at 125%, isolated original catalogue/socket/audio transport. This proves layout/interactions, not physical provider sound.
- `work/qa/refinement21-web-{1440,375,320}-{quick,remote,local}.png` plus full-menu/lyrics/player-preview captures.
- `apps/native/test/refinement21_ui_test.dart`: 4 focused real-widget cases including three viewport configurations and the 90-second phase boundary; passed.
- `work/qa/native-refinement21-{320,375,1440}-{quick-connect,local-output}.png`: actual FlutterApp, controller and bundled fonts/artwork.
- Existing refinement20 UI 7 cases passed after intentionally updating local-banner expectation. Native analyze is clean; web TypeScript check passed.

Live isolated preview: http://127.0.0.1:5191/app/#library. Start with `node work/qa/refinement21-preview-server.mjs` if needed. Socket.IO fixture supplies three card states (active Android, online Chrome Windows, offline Chrome Android), project art, original test lyric text and silent test audio. It sends no owner/provider traffic. POST `/api/qa/ref21` accepts `{output:'local'|'remote',settings:{fontScale:1.25,reducedMotion:true}}` and returns fixture state. Use a separate browser session from implementation's `refinement21-ui`.

Flutter uses existing short PUB_CACHE `C:/Users/alish/Documents/Codex/gw-pub-55712f`. Do not change dependencies or build packages from this UI task; root owns playback/runtime/release.
