# Reframer 0.11.0 build 4 audit and release readiness

Source audit date: 2026-07-28
Distribution completion date: 2026-07-29
Status: build 4 is signed, notarized, stapled, Gatekeeper-accepted, installed,
and ready for operator review; no manual acceptance is claimed by this record
yet

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
| Universal Release build | Passed | `mac-notarize --dmg` built clean source commit `1cd5092` with a mode-0600 YouTube xcconfig; both app and helper contain arm64 and x86_64 and target macOS 15.0 |
| Unit/AppKit tests | Passed | Final background run executed 302 tests with 0 failures; no UI test target or foreground app automation ran |
| Static analysis | Passed | `xcodebuild analyze`, Debug, generic macOS destination |
| DocC build | Passed | `xcodebuild docbuild`, Debug, generic macOS destination; all DocC topic references resolved |
| Exact candidate bundle contract | Passed | `scripts/validate_bundle.sh` accepted the Developer ID signed, stapled Reframer 0.11.0 (4) app before installation, from the mounted DMG, and after installation, including the configured YouTube key, clean source stamp, app/helper architectures and deployment targets, exact resource/Help/license allowlists, per-architecture helper identity and embedded entitlements, canonical helper provenance, and deterministic code comparison |
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
| Clean `main` equals `origin/main` | Passed | Release source commit `1cd5092` was clean, on `main`, and exactly equal to `origin/main` before the build |
| Configured YouTube Data API key | Passed | Enabled YouTube Data API v3 and API Keys API on `forge-ivg`; created the API-restricted `reframer-youtube-data-v2` key, stored it in the login Keychain and as the encrypted repository `REFRAMER_YOUTUBE_DATA_API_KEY` secret, and received HTTP 200 with a definite Made for Kids value from a live `videos.list` preflight |
| Developer ID app/helper signatures and exact entitlements | Passed | App and universal helper are signed by `Developer ID Application: Ilya Gusinski (7S422NVLUK)` with Hardened Runtime, secure timestamps, exact entitlement allowlists, and no prohibited debugging/library-validation entitlement |
| Apple notarization accepted | Passed | App submission `e603ea49-9fe4-46f7-a578-9ac9f300b5ea` and DMG submission `00c2e894-ecdf-44bb-98d4-360766a70462` were accepted |
| Ticket stapled and validated | Passed | `stapler validate` passed for the built app, separately notarized DMG, mounted-DMG app, and installed app |
| Gatekeeper accepted | Passed | `spctl` reports `source=Notarized Developer ID` for the app before installation, the DMG, mounted-DMG app, and installed app |
| Final distribution artifact mounted and revalidated | Passed | The read-only mounted DMG passed the full bundle contract, deep strict signature verification, ticket validation, and Gatekeeper assessment; DMG SHA-256 is `d80a9886585ae5b633ef8e6201015e2d0e6ee5e0fa5ae4db323d8c1b7f3d89c5` |
| Installed `/Applications/Reframer.app` replaced and verified | Passed | Replaced 0.10.0 (3) only after a rollback copy existed; installed 0.11.0 (4) passed the full bundle contract, configured-key check, universal architecture checks, deep strict signature verification, ticket validation, and Gatekeeper assessment |
| Old indexed app/build artifacts removed | Passed | Removed the generated Reframer DerivedData app after unregistering it; retained only the current notarized DMG and checksum under ignored, non-indexed `dist/`; Spotlight returns only `/Applications/Reframer.app` |

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
