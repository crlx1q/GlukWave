# Parity24 UI refinement

Implemented2026-10-15 on the existing GlukWave web/native design. Startup fixes, old TV JavaScript compatibility, release builds and deployment are owned by the parent implementation.

## Listening and lyrics

Lyrics appear only in the expanded player: its current/next excerpt and full synchronized text. Every collapsed/miniplayer surface is clean—web footer, native desktop bottom transport, desktop compact/quick windows and phone mini. The web/native desktop footer stays96px, the independent compact window116px and phone mini68px. Metadata space is reserved for the track and the real remote-device indicator. Artist metadata is plain text; web popup mini and footer contain no SoundCloud source hyperlinks. Full source details remain in the explicit full-player menu.

The full web/native excerpt uses one thin left rule, no enclosing card, and a clear current/next hierarchy. The existing lyricsUnderCover preference disables this expanded excerpt. Removing collapsed text also removes its extra lyric lookup and lyric-driven window resizing. The collapsed remote caption and transport reach remain verified at125%text.

Synchronized lyrics calculate3→2→1 from the actual playback position during the three seconds before the first nonempty timed words. Empty rows and standalone musical markers do not suppress the intro. There is no independent timer: pause holds the cue, seeking updates/cancels/restores it, zero-start and unsynchronized text have no countdown. The intro label is localized in all six application languages.

Distant full lyric lines gently lose sharpness with increasing line distance, capped at1.6logical pixels. Current/adjacent lines remain sharp. Web hover/focus clears defocus; high contrast and TV fallback avoid filters. Manual lyric scrolling retains its grace period; pane resizing recenters the active line once automatic following is allowed.

Native full views enter with a short incoming fade/slide, respecting reduced motion. Web tabs use a measured transform of the existing live cover, with no second player or duplicate outgoing album. Vertical layouts reclaim only empty lower projection from the complete rotation envelope; artwork is never scaled down during rotation. The native inner stage remains constant while its outer flow packs actual lower air. Wide artwork-left/control-right adaptation remains.

## Case and light

CD cases now have an opaque two-sided hinged lid with all four thin thickness surfaces in addition to the body tray, back and thick edges. Native visibility accounts for the lid hinge, and back-facing body metadata correctly occludes the opened lid. Brand placement and hover disc extraction remain. Vinyl geometry is unchanged.

Web reflection follows pointer coordinates in requestAnimationFrame directly, without a CSS interpolation tail. Tilt/reset and disc extraction can still ease separately. The cover keeps its full turn bounds and fixed artwork dimensions.

## Legacy TV CSS

The root-selected tv-legacy profile uses literal dark colors and flex composition, an economical flat cover, explicit keyboard focus and no expensive lyric filters. It avoids relying on unsupported min/clamp/grid/color-mix/selectors in critical listening controls. This stylesheet is not evidence of physical Samsung-browser verification.

## Verification

- Current web typecheck and two timing/defocus unit cases passed.
- Native parity23+24 focused regression22/22 passed, including phone/wide lyrics, seek-derived intro,96px footer, remote125% footer and410×144 compact window at125%.
- Full native1440×900 lyric view now asserts secondary controls remain within the initial viewport. Its normal metadata/lyric content still supports internal scrolling on constrained windows.
- The CD regression captures ten rotations with opaque reverse/edge assertions and unchanged inner turn bounds. The independent evaluator verified the final paint-order refinement on current source.
- Public captures/fixtures and source list: work/qa/parity24-ui-guide.md. Physical playback, TV engine success and OS notification appearance are outside these UI-only proofs.

## Changed UI files

Web: src/player-ui.tsx, lyric-timing.ts, album.tsx, mini.tsx(source credit only), focused-player.css, refinement21.css, reference-cover.css, wave.tsx, wave-math.ts, six locale JSON files; qa/lyric-timing.test.mjs and wave24-response.test.mjs.

Native: lib/ui/mini_lyrics.dart, lyric_timing.dart, player.dart, native19_desktop_transport.dart, album_stage.dart; lib/l10n/ecosystem_polish_strings.dart; lib/ui/desktop_player.dart, app.dart, widgets.dart; shared display equations inlib/core/wave_math.dart; only compact geometry inlib/services/desktop.dart; test/parity24_ui_test.dart, superseded geometry assertions in test/parity23_ui_test.dart, wave_test.dart and exportedparityfixture.

Initial round1 UI evaluation passed55/55source/capturematches. Finalsteeringacceptance is round2; see currentverificationbelow.

No APK, installer, package, install or production deployment was performed by the UI implementation agent.

## Wave preferences and response

Wave categories,moods and imported-taste genres use quiet neutral selection fill, transparent border, no borderglow/gradient/shadow, restrained accent icons and explicit keyboardfocus. Favorite/New/Popular current captures and computed styles are in the public guide.

Bloom and particles respond more visibly to real measured energy. Bloom's sharedJS/GLSL/Dart field increases center amplitudes, width and dotmass; at measured0.25 its fixed-time integrated field is2.282×the silencebaseline. Particles increase amplitude, fine-span, bandspread, pointsize and brightness through a shared boundedhelper. No time-based fakeenergy is introduced; silence and reduced-motion behavior remain. Web/native parity fixtures and response tests verify the same equations.

CD verification covers ten full-turn angles; every lid/body/interior/thickness plane is opaque. The natural gap between an open lid and its base can show the backdrop; the plastic faces do not become transparent. Inner/reverse printing and brand remain.

## Current verification and delivery boundary

After the final collapsed-text removal and wave refinements, affected native regression28/28 and analyzerNoissues passed. Web timing+wave response4/4passed. Root's earlier465-case full suite is the broad baseline; this UI agent did not repeat it. Current affectedproof/sourcehashes: work/qa/parity24-ui-steering-verification.json. Finalindependentround2PASS:35current sourcehashes +40captures matched75/75;7actualUIcases +1fixed-phase paintercase andactualwebGPU/Canvasenergycomparisons passed. Publicverdict/reviewguide:work/qa/parity24-steering-evaluator-verdict.json andwork/qa/parity24-steering-evaluator-review-guide.md. Exactlivecuecaptureautomation timing islimited/disclosed; mediatime helper/currentheld3 andunchangedpriorfullcueproof remain.

UI source frozen for parent packaging. No APK, installer, package, installation or production deployment was performed by this UI implementation agent.
