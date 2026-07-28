# Reframer remediation progress

## 2026-07-28

- Confirmed clean current `main` at `82f9dc4`.
- Completed end-to-end audit: 6 critical, 12 high, and 6 medium findings.
- Started mission `reframer-first-class-20260728`.
- Created isolated worktrees for playback, shortcuts, and UX/accessibility.
- Integration/release track owns documentation truth, CI, metadata, security, packaging, and final validation.
- Froze the 0.10.0 product contract: macOS 15.0+, MP4/M4V/MOV, conventional Page direction, guarded global stepping, local/offline processing.
- Reconciled root/nested README, current feature/test docs, DocC, Apple Help, version metadata, and the Help search index.
- Archived stale implementation reports outside the current documentation surface and removed internal docs from the app target.
- Rebuilt CI around explicit project paths, Debug/Release builds, static analysis, unit tests, DocC, XIB checks, and bundle validation.
- Added a separate serial UI-test workflow for a logged-in macOS runner whose
  operator has acknowledged Xcode UI automation.
- Removed runner code that edited privacy databases, restarted privacy services, removed provenance, or re-signed build products.
- Added Hardened Runtime release packaging, Developer ID verification, notarization, stapling, Gatekeeper assessment, license, and security policy.
- Integrated multi-display geometry with seven focused unit tests.
- Repaired the click-through edge indicator, keyboard/VoiceOver drop zone, conventional quick-filter menu, and Reduce Motion behavior.
- Normalized the child control window and XIB to a single 48-point layout, removed every Interface Builder clipping notice, and added control labels, help, state values, tooltips, focus visibility, and frame-entry clamping.
- Verified the integration branch builds and passes repository, XIB, and built-bundle validation.
- Replaced nominal-frame-rate arithmetic with exact presentation-order sample indexing, including edit-list source-to-player timeline mapping and stale-seek generation guards.
- Preserved the latest requested presentation time and replay intent when an
  estimated index is replaced by the exact VFR index; the remapped seek gets a
  new generation and stale estimated completions cannot clear it.
- Moved security-scoped access into one ARC-backed lease per load. Replacement
  access is acquired before old teardown, asynchronous load/seek/composition
  work retains its lease, and release occurs only after the AV graph and
  cancelling work finish.
- Added explicit scrub begin/preview/end semantics, EOF replay, AVPlayer truth observation, finite metadata validation, and a single generation-scoped loading/failure recovery surface.
- Replaced deprecated CFR-forcing filter composition with a source-timing-preserving, snapshot-driven filter pipeline and paused-frame refresh.
- Persisted and sanitized opacity, quick/advanced filters, and every filter parameter using isolated preference tests.
- Narrowed runtime media preflight to readable, playable, unprotected MP4/M4V/MOV assets with a real video track.
- Made the deterministic unit runner independent of Xcode's unreliable local
  test-worker launcher; the complete current unit suite passed with zero
  failures.
- Registered exact global chords through Carbon instead of broad keyboard
  observation. The lock chord remains available during normal operation; the
  four frame-step variants register only while a loaded, locked video has exact
  or estimated frame navigation and are absent otherwise.
- Unified local, menu, and registered-hot-key dispatch with state-aware command
  availability, focused-control ownership, customizable validated bindings,
  conflict/retry status, and relaunch persistence.
- Completed pointer-transparent status overlays, dedicated window dragging,
  primary-button video panning, keyboard/VoiceOver movement, multi-display
  recovery, panel focus, conventional filters, and Reduce Motion behavior.
- Reworked the UI target to use isolated preferences and Launch Services
  fixture opening. Its compiled assertions cover active and global frame steps
  in both directions and one/ten factors, exactly-once delivery, the unlocked
  no-swallow state, F and Command-?, focused filter activation, and
  rebind/persist/disable behavior.

## Validation recorded

- `scripts/validate_repository.sh` passed, including product-contract, plist,
  scheme, XIB, resource, workflow, entitlement, and documentation checks.
- The deterministic unit runner passed all 162 integrated tests with zero
  failures or unexpected results.
- Debug and universal arm64/x86_64 Release builds passed.
- Static analysis and DocC builds passed.
- The XIB compiled with zero errors, warnings, or notices.
- Built-bundle validation and an unsigned universal archive passed; the bundle
  contains only the intended runtime resources.
- `build-for-testing` compiled the complete unit and UI targets.
- A locally signed Debug bundle passed code-signing and entitlement inspection,
  but that ad hoc/development result is not a Developer ID distribution
  signature.

## Outstanding external evidence

- The UI test suite has not been recorded as executed. Its preflight correctly
  exited 77 because `REFRAMER_UI_RUNNER_AUTHORIZED=1` was not acknowledged.
  Reframer itself requires neither Input Monitoring nor Accessibility
  permission. A separate live-app inspection attempt was blocked by the locked
  macOS desktop.
- A future unlocked, logged-in Xcode UI-automation session must execute the UI
  suite and complete the live interaction, visual, multi-display, and
  VoiceOver walkthroughs listed in `docs/FEATURE_TESTS.md`.
- Developer ID distribution signing, Apple notarization, stapling, and
  Gatekeeper assessment were not run because Apple credentials were
  unavailable. The release pipeline is implemented, but these remain required
  external release-acceptance gates.
