# GlukWave +25 public UI review guide

Current integrated sources are frozen for independent evaluation. This is refinement of the established web/native brand; root owns startup recovery, backend date metadata, OS notification services and delivery builds.

## Final design contracts

- Favorite tracks follow their actual like order, newest first. New GET maps mark an already sorted server response; old append-order caches/servers reverse exactly once. Optimistic intention dates are captured once, survive overlay replay, reconcile authoritative dates/null and roll back with the edit. Confirmed private caches retain maps per account.
- Library defaults to recent account addition, history to recent recorded listening, playlists to saved membership order. The discreet six-language Sort control offers newest/oldest/title/artist/duration and playlist original order. Date sorts use actual account/membership maps, with deterministic legacy order fallback, never another listener's global catalog discovery date. Sorting copies only the visible view and its playback queue; the reorder editor still uses saved original order. Native preference keys include server/account namespace; web keys include account.
- Current/next lyrics sit beneath the artwork in the expanded player on desktop and stacked layouts. Existing disable preference remains. All collapsed footer/mini/popup players remain lyric-free and reserve remote device status. Title/artist have6–9px native and9px web breathing; artwork-to-metadata receives24px native /18–22px web instead of touching or the former large empty gap.
- Full lyric current, previous and next rows remain sharp. Further rows progressively defocus1.15px per extra line up to5px and dim with distance. Hover/focus/manual scrolling clear the depth effect for readability. TV/high-contrast do not require expensive filters. Timed3→2→1 remains media-clock-derived, unchanged.
- Web vinyl geometry remains the user's preferred version. Native rigid scene is now camera-projected physical planes with overlap-aware per-pixel-region occlusion. Flutter Stack has no CSS preserve-3d z buffer; average plane order is insufficient for an open lid crossing the body silhouette. Native subtracts only overlapping nearer opaque regions using affine reciprocal perspective depth; lid/front/back/tray/edges and a circular disc remain real separate surfaces. Twelve poses per vinyl/CD include full turns and±38pitch. Paper/rear print, brand and disc extraction remain.
- A fixed environmental light follows the actual displayed orientation of the cover, through CSS interpolation/inertia, on both axes. Moving the raw pointer without rotating changes no reflection. Keyboard arrows rotate the focused cover without bubbling into global skip shortcuts.
- Only loading accelerates to a physical900ms loop; playing status remains1200ms. Both ignore global appearance speed and stop under reduced motion/lifecycle restrictions. Native reads the physical stopwatch phase directly, avoiding stale phase after a delayed frame.
- Invisible full-turn layout space cannot own cover gestures. Web growth/stage/object pass pointer events; only physical opaque faces opt in. Controls own their higher hit layer. Narrow player layout is a genuine vertical scroll container instead of overflow:hidden. Native full-cover pan and rotation/mouse regions defer to visible projected children; the empty envelope passes touch to the scroll view. Flat cover margins follow the same rule.
- Expanded header displays the active wave's localized mode/mood when waveActive; ordinary tracks keep Now playing. No new collapsed lyric UI.

## Isolated review

`node work/qa/parity25-ui-server.mjs` serves the real source app on http://127.0.0.1:5254/app/#library with original QA account, three QA tracks, actual decoded silent WAV, local photographs, Socket.IO and date maps. No owner account/site requests, credentials, installs or deployments occur. QA endpoint `/api/qa/ui25` accepts settings/output/clock/lyricStart and active wave/mode/mood. Its library and membership data exercise new-date and saved-order differences.

Native captures render the real AlbumStage/PlayerPage/GlukWaveApp using isolated real controller and decoded project photography. They are Flutter test surfaces, not installed OS UI or physical device playback. Debug ribbon visible in test wrappers is outside release app configuration.

## Current evidence

- `parity25-web-focused.log`:12/12 focused order/journal/lyric cases, including missing Intl.Collator fallback. Root separately runs full web QA.
- `parity25-web-typecheck.log`: current typecheck.
- `parity25-web-runtime-proof.json`:14 browser records, library sort and saved order, source playback, excerpt beneath art at1440/768/375/320, pointer-stable/orientation-dependent light, full lyric depth, no collapsed text and125%sort controls.
- `parity25-hit-runtime-proof.json`: actual native HTML range input events, unchanged cover angle during seek, elementFromPoint through cover turn/queue movement at638×716 and1440×900 in CD/flat, scroll container movement and Wave header. Low-level agent-browser mouse wheel emits at0,0 even after moving/batching, so this proof explicitly uses its supported scroll-container command; physical mouse-wheel default at the intended pointer is not claimed. Blank target/auto overflow and native actual touch scrolling cover the underlying interaction contract.
- `parity25-native-ui-final.log`:46/46 finite baseline including long metadata, full-turn envelope/heading clearance, CD opaque surfaces, layout and physical clocks.
- `parity25-ui-final-steering.log`:27 current affected UI/clock cases passed after urgent interaction/header changes; initial hit test file load occurred during root's transient duplicate localized key and was recovered separately. Do not report the file's whole command as green.
- `parity25-native-hit-final.log`:4/4 recovered current actual seek/touch-scroll/Wave-caption cases, CD+flat narrow/wide. `parity25-native-ui-final-analyze.log`: No issues.
- `parity25-ui-verification.json`: final source/capture SHA256 list and explicit scope/limits, for evaluator hash comparison.

Current visual files are `parity25-web-*.png`, `parity25-hit-*.png`, and `native-parity25-*.png` in work/qa. They contain original fixture material only. Owner video frames named parity25-owner-video-* are excluded from this guide/evidence/delivery.

Do not infer physical TV/Android playback or OS notification rendering from this UI evidence. Root owns one final build per platform after independent evaluation. No extra binary builds were performed by the UI agent.
