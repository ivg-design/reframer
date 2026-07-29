# Changelog

Notable Reframer changes are recorded here. The project uses semantic
versioning once a build is published; earlier repository milestones were
development snapshots, not production releases.

## [0.11.0] - Unreleased

### Added

- Local AVI, DV, MPEG/MPEG-2/transport-stream, 3GP, and 3G2 container
  selection through AVFoundation, subject to the codecs macOS can decode
- VP8 and VP9 WebM preparation through a bundled universal, network-disabled
  FFmpeg 8.1.2/libvpx 1.16.0 helper. WebM alpha is preserved in a temporary
  ProRes 4444 intermediate and audio is converted to PCM
- Cancellation, disk-capacity checks, a 64 GB output ceiling, a five-minute
  no-progress watchdog, a 12-hour absolute runtime ceiling, replacement and
  termination cleanup, and startup cleanup for stale WebM intermediates
- Consent-gated YouTube playback through a privacy-enhanced,
  nonpersistent `WKWebView`, preceded by a per-video Made for Kids lookup
  through the YouTube Data API
- A local YouTube privacy/terms Help page and explicit source/license records
  for the bundled media helper

### Changed

- Shortcut Settings now uses one shared five-column grid for consistent
  alignment across sections. The panel is resizable, remembers a validated
  size, scrolls at compact heights, and traverses controls in row-major order
- YouTube shares play/pause, time seek, mute, volume, and window controls.
  It keeps YouTube's standard controls, links, branding, ads, settings, and
  fullscreen behavior; quality remains adaptive because the supported embed
  API cannot force maximum quality
- Exact frame stepping, zoom/pan, opacity, and Core Image filters are disabled
  for YouTube because those operations are not provided by the IFrame Player
  API and must not obscure or transform the embedded player
- Click-through Lock is unavailable from pending YouTube preflight through
  playback. Reframer automatically unlocks so YouTube's required controls,
  captions, settings, fullscreen, and links remain interactive; Always on Top
  When Unlocked is the topmost option for that source
- App Sandbox now includes outbound network-client access scoped by product
  behavior to the explicit YouTube workflow. Bundled Help remains native and
  offline; allowlisted policy links open in the system browser
- Release packaging requires `REFRAMER_YOUTUBE_DATA_API_KEY`, injects it
  through the Xcode build setting, and rejects missing or unexpanded values
- The release bundle allowlist includes the separately signed inherited-
  sandbox WebM helper, its stable `com.reframer.app.ffmpeg` signing identity,
  and bundled third-party license/source records

### Security

- The YouTube Data API client uses an ephemeral session, the player uses a
  nonpersistent website data store, and the app fails closed before creating
  player HTML if the required Made for Kids lookup is missing, rejected, or
  inconclusive
- YouTube never autoplays. Reframer pauses it when the app/window becomes
  hidden or occluded and does not request or store YouTube credentials,
  pasted-link history, or viewing history. Session cookies or player data can
  exist while the player runs but are never persisted; every embed starts
  after the nonpersistent website data store has been cleared
- Shipping a desktop API key permits extraction from the app bundle. Restrict
  the key by API and quota; a production backend is recommended for stronger
  credential control
- The Made for Kids preflight sends that key in the `X-Goog-Api-Key` request
  header instead of placing it in the request URL

### Fixed

- Visibility changes no longer issue redundant YouTube Pause commands while
  the player is already cued or paused, and non-playing terminal states now
  acknowledge a pending Pause instead of blocking later official-player Play
- Native mute no longer sends a destructive zero-volume command to YouTube;
  the retained unmuted level remains available to both Reframer and the
  embedded player's own Unmute control
- Native M2V preflight now requests precise duration and timing metadata, so
  valid elementary MPEG-2 video streams reach the normal ready state
- Lock entry is disabled when no local source is loaded, including while a
  YouTube selection is pending; Unlock remains available from a locked state
- The YouTube web view now fills the complete video canvas at every supported
  window size, including the 200×200-point minimum required by the embedded
  player

## [0.10.0] - Unreleased

### Added

- Canonical command registry and single dispatcher for key, menu, and global
  input
- Shortcut validation, clear/disable/reset behavior, persistence migration,
  registered-hot-key conflict status, and deterministic command tests
