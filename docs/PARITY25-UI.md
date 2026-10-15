# GlukWave +25 interface refinements

Favorites now appear newest first using like timestamps; old cached append order remains compatible. Library and playlist views include local per-account sorting, with playback following the visible order. Original playlist order and drag/reorder tools are preserved. Account addition dates and playlist membership dates are distinct from global source discovery.

Expanded current/next lyrics sit under the artwork, with more space around metadata. Collapsed players remain lyric-free. Full text keeps the current/adjacent rows sharp and progressively blurs/dims distant rows, clearing during manual navigation/focus. Existing lyric preference and media-timed intro remain.

Native 3D uses projected opaque surfaces and depth-correct overlap clipping for the case, hinged lid and disc. Web vinyl geometry remains. Fixed environmental reflection responds to displayed orientation, not raw mouse movement. Loading uses a900ms physical loop while playing status stays1200ms.

Invisible artwork layout envelopes pass pointer/touch input; only real physical faces own cover gestures. Narrow web player has normal vertical scrolling and seek controls retain hit priority through cover/tab movement. Native blank cover margins likewise allow natural scrolling. The expanded header identifies an active Wave mode/mood.

Playback rails now paint their position locally between authoritative samples. The presentation helpers stay isolated from application state and commands, preserve drag ownership and use physical time in Flutter. Local web playback reads the actual media clock; remote samples have a finite horizon rather than advancing forever. Canonical remote snapshots currently contain no playback-rate field, so their existing1× interpretation is retained.

Delivered verification, isolated capture guides and source/capture hashes live in docs/verification/2026-10-16/parity25. The earlier parity25-ui-verification.json records the visual baseline before the added progress helpers; final progress and independent-evaluation proofs identify the current sources. Startup, notification services, backend dates, release checks and binaries are documented by the parent implementation.
