# Changelog

Notable Reframer changes are recorded here. The project uses semantic
versioning once a build is published; earlier repository milestones were
development snapshots, not production releases.

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