- Desired-sample playback cursor, generation-scoped async work, sample-aligned
  final scrubs after exact indexing, labeled estimated fallback,
  load/error/end-state handling, and media preflight
- Bounded exact-sample indexing with a 2,000,000-sample ceiling and coherent
  multi-track playback, metadata, and navigation selection
- Keyboard and VoiceOver semantics for the empty state, toolbar, filters,
  panels, overlays, and status
- Reduce Motion and multi-display-safe presentation behavior
- Machine-readable product contract and repository/bundle validators
- Separate CI and interactive macOS UI-test workflows
- Developer ID/notarization release pipeline with universal-binary,
  Hardened Runtime, entitlement, stapling, Gatekeeper, checksum, and
  notarization-record verification
- Modern CoreSpotlight Apple Help index plus exact runtime-resource and Help
  bundle allowlists
- A documented all-synthetic media fixture corpus with real MP4, MOV, M4V,
  fractional-rate, variable-rate, and audio-only coverage
- MIT license and security/threat-model documentation

### Changed

- Minimum system and public documentation are aligned at macOS 15.0
- Shipping containers are explicitly MP4, M4V, and MOV through AVFoundation
- Page Down advances and Page Up reverses
- Global frame-step chords are registered only for a loaded, locked video with
  exact or estimated sample navigation, so inactive chords remain available to
  other apps
- Frame navigation uses decoded sample timing instead of rounded nominal-rate
  arithmetic after exact indexing; during indexing or a bounded fallback, the
  UI identifies the constant-rate estimate
- Video and controls now share one canonical externally managed overlay
  window, so macOS and third-party window managers move and resize the complete
  unlocked interface
- The control bar now uses one 48-point row at widths of 920 points or more and
  two rows totaling 96 points below that breakpoint. The window prefers 1,060
  points, supports a 640-point minimum, and keeps every control visible and
  accessibility-reachable in both layouts
- The preference formerly labeled Always on Top is now explicitly Always on
  Top When Unlocked; lock mode independently forces the overlay above ordinary
  application windows
- Selecting a replacement video stops playback immediately and the replacement
  lands paused
- Playback is prepared as a selected-track composition, keeping Core Image
  filtering on the same source track as metadata and frame navigation,
  preserving only audio that overlaps that video timeline, and deriving
  display dimensions from the transformed frame bounds
- Quick filters use a native AppKit pop-up button, so primary-click menus,
  keyboard selection, and accessibility children follow platform behavior;
  advanced controls remain in a separate panel
- App resources are explicitly allowlisted; engineering reports remain outside
  the app bundle
- Version and build metadata now derive from Xcode build settings and include a
  source stamp

### Fixed

- Decorative edge and status overlays no longer block pointer input
- Opacity and other advertised preferences persist after relaunch
- Toolbar controls, including explicitly sized sliders, no longer clip at the
  minimum window size
- Rebinding a command removes its previous chord and prevents duplicate
  dispatch
- Held non-repeat shortcuts are consumed without leaking into AppKit menu
  key-equivalent autorepeat, while frame stepping and panning still repeat
- Unchanged registered hot keys and their held state survive actionable-state
  reconfiguration, preventing a held global lock chord from toggling twice
- Focused text editors retain held-key repetition; Tab remains reserved for
  focus traversal, and recorded Space/layout characters render correctly
- System file/alert sheets and keyboard-scrollable documentation retain their
  native Space, arrow, and navigation-key behavior
- Command-? opens Reframer documentation instead of AppKit Help-menu search;
  the bundled pages now render as nonblank native AppKit content without a
  sandboxed WebKit process or network entitlement, keep their native scrolling
  keys, and retain Escape as the contextual close command
- Lock mode now applies to the complete overlay, including the control bar:
  the window uses macOS's public status-bar tier above all ordinary application
  windows, including normal, floating, modal, and utility windows; ignores
  pointer input; and cannot be moved or resized until the enabled global lock
  shortcut restores interaction. System pop-up menus, drag UI, the screen
  saver, and assistive-technology UI remain above it
- Lock and unlock now apply their complete window policy synchronously on the
  AppKit main thread, so a queued Mosaic or Accessibility move/resize cannot
  slip between the state transition and the frozen/restored window geometry
