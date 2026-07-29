# Reframer 0.11.0 build 4 audit and release readiness

Date: 2026-07-28
Status: source implementation validated and pushed; no build-4 notarization
or manual acceptance is claimed by this record yet

Historical build-1 through build-3 evidence remains in
[`AUDIT_2026-07-28.md`](AUDIT_2026-07-28.md). It must not be reused as proof
for build 4.

## Scope

Build 4 adds four material surfaces to the already remediated canonical overlay:

- aligned, resizable Shortcut Settings;
- expanded AVFoundation container selection;
- bundled VP8/VP9 WebM preparation with alpha;
- consent- and policy-gated YouTube playback.

This audit separates source/static evidence, background build/unit evidence,
Apple distribution evidence, and foreground/manual evidence. A check is not a
pass until its exact build-4 artifact produces the result.

## Implemented source contract

### Shortcut Settings

- One shared five-column `NSGridView` aligns enabled, shortcut, action,
  multiplier, and clear controls across every section.
- Content limits are 700×520 minimum, 780×1020 preferred, and 1100×1100
  maximum, clamped to the visible display.
- Compact heights scroll vertically; validated size persists.
- Focus traverses row-major and Tab is returned to AppKit instead of being
  recorded.

### Local media and WebM

- Native selection includes MP4/M4V/MOV, AVI, DV,
  MPEG/MPEG-2/transport-stream, and 3GP/3G2, subject to AVFoundation codec
  support. Checked-in real playable fixtures cover AVI, DV, MPG, MPEG, M2V,
  TS, MTS, M2TS, 3GP, and 3G2; M2V preflight requests precise duration and
  timing metadata.
- The bundle contains universal `Contents/Helpers/reframer-ffmpeg`, built from
  FFmpeg 8.1.2 and libvpx 1.16.0 with network protocols disabled.
- VP8/VP9 WebM input is opened by the sandboxed app and inherited by descriptor
  into the helper. Output is temporary ProRes 4444 with PCM audio, preserving
  alpha before normal AVFoundation playback, navigation, filtering, and audio.
- Preparation requires 2 GB of temporary capacity, caps output at 64 GB,
  supports bounded cancellation, stops after five minutes without output
  progress or 12 hours total, and cleans partial/prepared output across
  failure, replacement, cancellation, termination, and stale startup cleanup.
  Unit policy coverage proves progress extends only the stall deadline and
  that a no-output process reaches the stall timeout.
- FFmpeg/libvpx license, patent, revision, source-download, and source-offer
  records ship in `ThirdPartyLicenses`; the helper is rebuildable from
  `scripts/build_media_helper.sh`. Embedded temporary build paths mean the
  complete binary is not claimed to be byte-for-byte reproducible.

### YouTube

- Only supported HTTPS YouTube video-link forms are parsed.
- First use requires explicit privacy and terms consent. Only the accepted
  notice version is stored locally; pasted links and viewing history are not.
- Every identifier receives a YouTube Data API `videos.list` Made for Kids
  preflight before player HTML is created. The request query contains the
  parsed identifier, the key is sent in `X-Goog-Api-Key`, and Google receives
  ordinary HTTPS request/network metadata such as source IP. Missing key,
  rejection, unavailable video, or unknown status fails closed.
- The approved player is YouTube's privacy-enhanced embed in a nonpersistent
  `WKWebView`, with no autoplay, adaptive quality, standard controls, links,
  branding, ads, settings, and WebKit element fullscreen. The web view fills
  the complete video canvas and remains at least 200×200 points; YouTube owns
  its internal aspect fit and letterboxing. Session cookies/player data can
  exist while it runs, but are not persisted and are cleared before each
  embed.
- Play/pause, time seek, mute, volume, and window controls are shared.
  Exact frames, zoom/pan, opacity, and filters are unavailable. Filter and
  transform controls remain disabled from pending preflight through playback.
- Reframer unlocks before YouTube preflight and disables click-through Lock
  through playback so standard controls, captions, settings, fullscreen, and
  links remain interactive. Always on Top When Unlocked remains available.
- Timeline previews seek without seek-ahead; release/discrete seeks allow it.
  The ready snapshot does not overwrite saved native-media volume or mute.
  Official-player mute does not zero retained volume, so the player's own
  Unmute restores its prior audible level.
- Visibility/session transitions pause playback without automatic resume.
- The app entitlement set is App Sandbox, user-selected read-only, and network
  client. Network behavior is limited to the explicit YouTube preflight/player
  workflow; Help itself remains native and offline.

### Release controls

- Packaging fails closed without `REFRAMER_YOUTUBE_DATA_API_KEY`.
- The key is written only to a mode-0600 temporary xcconfig as
  `YOUTUBE_DATA_API_KEY`, redacted from build output, and never committed.
- Bundle validation allowlists the helper, third-party records, YouTube Help
  page, exact app/helper entitlements, architectures, and deployment targets.
- A desktop API key remains extractable. API/quota restriction and monitoring
  are required; a narrow production preflight backend is recommended.

## Background validation ledger

Update these rows only with build-4 output:

| Gate | Build-4 result | Evidence |
|---|---|---|
| Product/repository/Help-index validation | Passed | Regenerated the CoreSpotlight Help index, then `scripts/validate_repository.sh` passed against the final source and searchable Help semantics |
| Shell syntax and JSON/plist lint | Passed | Repository validator plus focused `bash -n`, `json.tool`, and `plutil` checks |
| Debug build | Passed | The background unit runner completed `build-for-testing` for the app and unit target with no foreground launch |
| Universal Release build | Passed for dirty source candidate | Background `xcodebuild build`, arm64/x86_64, macOS 15.0; both app and helper contain both architectures. A clean source stamp remains a packaging gate |
| Unit/AppKit tests | Passed | Final background run executed 302 tests with 0 failures; no UI test target or foreground app automation ran |
| Static analysis | Passed | `xcodebuild analyze`, Debug, generic macOS destination |
| DocC build | Passed | `xcodebuild docbuild`, Debug, generic macOS destination; all DocC topic references resolved |
| Exact candidate bundle contract | Passed | `scripts/validate_bundle.sh` accepted ad-hoc-signed Reframer 0.11.0 (4), app/helper architectures and deployment targets, exact resource/Help/license allowlists, per-architecture helper identity and embedded entitlements, canonical helper provenance, and deterministic code comparison |
| VP8-alpha and VP9-alpha helper round trip | Passed | Checked-in helper SHA `bb1f4d0148461b835a659a01b3898e97d375b6de57632182192bbbfe73c0154c`; VP8+Vorbis, VP9+Opus, and VP9 no-audio fixtures preserved expected alpha pixels and audio mapping |

The WebM fixtures were generated with the exact Homebrew FFmpeg 7.1.1_3
binary SHA-256
`7697b094387e2918821fe7480c73f5d44543817096e9d5b5fafe58ecd6912569`
(Lavc61.19.101/Lavf61.7.100, libvpx 1.15.2, Opus 1.5.2, libvorbis 1.3.7).
Canonical fixture SHA-256 values are recorded in
`Reframer/ReframerTests/TestFixtures/README.md`; regenerated Matroska
containers are not byte-deterministic because FFmpeg randomizes `TrackUID`.
All three decode to the same normalized raw-alpha SHA-256,
`c04eca3b362f3261a252f26aa7b0a27a0e0eb27ec4289f4a05f7ce9b22daff81`.

## Apple distribution ledger

| Gate | Build-4 result | Evidence |
|---|---|---|
| Clean `main` equals `origin/main` | Passed | The implementation and final audit commits were pushed; final post-push verification confirmed a clean `main` at `origin/main` |
| Configured YouTube Data API key | Blocked | `REFRAMER_YOUTUBE_DATA_API_KEY` is absent locally and no repository secret or variable is configured; source builds intentionally fail closed without a key |
| Developer ID app/helper signatures and exact entitlements | Pending | — |
| Apple notarization accepted | Blocked | `xcrun notarytool history --keychain-profile notary` reports no matching Keychain password item; no build-4 submission is possible with the current profile |
| Ticket stapled and validated | Pending | — |
| Gatekeeper accepted | Pending | — |
| Final ZIP extracted and revalidated | Pending | — |
| Installed `/Applications/Reframer.app` replaced and verified | Pending | The installed app remains the notarized Reframer 0.10.0 (3); it has not been replaced by build 4 |
| Old indexed app/build artifacts removed | Passed | Unregistered six generated app bundles; removed the repository `.artifacts` tree, Reframer Xcode DerivedData, profiling/Python caches, and 28 Reframer-only temporary paths; pruned 11 stale temporary-worktree registrations; Spotlight now returns only `/Applications/Reframer.app` |

## Manual acceptance required

No foreground automation or manual pass is authorized or claimed by this
record. The operator will test the installed final build:

1. resize Shortcut Settings through its range, confirm neat shared columns,
   see all rows at the preferred height, scroll at compact height, traverse by
   keyboard, and confirm restored size;
2. load representative native containers and VP8/VP9 WebM with alpha/audio;
   verify transparent compositing, playback, frames, scrub, mute, filters,
   cancellation, replacement, and cleanup;
3. accept the YouTube notice and load a real link with a configured Data API
   key; verify preflight, no autoplay, adaptive quality, standard player UI,
   WebKit element fullscreen, play/pause, time scrub, mute/volume, errors,
   external links, hidden/occluded pause, automatic unlock, disabled Lock,
   Always on Top When Unlocked, and unavailable frame/filter/transform
   controls; confirm every required player interaction remains reachable;
4. use macOS and Mosaic move/resize shortcuts while unlocked and confirm video
   plus controls remain one integral window;
5. with local media loaded, lock with Always on Top When Unlocked disabled and
   confirm the entire overlay is above ordinary app windows,
   immovable/resistant to Mosaic, and pointer-transparent across both media and
   controls; unlock globally;
6. open Help from both menu and Command-?, navigate all updated pages, and
   confirm nonblank native content plus system-browser policy links;
7. relaunch and verify preferences, window geometry, Shortcut Settings size,
   and the one-app Spotlight result.

Only after those rows and observations are recorded against the exact
installed build may this document call build 4 release-ready.
