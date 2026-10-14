# Parity23 UI implementation

Implemented on 2026-10-14 against the existing +22 application. This is a focused parity pass; the reference sleeve geometry, actual album imagery, established colors and Manrope typography remain in use.

## Behavior

- Quick Connect and its full directory read each device's own confirmed track and playback state. Only a local output can show the immediate local selection. An account/cloud directory appears first in Flutter, followed by a separate LAN/Wi-Fi section. Cloud rows call `transferCloud`, which the root implementation owns.
- Selected output captions are neutral in all six languages; they no longer falsely append “paused” when the device's own state says playing.
- The full player and desktop transports use a small framed excerpt headed “Слова”: current lyric first, next lyric below, then the seek bar. The existing `lyricsUnderCover` preference disables excerpts. 3D cover, short height and density no longer suppress the excerpt; the listening column can scroll internally.
- The web's extra floating right-hand Words card is removed. Collapsed desktop web lyrics are integrated into the central bottom transport using the full player's existing lookup, with no extra request. Phone collapsed transport stays compact.
- A preview stays on its selected track until that track starts playing. After adoption it follows later track changes, including title, cover and lyrics.
- Loading and listening wave glyphs keep a fixed physical 1200ms cycle, independent of appearance speed. Native uses a Stopwatch for real elapsed time and a Ticker only for paint scheduling, so global timeDilation does not alter the wave cycle. Web fixes the CSS cycle to1.2s. Reduced motion, background lifecycle and TickerMode stop the native loop.
- Incoming track cover/metadata slides in the queue direction and fades briefly. The transition owns no playback state, no second player and no outgoing media clone. Energy saving/reduced motion shows the new content immediately.
- Phone mini transport is 68 logical pixels high with 44-pixel touch targets. The full player hides local volume using the actual audio `hardwareVolume` policy; controlling another output retains appropriate remote control.
- The compact phone transport uses its second metadata line for the remote output while controlling another device, preserving its 68px height at 125% text size. Artist details remain available in the full player; a third compact line no longer overflows behind Quick Connect.
- Native Brand uses the exact path from the web mark as a crisp vector in its square tile, replacing rectangular GIF frames. Existing launcher artwork was already the correct web mark and was kept. The QR scanner glyph now has finder squares and scanning corners instead of a hashtag-like center.
- Android widget default width is three cells: compact 220×72dp, wave 220×176dp. Compact exposes next at 220dp and previous at 310dp; wave exposes previous/next at 180dp and like at 220dp. Play stays 48dp and adjacent controls stay 44dp. Large text hides the secondary status line at the shorter wave height. Existing receiver, grant, immutable PendingIntent and account boundaries are preserved.
- Native desktop bottom transport stays 94px when lyrics are missing/disabled, and reserves 160px only for a confirmed excerpt. The independent mini window stays 116px without lyrics and grows to 172px only when an excerpt exists.
- Android's full Connect settings includes an understated “Connect при выключенном экране” switch, localized in all six application languages. It explains battery use and the notification stop action, and binds to the root-owned background-connection service and persisted preference. Unsupported platforms do not show the switch.

- Following the latest user steering, spacious desktop returns to cover LEFT / controls RIGHT, with lyrics integrated above seek. Narrow/short windows and phones keep cover ABOVE controls. Both arrangements retain the complete sleeve geometry.
- Full-player sleeve size follows horizontal room, independently of the controls' height budget. Loading lyrics or shortening a desktop window cannot shrink the sleeve; the listening column scrolls internally instead.
- CD cases now have an opaque tray/interior with a circular recess behind the disc, plus opaque thickness surfaces on web. The lid opening and hover disc movement remain.
- The main music wave lifts normal measured energy with the same `1 - (1 - energy)^2.4` response on web/native, applied once before smoothing. Silk width, curvature, dot size and brightness now respond more clearly; silence remains zero and the ambient base is preserved.

## Public verification

`npm run check --workspace @glukwave/web` passed. Eleven distinct focused UI cases are exercised in `apps/native/test/parity23_ui_test.dart`: cover modes/lyric visibility, preview adoption, independent device row, compact phone/vector brand, desktop mini lyrics/adaptive height, loader cycle, reduced-motion content update, actual hardware-volume phone policy and remote controls, bottom transport availability, and opposing next/previous motion. Ten passed together after the layout correction; the hardware case passed separately after moving its fixture construction to the real async zone. Root runs the combined final suite. Four new steering checks passed separately: adaptive desktop with opaqueCD plus actual real-clock loading/listening checks at speed0.5/1/2 under global timeDilation. The 15-case UI file retains the previous behavior cases.

Public screenshots from the real Flutter widget tree are under `work/qa/`:

- `native-parity23-phone-3d-lyrics.png`
- `native-parity23-phone-2d-lyrics.png`
- `native-parity23-desktop-mini-lyrics.png`
- `native-parity23-independent-connect.png`
- `native-parity23-phone-mini-brand.png`
- `native-parity23-phone-hardware-volume.png`
- `native-parity23-desktop-bottom-lyrics.png`
- `native-parity23-wide-cd-opaque.png`

The hardware-policy capture explicitly constructs `hardwareVolume: true`; viewport width alone is not treated as Android. Test DSP/output is isolated while the real controller/audio UI policy is retained. Android RemoteViews tests are updated for the new responsive breakpoints; root performs the actual Android unit verification. Physical launcher's shape, Android notification shell appearance, live handset timing and production multi-device network behavior are not asserted by widget screenshots.

## UI-owned source

Web: `apps/web/src/devices-popover.tsx`, `player-ui.tsx`, `refinement21.css`, `focused-player.css`, `reference-cover.css`, `album.tsx`, `morph-icon.tsx`, `wave.tsx`, `wave-math.ts`, `wave-silk.ts`.

Native: `apps/native/lib/ui/mini_lyrics.dart`, `player.dart`, `player_gestures.dart`, `motion_icons.dart`, `widgets.dart`, `connect_device_tile.dart`, `connect_picker.dart`, `connect_panel.dart`, `lan_panel.dart`, `native19_desktop_transport.dart`, `desktop_player.dart`, `physical_wave_clock.dart`, `device_labels.dart`, `silk_wave.dart`, `album_stage.dart`; `apps/native/lib/l10n/ecosystem_polish_strings.dart`; the compact geometry section of `apps/native/lib/services/desktop.dart`; `apps/native/test/parity23_ui_test.dart`. Existing focused/cover22 assertions now test the latest adaptive desktop preference while preserving full-turn geometry assertions. Legacy native19 reachability/player-details fixtures retain all control-reach and constant-cover-size checks, using internal scroll when needed. The vector speed test now checks the requested physical clock rather than the superseded speed-dependent cycle.

Android: `apps/native/android/app/src/main/res/xml/glukwave_player_widget_info.xml`, `glukwave_wave_widget_info.xml`, `res/layout/glukwave_widget_player.xml`, `kotlin/tech/gluk/glukwave/HomeWidgets.kt`, and `src/test/kotlin/tech/gluk/glukwave/HomeWidgetsTest.kt`.

Root owns `controller.dart`, `services/audio.dart`, server synchronization, notification actions, builds and delivery. No installer/APK build, deployment or version bump was performed by the UI implementation agent.
