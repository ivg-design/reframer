# Reframer feature contract

This is the implemented source contract for Reframer 0.11.0 build 4. It does
not claim that a candidate passed manual interaction or Apple distribution
gates.

## Media sources

- Open or drop local WebM, MP4/M4V/MOV, AVI, DV,
  MPEG/MPEG-2/transport-stream, and 3GP/3G2 containers.
- Preflight native assets through AVFoundation and keep playback, Core Image,
  dimensions, audio range, and navigation on one selected usable video track.
- Prepare VP8/VP9 WebM with the bundled universal, network-disabled FFmpeg
  8.1.2/libvpx 1.16.0 helper. A temporary ProRes 4444/PCM intermediate
  preserves alpha and then uses the same AVFoundation features as other local
  media.
- Refuse WebM preparation without 2 GB of temporary capacity, cap an output at
  64 GB, stop after five minutes without output progress or 12 hours total,
  support cancellation, and clean prepared files on failure, replacement,
  cancellation, termination, and stale-output startup cleanup.
- Open a user-supplied YouTube link only after first-use consent and a
  per-video Made for Kids Data API preflight. Failure or unknown status stops
  before the player is created. Store only the accepted consent-notice version
  locally, never the pasted URL or viewing history.
- Use YouTube's privacy-enhanced embed in a nonpersistent WebKit data store
  that is cleared before every embed, with no autoplay. YouTube uses adaptive
  quality; the supported API cannot force maximum quality.
- Share play/pause, time seek, mute, volume, and window controls with
  YouTube. Keep its standard controls, links, branding, ads, settings, and
  WebKit element fullscreen visible. From pending preflight through playback,
  transform/filter controls stay disabled. Exact frames, zoom/pan, opacity,
  and filters are unavailable for that source. The web view fills the video
  canvas and stays at least 200×200 points; YouTube owns its internal aspect
  fit and letterboxing.
- Automatically unlock before YouTube preflight and keep click-through Lock
  disabled through playback. YouTube's required controls, captions, settings,
  fullscreen, and links must remain interactive; use Always on Top When
  Unlocked to keep that source above ordinary app windows.
- Use conservative no-seek-ahead timeline previews while dragging, then allow
  seek-ahead on release and discrete seeks. Keep YouTube ready snapshots from
  overwriting saved native-media volume or mute preferences. Mute through the
  official player mute state without setting retained volume to zero, so
  YouTube's own Unmute restores the prior audible level.

## Local playback and inspection

- Play, pause, replay from end, scrub with coalesced preview, and finish on an
  exact decoded sample when exact indexing is available.
- Treat the latest Play or Pause command as authoritative across startup,
  replay, and scrub handoffs.
- Navigate decoded presentation timing after indexing, with a labeled
  constant-rate estimate when cursors are unavailable or the 2,000,000-sample
  ceiling is reached.
- Zoom from 10% through 1000%, pan by pointer or keyboard, set opacity from 2%
  through 100%, and use native quick filters or the advanced filter stack.

## Overlay

- One canonical transparent overlay window contains video and controls, so
  macOS and Mosaic move and resize the complete overlay while it is unlocked.
- The preferred 1,060-point width uses one 48-point control row. Widths from
  the 640-point minimum through 919 points use two rows totaling 96 points;
  every control remains visible and accessibility-reachable.
- For native or prepared local media, Lock mode uses the public status-bar window tier above normal, floating,
  modal, and utility windows, makes video and controls pointer-transparent,
  and disables moving and resizing.
- System pop-up menus, drag UI, the screen saver, and assistive-technology
  windows retain their higher critical-system precedence.
- Lock entry requires the exact configured global Lock/Unlock chord.
  Registration loss automatically unlocks and reports recovery guidance.

## Shortcuts and accessibility

- A single dispatcher handles key, menu, and registered global commands.
- Command-O, Option-Command-O, and Command-? are fixed menu/Help commands and
  are not Shortcut Settings rows. The 14 editable rows cover playback, frame
  stepping, pan, reset, local/global Lock, panel, and filter actions; pointer
  zoom gestures are also fixed.
- The lock chord stays registered during normal operation. Local-media frame
  variants are registered only when loaded, locked, and exact or estimated
  navigation is available.
- Registered hot keys need no Accessibility or Input Monitoring permission.
- Resizable Shortcut Settings uses one shared five-column grid to align every
  enabled state, shortcut, action, multiplier, and clear control. It remembers
  a validated size, scrolls at compact heights, and follows row-major keyboard
  focus; Tab is never captured as a shortcut.
- Invalid, reserved, duplicate, modifier-collapsing, and unsafe global chords
  are rejected with an explanation; conflicts offer retry.
- Controls expose task-oriented VoiceOver labels, values, ranges, state, and
  actions. Panel focus and Escape restoration are predictable, and live
  contrast, transparency, and motion accommodations remain visible.

## Privacy and distribution

- App Sandbox uses user-selected read-only files plus outbound network client.
  The network scope is the explicit YouTube preflight/player workflow; there
  is no analytics, updater, telemetry, or native executable download.
  Authorized YouTube playback does load remote web content and IFrame API
  JavaScript in the isolated WebKit process; it never downloads native code or
  plug-ins.
- The YouTube Data API request is ephemeral. Its query contains the parsed
  video identifier, the key travels in `X-Goog-Api-Key`, and Google still
  receives ordinary HTTPS request/network metadata such as source IP.
- The WebKit data store is nonpersistent and cleared before every embed.
  Session cookies or player data may exist while the player runs but are not
  persisted. Reframer stores no URL history, viewing history, or YouTube
  credentials; its only YouTube-related preference is the accepted consent
  notice version.
- Bundled Help renders through native AppKit and does not fetch network
  content. Allowlisted terms/privacy links open in the system browser.
- The runtime allowlist includes the separately signed inherited-sandbox WebM
  helper and `ThirdPartyLicenses` source/license records.
- Release acceptance requires universal Developer ID signatures, exact app
  and helper entitlements, notarization, stapling, Gatekeeper, and final-ZIP
  checks. These external Apple checks are never inferred from a source build.

The machine-readable authority is
[`product-contract.json`](product-contract.json).