- External window managers can no longer target and strand a separate control
  window while leaving the video behind
- Whole-overlay click-through cannot be entered unless the exact configured
  global Lock/Unlock chord is registered. Registration loss, conflict,
  recording suspension, or disabling global shortcuts automatically unlocks
  the overlay and presents recovery guidance
- Escape closes the key/frontmost auxiliary panel instead of an unrelated
  background panel
- Focused buttons and generic controls no longer swallow plain or Shift-based
  Reframer shortcuts they do not own
- Mixed-file drops validate and open the same first supported video
- Borderless windows have user-facing accessibility names, dynamic failures
  are announced, and display accommodations update while the app is running
- Sliders expose role, value, range, and orientation; editable numeric fields
  expose their native text-field role; ready-state badges are individually
  reachable; and the empty-state Open action reports enabled
- Minimum-width toolbar layout and long frame-count status remain visible
- Stale load, seek, scrub, and filter completions cannot overwrite newer state
- Playback intent is now main-thread-owned and revisioned. A delayed AVPlayer
  playing callback cannot resurrect playback after a rapid play-then-pause
  command
- A generation-scoped two-second startup gate protects Play from transient
  paused callbacks, settles when AVPlayer reaches playing, and returns the model
  to Paused when AVPlayer has settled paused after the bounded grace period and
  no authorized seek or scrub handoff is pending
- EOF-replay and scrub seek completions resume only when their captured
  playback-intent revision is still current; a newer Pause always wins, while a
  newer Play reauthorizes the existing seek instead of starting a competing
  transport operation
- AVPlayer transport is forced paused during scrubbing and playback-seek
  handoffs, including when a delayed playing callback arrives; scrub end hands
  off synchronously without an unprotected pause window
- Ended playback can replay from the beginning
- UI tests run serially and no longer mutate macOS privacy or signing state
- Unit tests use minimum-Xcode-compatible weak-reference syntax
- The UI runner forwards its explicit operator acknowledgement into XCTest
  without relying on empty-array behavior that differs in macOS Bash
- Repository validation uses stock macOS system tools and no longer assumes a
  separately installed `ripgrep` executable on hosted runners
- Stapled review artifacts recognize Apple’s top-level `CodeResources` ticket
  only when `stapler` validates it, and the final ZIP is extracted and
  rechecked for bundle, signature, ticket, and Gatekeeper integrity
- Release packaging confines DerivedData to its scoped temporary directory and
  unregisters intermediate apps during cleanup, preventing old build products
  from reappearing in LaunchServices or Spotlight; bundle validation also
  rejects stale build numbers and dirty-stamped release artifacts, while local
  packaging requires clean `main` source matching `origin/main`
- The background test runner now unregisters every temporary Reframer app and
  removes its sentinel-owned DerivedData on success, failure, or interruption,
  so validation cannot repopulate Spotlight with retained test builds

### Security

- Removed the obsolete library-validation exception
- Replaced broad global keyboard monitoring with exact, exclusive registered
  hot keys that require no Accessibility or Input Monitoring permission
- Enabled App Sandbox with user-selected, read-only video access
- Kept bundled documentation offline and native instead of adding a network
  entitlement to make a sandboxed WebKit helper launch
- Removed scripts that wrote to privacy databases, restarted privacy services,
  stripped provenance, or re-signed test products
- Pinned GitHub Actions to reviewed immutable commits, disabled persisted
  checkout credentials, moved checkout and artifact upload to their Node 24
  releases, and limited write access to the release job while declaring the
  externally protected release-environment gate
- Restricted all release entry points to commits on `origin/main`, made tag
  changelog validation exact, protected temporary credentials, and expanded
  bundle validation to reject symlinks, unexpected signature contents, or
  unexpected executable-bearing paths
- Reverified the release checkout and remote tag target against the immutable
  workflow event commit immediately before publication
- Documented keyboard and file-access trust boundaries and release gates

## Development snapshots

The prior 0.1, 0.8, and 0.9 repository snapshots established the AppKit
overlay, playback controls, zoom/pan, filters, persistence, initial configurable
shortcuts, help content, and early tests. Their feature reports are preserved under
`docs/archive/legacy-implementation/` and do not define current behavior.
